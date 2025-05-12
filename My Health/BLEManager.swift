//
//  BLEManager.swift
//  My Health
//
//  Created by Jonathan Milligan on 1/29/25.
//

import Combine // Needed for ObservableObject
import CoreBluetooth
import Foundation

// MARK: - Constants and UUIDs

let UART_SERVICE_UUID_STRING = "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E"
let UART_RX_CHAR_UUID_STRING = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
let UART_TX_CHAR_UUID_STRING = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
let DEVICE_INFO_SERVICE_UUID_STRING = "0000180A-0000-1000-8000-00805F9B34FB"
let DEVICE_HW_VERSION_CHAR_UUID_STRING = "00002A27-0000-1000-8000-00805F9B34FB"
let DEVICE_FW_VERSION_CHAR_UUID_STRING = "00002A26-0000-1000-8000-00805F9B34FB"

let UART_SERVICE_UUID = CBUUID(string: UART_SERVICE_UUID_STRING)
let UART_RX_CHAR_UUID = CBUUID(string: UART_RX_CHAR_UUID_STRING)
let UART_TX_CHAR_UUID = CBUUID(string: UART_TX_CHAR_UUID_STRING)
let DEVICE_INFO_SERVICE_UUID = CBUUID(string: DEVICE_INFO_SERVICE_UUID_STRING)
let DEVICE_HW_VERSION_CHAR_UUID = CBUUID(string: DEVICE_HW_VERSION_CHAR_UUID_STRING)
let DEVICE_FW_VERSION_CHAR_UUID = CBUUID(string: DEVICE_FW_VERSION_CHAR_UUID_STRING)

let DEVICE_NAME_PREFIXES = [
    "R01", "R02", "R03", "R04", "R05", "R06", "R07", "R10",
    "COLMI", "VK-5098", "MERLIN", "Hello Ring", "RING1", "boAtring",
    "TR-R02", "SE", "EVOLVEO", "GL-SR2", "Blaupunkt", "KSIX RING",
]

// MARK: - UserDefaults Keys

let lastConnectedPeripheralNameKey = "lastConnectedPeripheralNameKey"
let lastConnectedPeripheralIdentifierKey = "lastConnectedPeripheralIdentifierKey"

// MARK: - Enums and Structs (Based on Python dataclasses and enums)

enum RealTimeReading: UInt8, CaseIterable {
    case heartRate = 1
    case bloodPressure = 2
    case spo2 = 3
    case fatigue = 4
    case healthCheck = 5
    case ecg = 7
    case pressure = 8
    case bloodSugar = 9
    case hrv = 10

    static let realTimeMapping: [String: RealTimeReading] = [
        "heart-rate": .heartRate,
        "blood-pressure": .bloodPressure,
        "spo2": .spo2,
        "fatigue": .fatigue,
        "health-check": .healthCheck,
        "ecg": .ecg,
        "pressure": .pressure,
        "blood-sugar": .bloodSugar,
        "hrv": .hrv,
    ]
}

enum Action: UInt8 {
    case start = 1
    case pause = 2
    case `continue` = 3
    case stop = 4
}

struct Reading {
    let kind: RealTimeReading
    let value: Int
}

struct ReadingError {
    let kind: RealTimeReading
    let code: Int
}

struct BatteryInfo {
    let batteryLevel: Int
    let charging: Bool
}

struct HeartRateLogSettings {
    let enabled: Bool
    let interval: Int // Interval in minutes
}

struct SportDetail {
    let year: Int
    let month: Int
    let day: Int
    let timeIndex: Int // time_index represents 15 minutes intervals within a day
    let calories: Int
    let steps: Int
    let distance: Int // Distance in meters

    var timestamp: Date {
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = timeIndex / 4
        dateComponents.minute = (timeIndex % 4) * 15
        dateComponents.timeZone = TimeZone(identifier: "UTC")

        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: dateComponents)!
    }
}

struct HeartRateLog {
    let heartRates: [Int]
    let timestamp: Date
    let size: Int
    let index: Int
    let range: Int

    func heartRatesWithTimes() -> [(Int, Date)] {
        addTimes(heartRates: heartRates, ts: timestamp)
    }
}

class NoData: Error {} // Representing NoData from Python

// MARK: - Packet Handling Functions (Based on packet.py)

func makePacket(command: UInt8, subData: [UInt8]? = nil) -> Data {
    var packet = Data(count: 16)
    packet[0] = command

    if let subData {
        assert(subData.count <= 14, "Sub data must be less than or equal to 14 bytes")
        for i in 0 ..< subData.count {
            packet[i + 1] = subData[i]
        }
    }
    packet[15] = checksum(packet: packet)
    return packet
}

func checksum(packet: Data) -> UInt8 {
    var sum: UInt32 = 0
    for byte in packet {
        sum += UInt32(byte)
    }
    return UInt8(sum & 255)
}

// MARK: - Parsing Functions (Based on Python parsing functions)

func parseBatteryData(packet: Data) -> BatteryInfo? {
    guard packet.count == 16, packet[0] == 0x03 else { // CMD_BATTERY = 3
        return nil
    }
    return BatteryInfo(batteryLevel: Int(packet[1]), charging: packet[2] != 0)
}

func parseRealTimeReadingData(packet: Data) -> Reading? {
    guard packet.count == 16, packet[0] == 105 else { // CMD_START_REAL_TIME = 105
        return nil
    }
    guard let kind = RealTimeReading(rawValue: packet[1]) else {
        return nil
    }
    let errorCode = packet[2]
    if errorCode != 0 {
        print("Real-time reading error code: \(errorCode)")
        return nil // Or return ReadingError if you want to handle errors explicitly
    }
    return Reading(kind: kind, value: Int(packet[3]))
}

func parseHeartRateLogSettingsData(packet: Data) -> HeartRateLogSettings? {
    guard packet.count == 16, packet[0] == 22 else { // CMD_HEART_RATE_LOG_SETTINGS = 22
        return nil
    }
    let rawEnabled = packet[2]
    var enabled = false
    if rawEnabled == 1 {
        enabled = true
    } else if rawEnabled == 2 {
        enabled = false
    } else {
        print("Warning: Unexpected value in enabled byte \(rawEnabled), defaulting to false")
    }
    return HeartRateLogSettings(enabled: enabled, interval: Int(packet[3]))
}

func parseSportDetailData(packet: Data) -> SportDetail? {
    guard packet.count == 16, packet[0] == 67 else { // CMD_GET_STEP_SOMEDAY = 67
        return nil
    }
    let year = bcdToDecimal(packet[1]) + 2000
    let month = bcdToDecimal(packet[2])
    let day = bcdToDecimal(packet[3])
    let timeIndex = Int(packet[4])
    let calories = Int(packet[7]) | (Int(packet[8]) << 8)
    let steps = Int(packet[9]) | (Int(packet[10]) << 8)
    let distance = Int(packet[11]) | (Int(packet[12]) << 8)

    return SportDetail(year: year, month: month, day: day, timeIndex: timeIndex, calories: calories, steps: steps, distance: distance)
}

// Heart Rate Log Parser State
class HeartRateLogParser {
    var rawHeartRates: [Int] = []
    var timestamp: Date?
    var size: Int = 0
    var index: Int = 0
    var end: Bool = false
    var range: Int = 5
    var isTodayLog: Bool = false

    init() {
        reset()
    }

    func reset() {
        rawHeartRates = []
        timestamp = nil
        size = 0
        index = 0
        end = false
        range = 5
        isTodayLog = false
    }

    func parse(packet: Data) -> HeartRateLog? {
        guard packet.count == 16, packet[0] == 21 else { // CMD_READ_HEART_RATE = 21
            return nil
        }

        let subType = packet[1]

        if subType == 255 {
            print("Error response from heart rate log request")
            reset()
            return nil // or throw NoData()
        }

        if isTodayLog, subType == 23 {
            guard let ts = timestamp else { return nil }
            let result = HeartRateLog(heartRates: heartRates, timestamp: ts, size: size, index: index, range: range)
            reset()
            return result
        }

        if subType == 0 {
            end = false
            size = Int(packet[2]) // Number of expected packets
            range = Int(packet[3])
            rawHeartRates = Array(repeating: -1, count: size * 13) // Pre-allocate array size, assuming max packets
            return nil
        } else if subType == 1 {
            // Next 4 bytes are a timestamp
            let timestampValue = packet.subdata(in: 2 ..< 6).withUnsafeBytes { $0.load(as: Int32.self) }
            timestamp = Date(timeIntervalSince1970: TimeInterval(timestampValue))

            // Remaining 9 bytes are heart rates
            let rates = packet.subdata(in: 6 ..< 15).map { Int($0) }
            rawHeartRates.replaceSubrange(0 ..< 9, with: rates)
            index += 9
            return nil
        } else {
            let rates = packet.subdata(in: 2 ..< 15).map { Int($0) }
            rawHeartRates.replaceSubrange(index ..< (index + 13), with: rates)
            index += 13

            if subType == size - 1 { // Check if this is the last packet
                guard let ts = timestamp else { return nil }
                let result = HeartRateLog(heartRates: heartRates, timestamp: ts, size: size, index: index, range: range)
                reset()
                return result
            } else {
                return nil
            }
        }
    }

    var heartRates: [Int] {
        var hr = rawHeartRates
        if rawHeartRates.count > 288 {
            hr = Array(rawHeartRates[0 ..< 288])
        } else if rawHeartRates.count < 288 {
            hr.append(contentsOf: Array(repeating: 0, count: 288 - rawHeartRates.count))
        }

        // Python code has is_today() check which might not be needed in Swift, adjust if needed.
        // if isTodayLog { ... }

        return hr
    }
}

// Sport Detail Parser State
class SportDetailParser {
    var newCalorieProtocol = false
    var index = 0
    var details: [SportDetail] = []

    init() {
        reset()
    }

    func reset() {
        newCalorieProtocol = false
        index = 0
        details = []
    }

    func parse(packet: Data) -> [SportDetail]? {
        guard packet.count == 16, packet[0] == 67 else { // CMD_GET_STEP_SOMEDAY = 67
            return nil
        }

        if index == 0, packet[1] == 255 {
            reset()
            return nil // NoData()
        }

        if index == 0, packet[1] == 240 {
            if packet[3] == 1 {
                newCalorieProtocol = true
            }
            index += 1
            return nil
        }

        guard let detail = parseSportDetailData(packet: packet) else { return nil }

        details.append(detail)

        if packet[5] == packet[6] - 1 {
            let result = details
            reset()
            return result
        } else {
            index += 1
            return nil
        }
    }
}

// MARK: - Utility Functions (Based on date_utils.py, set_time.py, steps.py)

func byteToBCD(_ byte: Int) -> UInt8 {
    assert(byte < 100 && byte >= 0)
    let tens = byte / 10
    let ones = byte % 10
    return UInt8((tens << 4) | ones)
}

func bcdToDecimal(_ bcd: UInt8) -> Int {
    (((Int(bcd) >> 4) & 15) * 10) + (Int(bcd) & 15)
}

func now() -> Date {
    Date() // Swift Date is already timezone-agnostic in many contexts, adjust if needed for UTC specifically
}

func datesBetween(start: Date, end: Date) -> [Date] {
    var dates: [Date] = []
    var currentDate = start
    let calendar = Calendar.current

    while currentDate <= end {
        dates.append(currentDate)
        currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
    }
    return dates
}

func setTimePacket(target: Date) -> Data {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")! // Ensure UTC timezone
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: target)

    var data = Data(count: 7)
    data[0] = byteToBCD(components.year! % 2000)
    data[1] = byteToBCD(components.month!)
    data[2] = byteToBCD(components.day!)
    data[3] = byteToBCD(components.hour!)
    data[4] = byteToBCD(components.minute!)
    data[5] = byteToBCD(components.second!)
    data[6] = 1 // Set language to English, 0 is Chinese

    return makePacket(command: 0x01, subData: [UInt8](data)) // CMD_SET_TIME = 1
}

func readHeartRatePacket(target: Date) -> Data {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let startOfDay = calendar.startOfDay(for: target)
    let timestamp = startOfDay.timeIntervalSince1970
    var data = Data()
    var timestampValue = Int32(timestamp)
    data.append(Data(bytes: &timestampValue, count: 4))

    return makePacket(command: 0x15, subData: [UInt8](data)) // CMD_READ_HEART_RATE = 21 (0x15)
}

func readStepsPacket(dayOffset: Int = 0) -> Data {
    var subData: [UInt8] = [0x00, 0x0F, 0x00, 0x5F, 0x01]
    subData[0] = UInt8(dayOffset)
    return makePacket(command: 0x43, subData: subData) // CMD_GET_STEP_SOMEDAY = 67 (0x43)
}

func blinkTwicePacket() -> Data {
    makePacket(command: 0x10) // CMD_BLINK_TWICE = 16 (0x10)
}

func rebootPacket() -> Data {
    makePacket(command: 0x08, subData: [0x01]) // CMD_REBOOT = 8 (0x08)
}

func hrLogSettingsPacket(settings: HeartRateLogSettings) -> Data {
    assert(settings.interval > 0 && settings.interval < 256, "Interval must be between 1 and 255")
    let enabled: UInt8 = settings.enabled ? 1 : 2
    let subData: [UInt8] = [2, enabled, UInt8(settings.interval)]
    return makePacket(command: 0x16, subData: subData) // CMD_HEART_RATE_LOG_SETTINGS = 22 (0x16)
}

func readHeartRateLogSettingsPacket() -> Data {
    makePacket(command: 0x16, subData: [0x01]) // CMD_HEART_RATE_LOG_SETTINGS = 22 (0x16)
}

func getStartPacket(readingType: RealTimeReading) -> Data {
    makePacket(command: 105, subData: [readingType.rawValue, Action.start.rawValue]) // CMD_START_REAL_TIME = 105
}

func getStopPacket(readingType: RealTimeReading) -> Data {
    makePacket(command: 106, subData: [readingType.rawValue, 0, 0]) // CMD_STOP_REAL_TIME = 106
}

func addTimes(heartRates: [Int], ts: Date) -> [(Int, Date)] {
    assert(heartRates.count == 288, "Need exactly 288 points at 5 minute intervals")
    var result: [(Int, Date)] = []
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var m = calendar.startOfDay(for: ts) // Start of the day in UTC
    let fiveMin = TimeInterval.minutes(5)

    for hr in heartRates {
        result.append((hr, m))
        m = m.addingTimeInterval(fiveMin)
    }
    return result
}

extension TimeInterval {
    static func minutes(_ value: Int) -> TimeInterval {
        TimeInterval(value * 60)
    }
}

// MARK: - ColmiR02Client Class (Based on client.py)

class ColmiR02Client: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    @Published var connectedPeripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var txCharacteristic: CBCharacteristic?

    private var responseQueue: [UInt8: [(Result<Data, Error>) -> Void]] = [:]
    private var heartRateLogParser = HeartRateLogParser()
    private var sportDetailParser = SportDetailParser()

    @Published var isScanning: Bool = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var receivedData: String = ""

    var isConnected: Bool {
        connectedPeripheral?.state == .connected
    }

    var address: String

    init(address: String) {
        self.address = address
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
        disconnect()
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth is not powered on")
            return
        }

        centralManager.scanForPeripherals(withServices: nil, options: nil)
        print("Scanning for peripherals...")
        isScanning = true
        discoveredPeripherals.removeAll()
    }

    func connect(peripheral: CBPeripheral) {
        if centralManager.isScanning {
            centralManager.stopScan()
            isScanning = false
        }
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            print("Disconnected from peripheral")
        }
        // connectedPeripheral will be set to nil in didDisconnectPeripheral delegate method
        rxCharacteristic = nil
        txCharacteristic = nil
    }

    func sendPacket(_ packetData: Data, command: UInt8, completion: ((Result<Data, Error>) -> Void)? = nil) {
        guard let peripheral = connectedPeripheral, let rxChar = rxCharacteristic else {
            completion?(.failure(NSError(domain: "ColmiR02Client", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected or RX Characteristic not found"])))
            return
        }

        if let completion {
            if responseQueue[command] == nil {
                responseQueue[command] = []
            }
            responseQueue[command]?.append(completion)
        }

        peripheral.writeValue(packetData, for: rxChar, type: .withoutResponse)
        print("Sent packet: \(packetData.hexEncodedString())")
    }

    // MARK: - Command Functions (Based on cli.py and client.py)

    func getDeviceInfo(completion: @escaping (Result<[String: String], Error>) -> Void) {
        guard let peripheral = connectedPeripheral else {
            completion(.failure(NSError(domain: "ColmiR02Client", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])))
            return
        }

        var deviceInfo: [String: String] = [:]

        func readCharacteristic(serviceUUID: CBUUID, characteristicUUID: CBUUID, key: String, nextStep: @escaping () -> Void) {
            guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID })
            else {
                completion(.failure(NSError(domain: "ColmiR02Client", code: 2, userInfo: [NSLocalizedDescriptionKey: "Service or Characteristic not found"])))
                return
            }

            peripheral.readValue(for: characteristic)
            responseQueue[0xFF] = [{ result in // Using a dummy command code for device info read
                switch result {
                case let .success(data):
                    deviceInfo[key] = String(data: data, encoding: .utf8) ?? "Unknown"
                case let .failure(error):
                    completion(.failure(error))
                    return
                }
                nextStep()
            }]
        }

        readCharacteristic(serviceUUID: DEVICE_INFO_SERVICE_UUID, characteristicUUID: DEVICE_HW_VERSION_CHAR_UUID, key: "hw_version", nextStep: {
            readCharacteristic(serviceUUID: DEVICE_INFO_SERVICE_UUID, characteristicUUID: DEVICE_FW_VERSION_CHAR_UUID, key: "fw_version", nextStep: {
                completion(.success(deviceInfo))
            })
        })
    }

    func getBattery(completion: @escaping (Result<BatteryInfo, Error>) -> Void) {
        let packet = makePacket(command: 0x03) // CMD_BATTERY = 3
        sendPacket(packet, command: 0x03) { result in
            switch result {
            case let .success(data):
                if let batteryInfo = parseBatteryData(packet: data) {
                    completion(.success(batteryInfo))
                } else {
                    completion(.failure(NSError(domain: "ColmiR02Client", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse battery data"])))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func setTime(target: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        let packet = setTimePacket(target: target)
        sendPacket(packet, command: 0x01) { result in // CMD_SET_TIME = 1
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func getHeartRateLog(targetDate: Date, completion: @escaping (Result<HeartRateLog, Error>) -> Void) {
        let packet = readHeartRatePacket(target: targetDate)
        heartRateLogParser.reset() // Reset parser before starting a new log request
        heartRateLogParser.isTodayLog = Calendar.current.isDateInToday(targetDate)

        sendPacket(packet, command: 0x15) { result in // CMD_READ_HEART_RATE = 21
            switch result {
            case let .success(data):
                if let log = self.heartRateLogParser.parse(packet: data) {
                    completion(.success(log))
                } else {
                    // Handle multi-packet scenario or parsing error. For now, fail if not immediately parsed
                    completion(.failure(NSError(domain: "ColmiR02Client", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse heart rate log data or incomplete log"])))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func getHeartRateLogSettings(completion: @escaping (Result<HeartRateLogSettings, Error>) -> Void) {
        let packet = readHeartRateLogSettingsPacket()
        sendPacket(packet, command: 0x16) { result in // CMD_HEART_RATE_LOG_SETTINGS = 22
            switch result {
            case let .success(data):
                if let settings = parseHeartRateLogSettingsData(packet: data) {
                    completion(.success(settings))
                } else {
                    completion(.failure(NSError(domain: "ColmiR02Client", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse heart rate log settings"])))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func setHeartRateLogSettings(settings: HeartRateLogSettings, completion: @escaping (Result<HeartRateLogSettings, Error>) -> Void) {
        let packet = hrLogSettingsPacket(settings: settings)
        sendPacket(packet, command: 0x16) { result in // CMD_HEART_RATE_LOG_SETTINGS = 22
            switch result {
            case let .success(data):
                // Response to set command might be different or empty. For now, return original settings if successful send.
                completion(.success(settings)) // Or parse response if device sends back confirmation
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func getRealtimeReading(readingType: RealTimeReading, completion: @escaping (Result<Reading, Error>) -> Void) {
        let startPacketData = getStartPacket(readingType: readingType)
        let stopPacketData = getStopPacket(readingType: readingType)

        sendPacket(startPacketData, command: 105) { startResult in // CMD_START_REAL_TIME = 105
            switch startResult {
            case .success:
                // Expecting data to be received in peripheral(_:didUpdateValueFor:)
                // This part is simplified, in a real app, you would likely use a timeout and handle multiple readings.
                self.responseQueue[105] = [{ dataResult in
                    switch dataResult {
                    case let .success(data):
                        if let reading = parseRealTimeReadingData(packet: data) {
                            self.sendPacket(stopPacketData, command: 106) { _ in } // Stop reading after getting one value // CMD_STOP_REAL_TIME = 106
                            completion(.success(reading))
                        } else {
                            completion(.failure(NSError(domain: "ColmiR02Client", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to parse real-time reading data"])))
                        }
                    case let .failure(error):
                        completion(.failure(error))
                        self.sendPacket(stopPacketData, command: 106) { _ in } // Ensure stop even on error
                    }
                }]

            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func getSteps(targetDate _: Date, completion: @escaping (Result<[SportDetail], Error>) -> Void) {
        let packet = readStepsPacket(dayOffset: 0) // Assuming day offset 0 for now, adjust based on targetDate if needed.
        sportDetailParser.reset() // Reset parser for new steps request

        sendPacket(packet, command: 0x43) { result in // CMD_GET_STEP_SOMEDAY = 67
            switch result {
            case let .success(data):
                if let details = self.sportDetailParser.parse(packet: data) {
                    completion(.success(details))
                } else {
                    completion(.failure(NSError(domain: "ColmiR02Client", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to parse step data or incomplete data"])))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func reboot(completion: @escaping (Result<Void, Error>) -> Void) {
        let packet = rebootPacket()
        sendPacket(packet, command: 0x08) { result in // CMD_REBOOT = 8
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func blinkTwice(completion: @escaping (Result<Void, Error>) -> Void) {
        let packet = blinkTwicePacket()
        sendPacket(packet, command: 0x10) { result in // CMD_BLINK_TWICE = 16
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    func rawCommand(commandCode: UInt8, subData: [UInt8]?, completion: @escaping (Result<Data, Error>) -> Void) {
        let packet = makePacket(command: commandCode, subData: subData)
        sendPacket(packet, command: commandCode, completion: completion)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth powered on")
        } else {
            print("Bluetooth not powered on")
            // Handle Bluetooth being off or unauthorized
        }
    }

    func centralManager(_: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData _: [String: Any], rssi _: NSNumber) {
        // Add to discovered peripherals list if not already present
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            print("Discovered peripheral: \(peripheral.name ?? "N/A") \(peripheral.identifier.uuidString)")
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "N/A")")
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self // Ensure delegate is set after connection
        isScanning = false // Stop scanning indication
        // Store the connected peripheral's information
        UserDefaults.standard.set(peripheral.name, forKey: lastConnectedPeripheralNameKey)
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastConnectedPeripheralIdentifierKey)
        address = peripheral.identifier.uuidString // Update client's address
        peripheral.discoverServices([UART_SERVICE_UUID, DEVICE_INFO_SERVICE_UUID])
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(peripheral.name ?? "N/A"), error: \(error?.localizedDescription ?? "N/A")")
        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
        }
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let peripheralName = peripheral.name ?? "Unknown Device"
        let peripheralID = peripheral.identifier.uuidString
        print("Disconnected from peripheral: \(peripheralName) (\(peripheralID)), error: \(error?.localizedDescription ?? "N/A")")

        if connectedPeripheral?.identifier == peripheral.identifier {
            connectedPeripheral = nil
        }
        rxCharacteristic = nil
        txCharacteristic = nil

        // Attempt to reconnect if it was an unexpected disconnection from the target peripheral
        if error != nil, peripheral.identifier.uuidString == address {
            print("Unexpected disconnection from \(peripheralName). Attempting to reconnect...")
            centralManager.connect(peripheral, options: nil)
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == UART_SERVICE_UUID {
                peripheral.discoverCharacteristics([UART_RX_CHAR_UUID, UART_TX_CHAR_UUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == UART_RX_CHAR_UUID {
                rxCharacteristic = characteristic
                print("RX Characteristic found")
            } else if characteristic.uuid == UART_TX_CHAR_UUID {
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("TX Characteristic found and set to notify")
            }
        }
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("Error updating value for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else {
            print("Characteristic \(characteristic.uuid) value is nil")
            return
        }

        print("Received data from TX characteristic: \(value.hexEncodedString())")
        receivedData = value.hexEncodedString() // Update published property

        let packetType = value[0]
        if let completion = responseQueue[packetType]?.removeFirst() {
            completion(.success(value))
            if responseQueue[packetType]?.isEmpty ?? false {
                responseQueue.removeValue(forKey: packetType)
            }
        } else if let completion = responseQueue[0xFF]?.removeFirst() { // Handling device info responses
            completion(.success(value))
            if responseQueue[0xFF]?.isEmpty ?? false {
                responseQueue.removeValue(forKey: 0xFF)
            }
        } else {
            print("No completion handler found for packet type \(packetType)")
        }
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            print("Error updating notification state for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }

        if characteristic.isNotifying {
            print("Started notification for characteristic \(characteristic.uuid)")
        } else {
            print("Stopped notification for characteristic \(characteristic.uuid)")
            // Optionally handle notification stopping
        }
    }
}

// MARK: - Extensions and Helper functions

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02X" : "%02x"
        return map { String(format: format, $0) }.joined()
    }
}
