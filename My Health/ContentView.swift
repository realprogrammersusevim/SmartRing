//
//  ContentView.swift
//  My Health
//
//  Created by Jonathan Milligan on 10/15/24.
//

import HealthKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var bleManager: BLEManager
    @State private var healthKitAuthorized = false

    init() {
        _bleManager = ObservedObject(
            wrappedValue: BLEManager(
                serviceUUID: "6e40fff0-b5a3-f393-e0a9-e50e24dcca9e",
                dataCharacteristicUUID: "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
            ))
    }

    var body: some View {
        TabView {
            ScanningView(bleManager: bleManager)
                .tabItem { Label("Scan", systemImage: "magnifyingglass") }

            DataDisplayView()
                .tabItem { Label("Data", systemImage: "list.bullet.rectangle") }

            SettingsView(healthKitAuthorized: $healthKitAuthorized)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            HealthKitManager.shared.requestAuthorization { success, error in
                healthKitAuthorized = success
                if success {
                    print("HealthKit Authorization Granted.")
                } else if let error {
                    print("HealthKit Authorization Failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct ScanningView: View {
    @ObservedObject var bleManager: BLEManager

    var body: some View {
        VStack {
            Text("Bluetooth Device Scanning")
                .font(.title)

            if bleManager.isScanning {
                ProgressView("Scanning for devices...")
            } else {
                Button("Start Scan") {
                    bleManager.startScanning()
                }
            }

            List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                HStack {
                    Text(peripheral.name ?? "Unknown Device")
                    Spacer()
                    Button("Connect") {
                        bleManager.connect(peripheral: peripheral)
                    }
                }
            }

            if bleManager.connectedPeripheral != nil {
                Text("Connected to: \(bleManager.connectedPeripheral?.name ?? "Device")")
                Button("Disconnect") {
                    bleManager.disconnect()
                }
            }

            Text("Raw Data: \($bleManager.receivedData)") // Debug display
        }
        .padding()
    }
}

struct DataDisplayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var heartRateData: [HeartRateData]
    @Query private var bloodOxygenData: [BloodOxygenData]

    var body: some View {
        VStack {
            Text("Logged Data")
                .font(.title)

            List {
                Section("Heart Rate") {
                    ForEach(heartRateData) { data in
                        HStack {
                            Text("Time: \(data.timestamp, style: .time)")
                            Spacer()
                            Text("\(data.heartRate) bpm")
                        }
                    }
                }
                Section("Blood Oxygen") {
                    ForEach(bloodOxygenData) { data in
                        HStack {
                            Text("Time: \(data.timestamp, style: .time)")
                            Spacer()
                            Text("\(data.bloodOxygen) blood oxygen")
                        }
                    }
                }
                // ... Display other data types
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @Binding var healthKitAuthorized: Bool

    var body: some View {
        VStack {
            Text("Settings")
                .font(.title)
            HStack {
                Text("HealthKit Access:")
                Spacer()
                Text(healthKitAuthorized ? "Granted" : "Not Granted")
            }
            // ... Add other settings options
        }
        .padding()
    }
}

// Function to log heart rate to SwiftData and HealthKit
func logHeartRate(heartRate: Int) {
    @Environment(\.modelContext) var modelContext

    Task { @MainActor in // Ensure SwiftData operations on main actor
        do {
            let newData = HeartRateData(timestamp: Date(), heartRate: heartRate)
            modelContext.insert(newData)
            try modelContext.save()
            print("Heart rate logged to SwiftData.")

            if HealthKitManager.shared.healthStore.authorizationStatus(
                for: HKQuantityType.quantityType(forIdentifier: .heartRate)!) == .sharingAuthorized
            {
                HealthKitManager.shared.saveHeartRate(
                    heartRate: heartRate, timestamp: newData.timestamp
                )
            } else {
                print(
                    "HealthKit authorization not granted for Heart Rate, skipping HealthKit save.")
            }

        } catch {
            print("Error logging heart rate to SwiftData: \(error)")
        }
    }
}

// Function to log blood oxygen count (example) - adapt for other data types
func logBloodOxygen(bloodOxygen: Int) {
    @Environment(\.modelContext) var modelContext

    Task { @MainActor in
        do {
            let newData = BloodOxygenData(timestamp: Date(), bloodOxygen: bloodOxygen)
            modelContext.insert(newData)
            try modelContext.save()
            print("Blood oxygen logged to SwiftData.")

            if HealthKitManager.shared.healthStore.authorizationStatus(
                for: HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!)
                == .sharingAuthorized
            {
                HealthKitManager.shared.saveBloodOxygen(
                    bloodOxygen: bloodOxygen, timestamp: newData.timestamp
                )
            } else {
                print(
                    "HealthKit authorization not granted for Blood Oxygen, skipping HealthKit save."
                )
            }

        } catch {
            print("Error logging blood oxygen to SwiftData: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [HeartRateData.self, BloodOxygenData.self], inMemory: true)
}
