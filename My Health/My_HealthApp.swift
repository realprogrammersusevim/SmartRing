//
//  My_HealthApp.swift
//  My Health
//
//  Created by Jonathan Milligan on 10/15/24.
//

import BackgroundTasks // Import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct My_HealthApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let healthDataLogger = HealthDataLogger.shared
    let backgroundTaskIdentifier = "com.health.jonathan.logHealthData"

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
            if newPhase == .background {
                print("App moved to background, scheduling health data log task.")
                scheduleHealthDataLogTask()
            }
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            print("Background task \(backgroundTaskIdentifier) starting.")
            handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleHealthDataLogTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        // Fetch data approximately every 15 minutes. iOS will adjust this based on system conditions.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

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
        scheduleHealthDataLogTask()

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
        let ringManager = ColmiR02Client(address: deviceAddressForBackgroundTask)

        task.expirationHandler = {
            print("Background task \(backgroundTaskIdentifier) expired.")
            // ringManager.disconnect() // Consider disconnecting if appropriate
            task.setTaskCompleted(success: false)
        }

        Task {
            await healthDataLogger.logCurrentHealthData(bleManager: ringManager, modelContext: modelContext)
            // ringManager.disconnect() // Consider if disconnect is needed after background fetch
            print("Background task \(backgroundTaskIdentifier) work finished processing.")
            task.setTaskCompleted(success: true) // Mark success after async operations complete
        }
    }
}
