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
        let storedAddress = UserDefaults.standard.string(
            forKey: lastConnectedPeripheralIdentifierKey)
        let deviceAddressForBackgroundTask = storedAddress ?? "D890C620-D962-42FA-A099-81A4F7605434" // Fallback
        let ringManager = ColmiR02Client(address: deviceAddressForBackgroundTask)

        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1 // Process sequentially

        let fetchHeartRateOperation = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)
            ringManager.getRealtimeReading(readingType: .heartRate) { result in
                switch result {
                case let .success(reading):
                    print("Background task: Fetched heart rate: \(reading.value)")
                    logHeartRate(heartRate: reading.value, modelContext: modelContext)
                case let .failure(error):
                    print("Background task: Failed to fetch heart rate: \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait() // Wait for the async operation to complete
        }

        let fetchBloodOxygenOperation = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)
            ringManager.getRealtimeReading(readingType: .spo2) { result in
                switch result {
                case let .success(reading):
                    print("Background task: Fetched SpO2: \(reading.value)")
                    logBloodOxygen(bloodOxygen: reading.value, modelContext: modelContext)
                case let .failure(error):
                    print("Background task: Failed to fetch SpO2: \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait() // Wait for the async operation to complete
        }

        fetchBloodOxygenOperation.addDependency(fetchHeartRateOperation)
        operationQueue.addOperation(fetchHeartRateOperation)
        operationQueue.addOperation(fetchBloodOxygenOperation)

        task.expirationHandler = {
            print("Background task \(backgroundTaskIdentifier) expired.")
            operationQueue.cancelAllOperations()
            // ringManager.disconnect() // Consider disconnecting if appropriate
            task.setTaskCompleted(success: false)
        }

        operationQueue.addBarrierBlock {
            // This block runs after all operations in the queue are finished.
            // ringManager.disconnect() // Consider disconnecting if appropriate
            print("Background task \(backgroundTaskIdentifier) work finished.")
            task.setTaskCompleted(success: true)
        }
    }
}
