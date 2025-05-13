//
//  My_HealthApp.swift
//  My Health
//
//  Created by Jonathan Milligan on 10/15/24.
//

import BackgroundTasks // Import BackgroundTasks
import SwiftData
import SwiftUI

let BG_INTERVAL: TimeInterval = 10 * 60

@main
struct My_HealthApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let healthDataLogger = HealthDataLogger.shared
    let backgroundTaskIdentifier = "com.health.jonathan.logHealthData"

    // Static timer for foreground data logging
    private static var appForegroundLogTimer: Timer?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HeartRateData.self,
            BloodOxygenData.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // Capture necessary instances for static methods or ensure they can be accessed globally
            let currentHealthDataLogger = healthDataLogger // HealthDataLogger.shared could also be used directly in static func
            let currentModelContainer = sharedModelContainer

            if newPhase == .active {
                print("App became active. Starting foreground health data logging.")
                My_HealthApp.stopForegroundLogTimer() // Stop any existing timer
                My_HealthApp.startForegroundLogTimer(
                    healthDataLogger: currentHealthDataLogger,
                    modelContainer: currentModelContainer
                )
            } else if newPhase == .inactive {
                print("App became inactive. Stopping foreground health data logging.")
                My_HealthApp.stopForegroundLogTimer()
            } else if newPhase == .background {
                print("App moved to background, scheduling health data log task.")
                My_HealthApp.stopForegroundLogTimer() // Stop foreground timer
                scheduleHealthDataLogTask()
            }
        }
    }

    // Static method to start the foreground timer
    static func startForegroundLogTimer(healthDataLogger: HealthDataLogger, modelContainer: ModelContainer) {
        appForegroundLogTimer?.invalidate() // Invalidate existing timer just in case

        let logAction = {
            Task {
                print("Foreground timer: Logging health data.")
                // Create a new ModelContext for this operation.
                let context = ModelContext(modelContainer)

                // Use stored address, fallback to default if not found
                let deviceAddress = DeviceSettingsManager.shared.getTargetDeviceAddress()

                // Create the BLE manager outside the task to give it time to initialize
                let ringManager = ColmiR02Client(address: deviceAddress) // Creates a new client for this operation

                do {
                    // Add a small delay to allow the BLE manager to initialize
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

                    // Connect to the device first
                    try await ringManager.connectAndPrepare()

                    // Now log the health data
                    await healthDataLogger.logCurrentHealthData(bleManager: ringManager, modelContext: context)
                    print("Foreground timer: Health data logging complete.")

                    // Disconnect when done
                    ringManager.disconnect()
                } catch {
                    print("Foreground timer: Failed to connect or log data: \(error.localizedDescription)")
                }
            }
        }

        // Perform an initial log right away when app becomes active / timer starts
        logAction()

        // Schedule a new timer for repeated logging
        appForegroundLogTimer = Timer.scheduledTimer(withTimeInterval: BG_INTERVAL, repeats: true) { _ in
            logAction()
        }
        print("Foreground health data log timer started. Will fire every \(BG_INTERVAL.description) after an initial log.")
    }

    // Static method to stop the foreground timer
    static func stopForegroundLogTimer() {
        appForegroundLogTimer?.invalidate()
        appForegroundLogTimer = nil
        print("Foreground health data log timer stopped.")
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            print("Background task \(backgroundTaskIdentifier) starting.")
            handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleHealthDataLogTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Fetch data. iOS will adjust this based on system conditions.
        request.earliestBeginDate = Date(timeIntervalSinceNow: BG_INTERVAL)

        do {
            try BGTaskScheduler.shared.submit(request)
            print(
                "Submitted background task: \(backgroundTaskIdentifier) to run after \(request.earliestBeginDate?.description ?? "N/A")"
            )
        } catch {
            print("Could not schedule app refresh task \(backgroundTaskIdentifier): \(error)")
        }
    }

    func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh task
        scheduleHealthDataLogTask() // Instance method call

        // Create a new ModelContainer and ModelContext for this background task
        let schema = Schema([HeartRateData.self, BloodOxygenData.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        guard let container = try? ModelContainer(for: schema, configurations: [modelConfiguration])
        else {
            print("Background task: Failed to create ModelContainer.")
            task.setTaskCompleted(success: false)
            return
        }
        let modelContext = ModelContext(container)

        // Use stored address for background tasks, fallback to default if not found
        let deviceAddressForBackgroundTask = DeviceSettingsManager.shared.getTargetDeviceAddress()
        // Use the instance's healthDataLogger (which is HealthDataLogger.shared)
        let currentHealthDataLogger = healthDataLogger
        let ringManager = ColmiR02Client(address: deviceAddressForBackgroundTask)

        task.expirationHandler = {
            print("Background task \(backgroundTaskIdentifier) expired.")
            // ringManager.disconnect() // Consider disconnecting if appropriate
            task.setTaskCompleted(success: false)
        }

        Task {
            defer {
                // Ensure the client is disconnected after the background work is done or if an error occurs
                print("Background task: Disconnecting ColmiR02Client.")
                ringManager.disconnect()
            }
            do {
                print("Background task: Attempting to connect and prepare ColmiR02Client.")
                try await ringManager.connectAndPrepare() // Wait for connection and readiness
                print("Background task: ColmiR02Client connected and prepared. Logging health data.")

                await currentHealthDataLogger.logCurrentHealthData(bleManager: ringManager, modelContext: modelContext)

                print("Background task \(backgroundTaskIdentifier) work finished processing.")
                task.setTaskCompleted(success: true)
            } catch {
                print("Background task: Failed to connect or log data: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
