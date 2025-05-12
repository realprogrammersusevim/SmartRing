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
    private let healthDataLogger = HealthDataLogger.shared
    @State private var healthKitAuthorized = false

    init() {
        let initialAddress = DeviceSettingsManager.shared.getTargetDeviceAddress()
        _ringManager = ObservedObject(wrappedValue: ColmiR02Client(address: initialAddress))
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
                    Task {
                        do {
                            let batteryInfo = try await bleManager.getBattery()
                            batteryInfoString = "\(batteryInfo.batteryLevel)% (Charging: \(batteryInfo.charging ? "Yes" : "No"))"
                        } catch {
                            batteryInfoString = "Error: \(error.localizedDescription)"
                        }
                    }
                }
                Button("Log Data Now") {
                    Task {
                        await HealthDataLogger.shared.logCurrentHealthData(
                            bleManager: bleManager, modelContext: modelContext
                        )
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

#Preview {
    ContentView()
        .modelContainer(for: [HeartRateData.self, BloodOxygenData.self], inMemory: true)
}
