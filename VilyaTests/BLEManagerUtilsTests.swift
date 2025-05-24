//
//  BLEManagerUtilsTests.swift
//  VilyaTests
//
//  Created by Jonathan Milligan on 5/24/25.
//

import Foundation
import Testing

@testable import Vilya // To access makePacket, checksum, etc.

struct BLEManagerUtilsTests {
    @Test func testMakePacket() throws {
        let command: UInt8 = 0x01
        let subData: [UInt8] = [0x02, 0x03, 0x04]
        let packet = makePacket(command: command, subData: subData)

        #expect(packet.count == 16)
        #expect(packet[0] == command)
        #expect(packet[1] == subData[0])
        #expect(packet[2] == subData[1])
        #expect(packet[3] == subData[2])

        var expectedChecksum =
            UInt32(command) + UInt32(subData[0]) + UInt32(subData[1]) + UInt32(subData[2])
        // Add other bytes (0) up to index 14
        for i in 4 ..< 15 {
            expectedChecksum += UInt32(packet[i])
        }
        #expect(packet[15] == UInt8(expectedChecksum & 0xFF))

        let packetNoSubData = makePacket(command: 0xAA)
        #expect(packetNoSubData.count == 16)
        #expect(packetNoSubData[0] == 0xAA)
        var expectedChecksumNoSubData: UInt32 = 0xAA
        for i in 1 ..< 15 {
            expectedChecksumNoSubData += UInt32(packetNoSubData[i])
        }
        #expect(packetNoSubData[15] == UInt8(expectedChecksumNoSubData & 0xFF))
    }

    @Test func testChecksum() throws {
        var packet = Data(repeating: 0, count: 16)
        packet[0] = 0x01
        packet[1] = 0x02
        // checksum should be 0x01 + 0x02 = 0x03
        #expect(checksum(packet: packet) == 0x03)

        packet[0] = 0xFF
        packet[1] = 0x01
        // checksum should be 0xFF + 0x01 = 0x100 -> 0x00
        #expect(checksum(packet: packet) == 0x00)
    }

    @Test func testByteToBCD() throws {
        #expect(byteToBCD(0) == 0x00)
        #expect(byteToBCD(5) == 0x05)
        #expect(byteToBCD(10) == 0x10)
        #expect(byteToBCD(23) == 0x23)
        #expect(byteToBCD(99) == 0x99)
    }

    @Test func testBcdToDecimal() throws {
        #expect(bcdToDecimal(0x00) == 0)
        #expect(bcdToDecimal(0x05) == 5)
        #expect(bcdToDecimal(0x10) == 10)
        #expect(bcdToDecimal(0x23) == 23)
        #expect(bcdToDecimal(0x99) == 99)
    }

    @Test func testSetTimePacket() throws {
        // Example Date: 2024-07-15 10:30:45 UTC
        var components = DateComponents()
        components.year = 2024
        components.month = 7
        components.day = 15
        components.hour = 10
        components.minute = 30
        components.second = 45
        components.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar.current.date(from: components)!

        let packet = setTimePacket(target: date)
        #expect(packet[0] == 0x01) // CMD_SET_TIME
        #expect(packet[1] == byteToBCD(24)) // Year
        #expect(packet[2] == byteToBCD(07)) // Month
        #expect(packet[3] == byteToBCD(15)) // Day
        #expect(packet[4] == byteToBCD(10)) // Hour
        #expect(packet[5] == byteToBCD(30)) // Minute
        #expect(packet[6] == byteToBCD(45)) // Second
        #expect(packet[7] == 1) // Language English
    }

    @Test func testReadHeartRatePacket() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let startOfDay = calendar.startOfDay(for: date)
        let timestamp = Int32(startOfDay.timeIntervalSince1970)

        let packet = readHeartRatePacket(target: date)
        #expect(packet[0] == 0x15) // CMD_READ_HEART_RATE

        let subData = packet.subdata(in: 1 ..< 5)
        let packetTimestamp = subData.withUnsafeBytes { $0.load(as: Int32.self) }
        #expect(packetTimestamp == timestamp)
    }

    @Test func testReadStepsPacket() throws {
        let packetDefault = readStepsPacket() // dayOffset = 0
        #expect(packetDefault[0] == 0x43) // CMD_GET_STEP_SOMEDAY
        #expect(packetDefault[1] == 0x00) // dayOffset

        let packetOffset = readStepsPacket(dayOffset: 3)
        #expect(packetOffset[0] == 0x43)
        #expect(packetOffset[1] == 0x03) // dayOffset
    }

    @Test func testBlinkTwicePacket() throws {
        let packet = blinkTwicePacket()
        #expect(packet[0] == 0x10) // CMD_BLINK_TWICE
    }

    @Test func testRebootPacket() throws {
        let packet = rebootPacket()
        #expect(packet[0] == 0x08) // CMD_REBOOT
        #expect(packet[1] == 0x01)
    }

    @Test func testHrLogSettingsPacket() throws {
        let settingsEnabled = HeartRateLogSettings(enabled: true, interval: 15)
        let packetEnabled = hrLogSettingsPacket(settings: settingsEnabled)
        #expect(packetEnabled[0] == 0x16) // CMD_HEART_RATE_LOG_SETTINGS
        #expect(packetEnabled[1] == 0x02) // Sub-command for write
        #expect(packetEnabled[2] == 0x01) // Enabled
        #expect(packetEnabled[3] == 15) // Interval

        let settingsDisabled = HeartRateLogSettings(enabled: false, interval: 30)
        let packetDisabled = hrLogSettingsPacket(settings: settingsDisabled)
        #expect(packetDisabled[0] == 0x16)
        #expect(packetDisabled[1] == 0x02)
        #expect(packetDisabled[2] == 0x02) // Disabled
        #expect(packetDisabled[3] == 30) // Interval
    }

    @Test func testReadHeartRateLogSettingsPacket() throws {
        let packet = readHeartRateLogSettingsPacket()
        #expect(packet[0] == 0x16) // CMD_HEART_RATE_LOG_SETTINGS
        #expect(packet[1] == 0x01) // Sub-command for read
    }

    @Test func testGetStartPacket() throws {
        let packet = getStartPacket(readingType: .heartRate)
        #expect(packet[0] == 105) // CMD_START_REAL_TIME
        #expect(packet[1] == RealTimeReading.heartRate.rawValue)
        #expect(packet[2] == Action.start.rawValue)
    }

    @Test func testGetStopPacket() throws {
        let packet = getStopPacket(readingType: .spo2)
        #expect(packet[0] == 106) // CMD_STOP_REAL_TIME
        #expect(packet[1] == RealTimeReading.spo2.rawValue)
        #expect(packet[2] == Action.stop.rawValue)
        #expect(packet[3] == 0)
    }

    @Test func testAddTimes() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")!
        let startDate = calendar.date(from: components)!

        let emptyRates: [Int] = []
        let emptyResult = addTimes(heartRates: emptyRates, ts: startDate)
        #expect(emptyResult.isEmpty)

        let rates = [60, 62, 65]
        let result = addTimes(heartRates: rates, ts: startDate)
        #expect(result.count == 3)

        #expect(result[0].0 == 60)
        #expect(result[0].1 == startDate)

        #expect(result[1].0 == 62)
        #expect(result[1].1 == startDate.addingTimeInterval(5 * 60))

        #expect(result[2].0 == 65)
        #expect(result[2].1 == startDate.addingTimeInterval(10 * 60))
    }
}
