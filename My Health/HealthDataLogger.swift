//
//  HealthDataLogger.swift
//  My Health
//
//  Created by Jonathan Milligan on 05/12/2025.
//

import Foundation
import HealthKit
import SwiftData

class HealthDataLogger {
    static let shared = HealthDataLogger()

    private init() {}

    func logCurrentHealthData(bleManager: ColmiR02Client, modelContext: ModelContext) async {
        print("HealthDataLogger: Attempting to log current health data.")
        do {
            // Fetch Heart Rate
            let hrReading = try await bleManager.getRealtimeReading(readingType: .heartRate)
            print("HealthDataLogger: Fetched heart rate: \(hrReading.value)")
            await saveHeartRateToStores(
                heartRate: hrReading.value, timestamp: Date(), modelContext: modelContext
            )

            // Fetch Blood Oxygen
            let spo2Reading = try await bleManager.getRealtimeReading(readingType: .spo2)
            print("HealthDataLogger: Fetched SpO2: \(spo2Reading.value)")
            await saveBloodOxygenToStores(
                bloodOxygen: spo2Reading.value, timestamp: Date(), modelContext: modelContext
            )

            print("HealthDataLogger: Successfully logged current health data.")

        } catch {
            print(
                "HealthDataLogger: Error logging current health data: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func saveHeartRateToStores(heartRate: Int, timestamp: Date, modelContext: ModelContext) {
        do {
            let newData = HeartRateData(timestamp: timestamp, heartRate: heartRate)
            modelContext.insert(newData)
            try modelContext.save()
            print("HealthDataLogger: Heart rate logged to SwiftData.")

            if HealthKitManager.shared.healthStore.authorizationStatus(
                for: HKQuantityType.quantityType(forIdentifier: .heartRate)!) == .sharingAuthorized
            {
                HealthKitManager.shared.saveHeartRate(
                    heartRate: heartRate, timestamp: newData.timestamp
                )
            } else {
                print(
                    "HealthDataLogger: HealthKit authorization not granted for Heart Rate, skipping HealthKit save."
                )
            }
        } catch {
            print("HealthDataLogger: Error logging heart rate to SwiftData: \(error)")
        }
    }

    @MainActor
    private func saveBloodOxygenToStores(
        bloodOxygen: Int, timestamp: Date, modelContext: ModelContext
    ) {
        do {
            let newData = BloodOxygenData(timestamp: timestamp, bloodOxygen: bloodOxygen)
            modelContext.insert(newData)
            try modelContext.save()
            print("HealthDataLogger: Blood oxygen logged to SwiftData.")

            if HealthKitManager.shared.healthStore.authorizationStatus(
                for: HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!)
                == .sharingAuthorized
            {
                HealthKitManager.shared.saveBloodOxygen(
                    bloodOxygen: bloodOxygen, timestamp: newData.timestamp
                )
            } else {
                print(
                    "HealthDataLogger: HealthKit authorization not granted for Blood Oxygen, skipping HealthKit save."
                )
            }
        } catch {
            print("HealthDataLogger: Error logging blood oxygen to SwiftData: \(error)")
        }
    }
}
