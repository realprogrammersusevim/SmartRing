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
    @ObservedObject var ringManager: ColmiR02Client
    @State private var healthKitAuthorized = false

    init() {
        let storedAddress = UserDefaults.standard.string(forKey: lastConnectedPeripheralIdentifierKey)
        let initialAddress = storedAddress ?? "D890C620-D962-42FA-A099-81A4F7605434" // Fallback to default
        _ringManager = ObservedObject(
            wrappedValue: ColmiR02Client(address: initialAddress)
        )
    }

    var body: some View {
        TabView {
            ScanningView(bleManager: ringManager)
                .tabItem { Label("Scan", systemImage: "magnifyingglass") }

            DataDisplayView(bleManager: ringManager)
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
    @ObservedObject var bleManager: ColmiR02Client

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

            Text("Raw Data: \(bleManager.receivedData)") // Debug display
        }
        .padding()
    }
}

struct DataDisplayView: View {
    @ObservedObject var bleManager: ColmiR02Client

    @Environment(\.modelContext) private var modelContext
    @Query private var heartRateData: [HeartRateData]
    @Query private var bloodOxygenData: [BloodOxygenData]

    @State private var batteryInfoString: String = "N/A"

    var body: some View {
        VStack {
            Text("Info")
                .font(.title)
            List {
                Text("Battery: \(batteryInfoString)")
                Button("Get Battery") {
                    bleManager.getBattery { result in
                        DispatchQueue.main.async { // Ensure UI updates on main thread
                            switch result {
                            case let .success(batteryInfo):
                                batteryInfoString = "\(batteryInfo.batteryLevel)% (Charging: \(batteryInfo.charging ? "Yes" : "No"))"
                            case let .failure(error):
                                batteryInfoString = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                Button("Log Data Now") {
                    // Fetch Heart Rate
                    bleManager.getRealtimeReading(readingType: .heartRate) { hrResult in
                        DispatchQueue.main.async {
                            switch hrResult {
                            case let .success(hrReading):
                                print("Manual Log: Fetched heart rate: \(hrReading.value)")
                                logHeartRate(heartRate: hrReading.value, modelContext: modelContext)

                                // Fetch Blood Oxygen after heart rate
                                bleManager.getRealtimeReading(readingType: .spo2) { spo2Result in
                                    DispatchQueue.main.async {
                                        switch spo2Result {
                                        case let .success(spo2Reading):
                                            print("Manual Log: Fetched SpO2: \(spo2Reading.value)")
                                            logBloodOxygen(bloodOxygen: spo2Reading.value, modelContext: modelContext)
                                        case let .failure(error):
                                            print("Manual Log: Failed to fetch SpO2: \(error.localizedDescription)")
                                        }
                                    }
                                }
                            case let .failure(error):
                                print("Manual Log: Failed to fetch heart rate: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
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
func logHeartRate(heartRate: Int, modelContext: ModelContext) {
    Task { @MainActor in
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
func logBloodOxygen(bloodOxygen: Int, modelContext: ModelContext) {
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
