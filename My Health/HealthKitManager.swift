//
//  HealthKitManager.swift
//  My Health
//
//  Created by Jonathan Milligan on 1/29/25.
//

import HealthKit

class HealthKitManager {
    static let shared = HealthKitManager()
    let healthStore = HKHealthStore()

    private init() {} // Singleton

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKitError", code: 0, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."]))
            return
        }

        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)! // Add more types as needed
            // ... Add other HealthKit data types you want to write
        ]

        let typesToRead: Set<HKObjectType> = [] // Read types if needed in the future

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) in
            completion(success, error)
        }
    }

    func saveHeartRate(heartRate: Int, timestamp: Date) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            print("Error: Heart rate type not available in HealthKit.")
            return
        }

        let heartRateQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: HKUnit.minute()), doubleValue: Double(heartRate))
        let heartRateSample = HKQuantitySample(type: heartRateType, quantity: heartRateQuantity, start: timestamp, end: timestamp)

        healthStore.save(heartRateSample) { (success, error) in
            if let error = error {
                print("Error saving heart rate to HealthKit: \(error.localizedDescription)")
            } else if success {
                print("Heart rate data saved to HealthKit.")
            }
        }
    }

    func saveBloodOxygen(bloodOxygen: Int, timestamp: Date) {
        guard let bloodOxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) else {
            print("Error: Blood Oxygen type not available in HealthKit.")
            return
        }

        let bloodOxygenQuantity = HKQuantity(unit: HKUnit.count(), doubleValue: Double(bloodOxygen))
        let bloodOxygenSample = HKQuantitySample(type: bloodOxygenType, quantity: bloodOxygenQuantity, start: timestamp, end: timestamp)

        healthStore.save(bloodOxygenSample) { (success, error) in
            if let error = error {
                print("Error saving blood oxygen to HealthKit: \(error.localizedDescription)")
            } else if success {
                print("Blood oxygen data saved to HealthKit.")
            }
        }
    }

    // ... Add functions to save other data types to HealthKit as needed
}
