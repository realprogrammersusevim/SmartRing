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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
