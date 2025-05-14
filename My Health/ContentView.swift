//
//  ContentView.swift
//  My Health
//
//  Created by Jonathan Milligan on 10/15/24.
//

import Charts
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
        NavigationView {
            VStack {
                if bleManager.isScanning {
                    ProgressView("Scanning for devices...")
                        .padding()
                } else {
                    Button(action: {
                        bleManager.startScanning()
                    }) {
                        Label("Start Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, maxHeight: 30.0)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                    if bleManager.connectedPeripheral == nil, !bleManager.address.isEmpty {
                        Button(action: {
                            bleManager.reconnectToLastDevice()
                        }) {
                            Label("Reconnect to Ring", systemImage: "arrow.clockwise.circle")
                                .frame(maxWidth: .infinity, maxHeight: 30.0)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                    }
                }

                List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peripheral.name ?? "Unknown Device")
                                .font(.headline)
                            Text(peripheral.identifier.uuidString)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("Connect") {
                            bleManager.connect(peripheral: peripheral)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .listStyle(.insetGrouped)

                if let connectedPeripheral = bleManager.connectedPeripheral {
                    VStack {
                        Text("Connected to: \(connectedPeripheral.name ?? "Device")")
                            .font(.headline)
                            .padding(.top)
                        Button("Disconnect") {
                            bleManager.disconnect()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding()
                }

                // Text("Raw Data: \(bleManager.receivedData)") // Debug display - consider removing or placing elsewhere
            }
            .navigationTitle("Device Scanning")
        }
    }
}

struct DataDisplayView: View {
    @ObservedObject var bleManager: ColmiR02Client
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HeartRateData.timestamp, order: .reverse) private var heartRateData: [HeartRateData]
    @Query(sort: \BloodOxygenData.timestamp, order: .reverse) private var bloodOxygenData: [BloodOxygenData]

    @State private var batteryInfoString: String = "N/A"
    @State private var batteryCharging: Bool? = nil

    var body: some View {
        NavigationView {
            List {
                Section("Device Information") {
                    HStack {
                        Text("Battery:")
                        Spacer()
                        Text(batteryInfoString)
                        if let charging = batteryCharging {
                            Image(systemName: charging ? "bolt.fill" : "bolt")
                        }
                    }
                    Button("Refresh Battery Status") {
                        Task {
                            do {
                                let batteryInfo = try await bleManager.getBattery()
                                batteryInfoString = "\(batteryInfo.batteryLevel)%"
                                batteryCharging = batteryInfo.charging
                            } catch {
                                batteryInfoString = "Error: \(error.localizedDescription)"
                            }
                        }
                    }
                    Button("Log Current Health Data") {
                        Task {
                            await HealthDataLogger.shared.logCurrentHealthData(
                                bleManager: bleManager, modelContext: modelContext
                            )
                        }
                    }
                }

                Section("Logged Data Chart") {}

                Section("Logged Heart Rate") {
                    ForEach(heartRateData) { data in
                        HStack {
                            Text("Time: \(data.timestamp, style: .time)")
                            Spacer()
                            Text("\(data.heartRate) bpm")
                        }
                    }.onDelete(perform: deleteHeartRateData)
                }

                Section("Logged Blood Oxygen") {
                    ForEach(bloodOxygenData) { data in
                        HStack {
                            Text("Time: \(data.timestamp, style: .time)")
                            Spacer()
                            Text("\(data.bloodOxygen)%")
                        }
                    }.onDelete(perform: deleteBloodOxygenData)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Health Data")
        }
    }

    private func deleteHeartRateData(offsets: IndexSet) {
        withAnimation {
            offsets.map { heartRateData[$0] }.forEach(modelContext.delete)
        }
    }

    private func deleteBloodOxygenData(offsets: IndexSet) {
        withAnimation {
            offsets.map { bloodOxygenData[$0] }.forEach(modelContext.delete)
        }
    }
}

struct SettingsView: View {
    @Binding var healthKitAuthorized: Bool

    var body: some View {
        NavigationView {
            List {
                Section("Integrations") {
                    HStack {
                        Text("HealthKit Access")
                        Spacer()
                        Text(healthKitAuthorized ? "Granted" : "Not Granted")
                            .foregroundColor(healthKitAuthorized ? .green : .red)
                    }
                }
                // Add other settings sections and options here
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [HeartRateData.self, BloodOxygenData.self], inMemory: true)
}
