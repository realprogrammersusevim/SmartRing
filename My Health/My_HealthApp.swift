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

    // Shared function to perform the health data logging operation
    private static func performHealthDataLoggingOperation(
        healthDataLogger: HealthDataLogger,
        modelContainer: ModelContainer,
        deviceAddress: String,
        operationIdentifier: String
    ) async throws {
        print("\(operationIdentifier): Performing health data logging operation for address: \(deviceAddress)")
        let context = ModelContext(modelContainer)
        let ringManager = ColmiR02Client(address: deviceAddress)

        // Adding a small delay that was previously in the foreground timer logic,
        // right after client initialization and before connectAndPrepare.
        // This might help ensure the CBCentralManager (initialized within ColmiR02Client)
        // has settled before proceeding with connection attempts.
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay

        defer {
            // Ensure disconnection happens even if an error occurs during the operation,
            // but after all awaited operations within the main body of the function complete.
            print("\(operationIdentifier): Operation complete. Disconnecting ColmiR02Client.")
            ringManager.disconnect()
        }

        print("\(operationIdentifier): Attempting to connect and prepare ColmiR02Client.")
        try await ringManager.connectAndPrepare()
        print("\(operationIdentifier): ColmiR02Client connected and prepared. Logging health data.")
        await healthDataLogger.logCurrentHealthData(bleManager: ringManager, modelContext: context)
        print("\(operationIdentifier): Health data logging operation successful.")
    }

    // Static method to start the foreground timer
    static func startForegroundLogTimer(healthDataLogger: HealthDataLogger, modelContainer: ModelContainer) {
        appForegroundLogTimer?.invalidate()

        let logAction = {
            Task {
                let deviceAddress = DeviceSettingsManager.shared.getTargetDeviceAddress()
                do {
                    try await Self.performHealthDataLoggingOperation(healthDataLogger: healthDataLogger, modelContainer: modelContainer, deviceAddress: deviceAddress, operationIdentifier: "ForegroundTimer")
                } catch {
                    print("ForegroundTimer: Failed to log data: \(error.localizedDescription)")
                }
            }
        }

        // Perform an initial log right away when app becomes active / timer starts
        logAction()

        appForegroundLogTimer = Timer.scheduledTimer(withTimeInterval: BG_INTERVAL, repeats: true) { _ in
            logAction()
        }
        print("Foreground health data log timer started. Will fire every \(BG_INTERVAL) seconds after an initial log.")
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
        // Note: The original code created a modelContext here but it wasn't directly used if the logging function creates its own.
        // The new shared function `performHealthDataLoggingOperation` creates its own ModelContext from the passed ModelContainer.
        let schema = Schema([HeartRateData.self, BloodOxygenData.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        guard let backgroundModelContainer = try? ModelContainer(for: schema, configurations: [modelConfiguration])
        else {
            print("BackgroundTask: Failed to create ModelContainer.")
            task.setTaskCompleted(success: false)
            return
        }

        // Use stored address for background tasks, fallback to default if not found
        let deviceAddressForBackgroundTask = DeviceSettingsManager.shared.getTargetDeviceAddress()
        // Use the instance's healthDataLogger (which is HealthDataLogger.shared)
        let currentHealthDataLogger = healthDataLogger

        task.expirationHandler = {
            print("BackgroundTask (\(backgroundTaskIdentifier)): Expired.")
            // Disconnection is handled by the defer block in performHealthDataLoggingOperation
            task.setTaskCompleted(success: false)
        }

        Task {
            do {
                try await My_HealthApp.performHealthDataLoggingOperation(healthDataLogger: currentHealthDataLogger, modelContainer: backgroundModelContainer, deviceAddress: deviceAddressForBackgroundTask, operationIdentifier: "BackgroundTask")
                print("BackgroundTask (\(backgroundTaskIdentifier)): Work finished successfully.")
                task.setTaskCompleted(success: true)
            } catch {
                print("BackgroundTask (\(backgroundTaskIdentifier)): Failed to log data: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
