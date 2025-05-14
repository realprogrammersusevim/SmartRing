//
//  PacketParser.swift
//  Vilya
//
//  Created by Jonathan Milligan on 05/12/2025.
//

import Foundation

// MARK: - Parsing Functions (Based on Python parsing functions)

enum PacketParser {
    static func parseBatteryData(packet: Data) -> BatteryInfo? {
        guard packet.count == 16, packet[0] == 0x03 else { // CMD_BATTERY = 3
            return nil
        }
        return BatteryInfo(batteryLevel: Int(packet[1]), charging: packet[2] != 0)
    }

    static func parseRealTimeReadingData(packet: Data) -> Reading? {
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

    static func parseHeartRateLogSettingsData(packet: Data) -> HeartRateLogSettings? {
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

    static func parseSportDetailData(packet: Data) -> SportDetail? {
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

        return SportDetail(
            year: year, month: month, day: day, timeIndex: timeIndex, calories: calories,
            steps: steps, distance: distance
        )
    }
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
    private var requestedDateForLog: Date?

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
        requestedDateForLog = nil
    }

    func setTargetDateForCurrentLog(_ date: Date) {
        // Store the start of the day for the requested log
        requestedDateForLog = Calendar.current.startOfDay(for: date)
    }

    func parse(packet: Data) -> HeartRateLog? {
        guard packet.count == 16, packet[0] == 21 else { // CMD_READ_HEART_RATE = 21
            return nil
        }

        let subType = packet[1]

        if subType == 255 {
            print("HeartRateLogParser: Received 0xFF, interpreting as empty data for the day \(requestedDateForLog?.formatted(date: .long, time: .omitted) ?? "Unknown Date").")
            guard let dateForLog = requestedDateForLog else {
                print("HeartRateLogParser: Critical error - 0xFF received but no targetDateForLog set. Cannot create empty log.")
                reset() // Reset internal state
                return nil // This will likely lead to a parsing error or timeout in the calling function
            }
            let emptyLog = HeartRateLog(
                heartRates: [],
                timestamp: dateForLog, // Use the date of the original request
                size: 0, // No actual data packets
                index: 0, // Signifies this 0xFF packet itself
                range: range // Use default or last known range
            )
            reset()
            return emptyLog
        }

        if isTodayLog, subType == 23 {
            guard let ts = timestamp else { return nil }
            let result = HeartRateLog(
                heartRates: heartRates, timestamp: ts, size: size, index: index, range: range
            )
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
            let timestampValue = packet.subdata(in: 2 ..< 6).withUnsafeBytes {
                $0.load(as: Int32.self)
            }
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
                guard let ts = timestamp else {
                    print("HeartRateLogParser: Log ended (all packets received) but no base timestamp from device. This is unexpected.")
                    reset()
                    return nil
                }
                let result = HeartRateLog(
                    heartRates: heartRates, timestamp: ts, size: size, index: index, range: range
                )
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

        guard let detail = PacketParser.parseSportDetailData(packet: packet) else { return nil }

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
