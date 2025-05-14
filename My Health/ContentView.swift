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
    @Query private var heartRateData: [HeartRateData]
    @Query private var bloodOxygenData: [BloodOxygenData]

    @State private var batteryInfoString: String = "N/A"
    init(bleManager: ColmiR02Client) {
        self.bleManager = bleManager
        let twentyFourHoursAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let heartRatePredicate = #Predicate<HeartRateData> { data in
            data.timestamp >= twentyFourHoursAgo
        }
        let bloodOxygenPredicate = #Predicate<BloodOxygenData> { data in
            data.timestamp >= twentyFourHoursAgo
        }

        var heartRateFetchDescriptor = FetchDescriptor<HeartRateData>(predicate: heartRatePredicate, sortBy: [SortDescriptor(\HeartRateData.timestamp, order: .reverse)])
        heartRateFetchDescriptor.fetchLimit = 30
        _heartRateData = Query(heartRateFetchDescriptor)

        var bloodOxygenFetchDescriptor = FetchDescriptor<BloodOxygenData>(predicate: bloodOxygenPredicate, sortBy: [SortDescriptor(\BloodOxygenData.timestamp, order: .reverse)])
        bloodOxygenFetchDescriptor.fetchLimit = 30
        _bloodOxygenData = Query(bloodOxygenFetchDescriptor)
    }

    @State private var batteryCharging: Bool? = nil
    @State private var hrLogSettingsEnabled: Bool = false
    @State private var hrLogIntervalSelection: Int = 5 // Default interval
    @State private var hrLogSettingsStatusMessage: String = "Tap 'Refresh' to load settings."
    @State private var isLoadingHRLogSettings: Bool = false
    let availableIntervals: [Int] = [5, 10, 15, 30, 60] // Common intervals in minutes

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
                    .disabled(bleManager.connectedPeripheral == nil)
                    Button("Log Current Health Data") {
                        Task {
                            await HealthDataLogger.shared.logCurrentHealthData(
                                bleManager: bleManager, modelContext: modelContext
                            )
                        }
                    }
                    .disabled(bleManager.connectedPeripheral == nil)
                }

                Section("Historical Data") {
                    Button("Fetch All Historical Heart Rate Data") {
                        Task {
                            print("Fetching all historical heart rate data...")
                            let calendar = Calendar.current
                            let today = calendar.startOfDay(for: Date())
                            for i in 0 ..< 7 {
                                if let targetDate = calendar.date(byAdding: .day, value: -i, to: today) {
                                    do {
                                        print("Fetching heart rate log for \(targetDate.formatted(date: .long, time: .omitted))...")
                                        let heartRateLog = try await bleManager.getHeartRateLog(targetDate: targetDate)
                                        if heartRateLog.size == 0 {
                                            continue
                                        }
                                        print("Successfully fetched HeartRateLog for \(targetDate.formatted(date: .long, time: .omitted)):")
                                        print("  Timestamp: \(heartRateLog.timestamp)")
                                        print("  Size: \(heartRateLog.size)")
                                        print("  Index: \(heartRateLog.index)")
                                        print("  Range: \(heartRateLog.range)")
                                        print("  Heart Rates with Times: \(heartRateLog.heartRatesWithTimes())")
                                    } catch {
                                        print("Error fetching heart rate log for \(targetDate.formatted(date: .long, time: .omitted)): \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                    .disabled(bleManager.connectedPeripheral == nil)
                }

                Section("Heart Rate Log Settings") {
                    if isLoadingHRLogSettings {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 5)
                            Text("Accessing device...")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    } else if !hrLogSettingsStatusMessage.isEmpty {
                        Text(hrLogSettingsStatusMessage)
                            .font(.caption)
                    }
                    HStack {
                        Text("Automatic Logging:")
                        Spacer()
                        Toggle("Enabled", isOn: $hrLogSettingsEnabled)
                            .labelsHidden()
                    }
                    .disabled(bleManager.connectedPeripheral == nil)

                    Picker("Logging Interval (minutes):", selection: $hrLogIntervalSelection) {
                        ForEach(availableIntervals, id: \.self) { interval in
                            Text("\(interval) min").tag(interval)
                        }
                    }
                    .disabled(bleManager.connectedPeripheral == nil || !hrLogSettingsEnabled) // Also disable if logging is off

                    Button("Refresh HR Log Settings") {
                        Task {
                            await fetchHRLogSettings()
                        }
                    }
                    .disabled(bleManager.connectedPeripheral == nil)
                    Button("Apply HR Log Settings") {
                        Task {
                            await applyHRLogSettings()
                            await fetchHRLogSettings()
                        }
                    }
                    .disabled(bleManager.connectedPeripheral == nil)
                }

                // Section("Logged Data Chart") {}

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

    private func fetchHRLogSettings() async {
        guard bleManager.connectedPeripheral != nil else {
            hrLogSettingsStatusMessage = "Not connected to device."
            return
        }
        isLoadingHRLogSettings = true
        hrLogSettingsStatusMessage = "" // Clear previous status, spinner will indicate loading

        do {
            let settings = try await bleManager.getHeartRateLogSettings()
            hrLogSettingsEnabled = settings.enabled
            if availableIntervals.contains(settings.interval) {
                hrLogIntervalSelection = settings.interval
            } else {
                // If the interval from the device isn't in our list, default or handle as error
                hrLogIntervalSelection = availableIntervals.first ?? 5 // Fallback
                print("Warning: Received interval \(settings.interval) not in availableIntervals. Defaulting.")
            }
            hrLogSettingsStatusMessage = "Enabled: \(settings.enabled ? "Yes" : "No"), Interval: \(settings.interval) min"
        } catch {
            hrLogSettingsStatusMessage = "Error fetching settings: \(error.localizedDescription)"
        }
        isLoadingHRLogSettings = false
    }

    private func applyHRLogSettings() async {
        guard bleManager.connectedPeripheral != nil else {
            hrLogSettingsStatusMessage = "Not connected to device."
            return
        }
        let newSettings = HeartRateLogSettings(enabled: hrLogSettingsEnabled, interval: hrLogIntervalSelection)
        isLoadingHRLogSettings = true
        hrLogSettingsStatusMessage = "" // Clear previous status

        do {
            _ = try await bleManager.setHeartRateLogSettings(settings: newSettings)
            hrLogSettingsStatusMessage = "Settings applied. Refresh to confirm."
        } catch {
            hrLogSettingsStatusMessage = "Error applying settings: \(error.localizedDescription)"
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
