//
//  PacketParserTests.swift
//  VilyaTests
//
//  Created by Jonathan Milligan on 5/24/25.
//

import Foundation
import Testing

@testable import Vilya // To access PacketParser and its related types

struct PacketParserTests {
    // Helper to create a Data packet
    private func createPacket(command: UInt8, bytes: [UInt8]) -> Data {
        var data = Data(repeating: 0, count: 16)
        data[0] = command
        for (index, byte) in bytes.enumerated() {
            if index + 1 < 15 { // Ensure we don't write past byte 14 for subdata
                data[index + 1] = byte
            }
        }
        // The checksum is usually calculated by the makePacket function,
        // but for parser tests, we often care more about the payload.
        // If checksum matters for parsing, it should be set correctly.
        return data
    }

    @Test func testParseBatteryData() throws {
        // Valid packet: level 80, charging
        let validPacket = createPacket(
            command: 0x03, bytes: [80, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        let batteryInfo = PacketParser.parseBatteryData(packet: validPacket)
        #expect(batteryInfo != nil)
        #expect(batteryInfo?.batteryLevel == 80)
        #expect(batteryInfo?.charging == true)

        // Valid packet: level 50, not charging
        let validPacketNotCharging = createPacket(
            command: 0x03, bytes: [50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        let batteryInfoNotCharging = PacketParser.parseBatteryData(packet: validPacketNotCharging)
        #expect(batteryInfoNotCharging != nil)
        #expect(batteryInfoNotCharging?.batteryLevel == 50)
        #expect(batteryInfoNotCharging?.charging == false)

        // Invalid command
        let invalidCmdPacket = createPacket(command: 0x04, bytes: [80, 1])
        #expect(PacketParser.parseBatteryData(packet: invalidCmdPacket) == nil)

        // Invalid length
        let invalidLengthPacket = Data([0x03, 80, 1])
        #expect(PacketParser.parseBatteryData(packet: invalidLengthPacket) == nil)
    }

    @Test func testParseRealTimeReadingData() throws {
        // Valid HR: 75
        let validHrPacket = createPacket(
            command: 105, bytes: [RealTimeReading.heartRate.rawValue, 0, 75]
        )
        let hrReading = PacketParser.parseRealTimeReadingData(packet: validHrPacket)
        #expect(hrReading != nil)
        #expect(hrReading?.kind == .heartRate)
        #expect(hrReading?.value == 75)

        // Valid SpO2: 98
        let validSpo2Packet = createPacket(
            command: 105, bytes: [RealTimeReading.spo2.rawValue, 0, 98]
        )
        let spo2Reading = PacketParser.parseRealTimeReadingData(packet: validSpo2Packet)
        #expect(spo2Reading != nil)
        #expect(spo2Reading?.kind == .spo2)
        #expect(spo2Reading?.value == 98)

        // Packet with error code
        let errorPacket = createPacket(
            command: 105, bytes: [RealTimeReading.heartRate.rawValue, 1, 0]
        ) // Error code 1
        #expect(PacketParser.parseRealTimeReadingData(packet: errorPacket) == nil)

        // Invalid command
        let invalidCmdPacket = createPacket(
            command: 100, bytes: [RealTimeReading.heartRate.rawValue, 0, 75]
        )
        #expect(PacketParser.parseRealTimeReadingData(packet: invalidCmdPacket) == nil)

        // Invalid length
        let invalidLengthPacket = Data([105, 1, 0])
        #expect(PacketParser.parseRealTimeReadingData(packet: invalidLengthPacket) == nil)

        // Unknown reading kind
        let unknownKindPacket = createPacket(command: 105, bytes: [99, 0, 75]) // 99 is not a valid RealTimeReading rawValue
        #expect(PacketParser.parseRealTimeReadingData(packet: unknownKindPacket) == nil)
    }

    @Test func testParseHeartRateLogSettingsData() throws {
        // Enabled, interval 10
        let enabledPacket = createPacket(command: 22, bytes: [0, 1, 10]) // packet[1] is unused by parser
        let settingsEnabled = PacketParser.parseHeartRateLogSettingsData(packet: enabledPacket)
        #expect(settingsEnabled != nil)
        #expect(settingsEnabled?.enabled == true)
        #expect(settingsEnabled?.interval == 10)

        // Disabled, interval 30
        let disabledPacket = createPacket(command: 22, bytes: [0, 2, 30])
        let settingsDisabled = PacketParser.parseHeartRateLogSettingsData(packet: disabledPacket)
        #expect(settingsDisabled != nil)
        #expect(settingsDisabled?.enabled == false)
        #expect(settingsDisabled?.interval == 30)

        // Unexpected enabled byte (e.g., 0 or 3), defaults to false
        let unexpectedEnabledPacket = createPacket(command: 22, bytes: [0, 3, 15])
        let settingsUnexpected = PacketParser.parseHeartRateLogSettingsData(
            packet: unexpectedEnabledPacket)
        #expect(settingsUnexpected != nil)
        #expect(settingsUnexpected?.enabled == false) // Default behavior
        #expect(settingsUnexpected?.interval == 15)

        // Invalid command
        let invalidCmdPacket = createPacket(command: 23, bytes: [0, 1, 10])
        #expect(PacketParser.parseHeartRateLogSettingsData(packet: invalidCmdPacket) == nil)

        // Invalid length
        let invalidLengthPacket = Data([22, 0, 1])
        #expect(PacketParser.parseHeartRateLogSettingsData(packet: invalidLengthPacket) == nil)
    }

    @Test func testParseSportDetailData() throws {
        // year: 24 (2024), month: 7, day: 15, timeIndex: 40 (10:00), calories: 100, steps: 200, distance: 300
        // packet[1]=year, packet[2]=month, packet[3]=day, packet[4]=timeIndex
        // packet[7]=cal_low, packet[8]=cal_high
        // packet[9]=steps_low, packet[10]=steps_high
        // packet[11]=dist_low, packet[12]=dist_high
        let validPacketBytes: [UInt8] = [
            byteToBCD(24), byteToBCD(7), byteToBCD(15), 40, // year, month, day, timeIndex
            0, 0, // packet[5], packet[6] (current_packet_index, total_packets) - not directly used by this static parser
            UInt8(100 & 0xFF), UInt8((100 >> 8) & 0xFF), // calories
            UInt8(200 & 0xFF), UInt8((200 >> 8) & 0xFF), // steps
            UInt8(300 & 0xFF), UInt8((300 >> 8) & 0xFF), // distance
            0, 0, // packet[13], packet[14]
        ]
        let validPacket = createPacket(command: 67, bytes: validPacketBytes)
        let sportDetail = PacketParser.parseSportDetailData(packet: validPacket)
        #expect(sportDetail != nil)
        #expect(sportDetail?.year == 2024)
        #expect(sportDetail?.month == 7)
        #expect(sportDetail?.day == 15)
        #expect(sportDetail?.timeIndex == 40)
        #expect(sportDetail?.calories == 100)
        #expect(sportDetail?.steps == 200)
        #expect(sportDetail?.distance == 300)

        // Invalid command
        let invalidCmdPacket = createPacket(command: 68, bytes: validPacketBytes)
        #expect(PacketParser.parseSportDetailData(packet: invalidCmdPacket) == nil)

        // Invalid length
        let invalidLengthPacket = Data([67] + validPacketBytes.prefix(10))
        #expect(PacketParser.parseSportDetailData(packet: invalidLengthPacket) == nil)
    }

    // MARK: - HeartRateLogParser Tests

    @Test func heartRateLogParser_FullSequence() throws {
        let parser = HeartRateLogParser()
        let targetDate = Calendar.current.date(
            from: DateComponents(year: 2023, month: 10, day: 26))!
        parser.setTargetDateForCurrentLog(targetDate)

        // Subtype 0: Header (size 2, range 5)
        let headerPacket = createPacket(
            command: 21, bytes: [0, 2, 5] + [UInt8](repeating: 0, count: 11)
        )
        #expect(parser.parse(packet: headerPacket) == nil) // No log yet
        #expect(parser.size == 2)
        #expect(parser.range == 5)
        #expect(parser.rawHeartRates.count == 2 * 13) // size * 13

        // Subtype 1: First data packet (timestamp, 9 rates)
        let tsValue = Int32(targetDate.timeIntervalSince1970)
        var littleEndianTsValue = tsValue.littleEndian // Ensure timestamp bytes are little-endian for the packet
        let tsBytes = Data(bytes: &littleEndianTsValue, count: MemoryLayout<Int32>.size)
        let rates1: [UInt8] = [60, 61, 62, 63, 64, 65, 66, 67, 68]
        // Packet structure for subtype 1: subtype (1 byte) + timestamp (4 bytes) + rates (9 bytes) = 14 bytes
        let dataPacket1Bytes = [1] + Array(tsBytes) + rates1 // Total 14 bytes
        let dataPacket1 = createPacket(command: 21, bytes: dataPacket1Bytes)
        #expect(parser.parse(packet: dataPacket1) == nil) // No log yet
        #expect(parser.timestamp != nil)
        // The timestamp from the packet is based on targetDate's start of day, so compare against that.
        #expect(
            Calendar.current.isDate(
                parser.timestamp!, inSameDayAs: Calendar.current.startOfDay(for: targetDate)
            ))
        #expect(Array(parser.rawHeartRates.prefix(9)) == rates1.map { Int($0) })
        #expect(parser.index == 9)

        // Subtype 2 (size-1): Last data packet (13 rates)
        let rates2: [UInt8] = [70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82]
        // Packet structure for subsequent data: subtype (1 byte) + rates (13 bytes) = 14 bytes
        let dataPacket2Bytes = [UInt8(parser.size)] + rates2 // SubType should be 2 (equal to parser.size)
        let dataPacket2 = createPacket(command: 21, bytes: dataPacket2Bytes)
        let log = parser.parse(packet: dataPacket2)

        #expect(log != nil)
        #expect(log?.size == 2)
        #expect(log?.range == 5)
        #expect(log?.heartRates.count == 288) // Padded/truncated
        let expectedRates = (rates1 + rates2).map { Int($0) }
        for i in 0 ..< expectedRates.count {
            #expect(log?.heartRates[i] == expectedRates[i])
        }
        // Check if parser reset
        #expect(parser.size == 0)
    }

    @Test func heartRateLogParser_EmptyLog() throws {
        let parser = HeartRateLogParser()
        let targetDate = Date()
        parser.setTargetDateForCurrentLog(targetDate)

        let emptyLogPacket = createPacket(
            command: 21, bytes: [255] + [UInt8](repeating: 0, count: 14)
        )
        let log = parser.parse(packet: emptyLogPacket)

        #expect(log != nil)
        #expect(log?.heartRates.isEmpty == true) // The heartRates computed property will pad it to 288 with 0s.
        // The rawHeartRates from parser would be empty.
        // The log object itself should reflect it was an empty log.
        #expect(log?.size == 0) // Size 0 indicates empty log from device
        #expect(log?.index == 0) // Index 0 for the 0xFF packet
        #expect(
            Calendar.current.isDate(
                log!.timestamp, inSameDayAs: Calendar.current.startOfDay(for: targetDate)
            ))
        // Check if parser reset
        #expect(parser.size == 0)
    }

    @Test func heartRateLogParser_heartRatesComputedProperty() throws {
        let parser = HeartRateLogParser()
        parser.rawHeartRates = [60, 65, 70] // Less than 288
        var paddedRates = parser.heartRates
        #expect(paddedRates.count == 288)
        #expect(paddedRates[0] == 60)
        #expect(paddedRates[1] == 65)
        #expect(paddedRates[2] == 70)
        #expect(paddedRates[3] == 0) // Padded with 0

        parser.rawHeartRates = Array(0 ..< 300) // More than 288
        var truncatedRates = parser.heartRates
        #expect(truncatedRates.count == 288)
        #expect(truncatedRates[287] == 287)

        parser.rawHeartRates = Array(0 ..< 288) // Exactly 288
        var exactRates = parser.heartRates
        #expect(exactRates.count == 288)
        #expect(exactRates[287] == 287)
    }

    // MARK: - SportDetailParser Tests

    @Test func sportDetailParser_FullSequence() throws {
        let parser = SportDetailParser()

        // Packet 1 (index 0 of 2)
        let detail1Bytes: [UInt8] = [
            byteToBCD(24), byteToBCD(7), byteToBCD(15), 40, 0, 2, 100, 0, 200, 0, 150, 0, 0, 0,
        ]
        let packet1 = createPacket(command: 67, bytes: detail1Bytes)
        #expect(parser.parse(packet: packet1) == nil) // Not complete yet
        #expect(parser.details.count == 1)
        #expect(parser.index == 1) // Incremented from 0

        // Packet 2 (index 1 of 2 - last packet)
        let detail2Bytes: [UInt8] = [
            byteToBCD(24), byteToBCD(7), byteToBCD(15), 41, 1, 2, 50, 0, 100, 0, 75, 0, 0, 0,
        ]
        let packet2 = createPacket(command: 67, bytes: detail2Bytes)
        let sportDetails = parser.parse(packet: packet2)

        #expect(sportDetails != nil)
        #expect(sportDetails?.count == 2)
        #expect(sportDetails?[0].timeIndex == 40)
        #expect(sportDetails?[0].calories == 100)
        #expect(sportDetails?[1].timeIndex == 41)
        #expect(sportDetails?[1].calories == 50)

        // Check if parser reset
        #expect(parser.index == 0)
        #expect(parser.details.isEmpty)
    }

    @Test func sportDetailParser_NoData() throws {
        let parser = SportDetailParser()
        // NoData packet: index 0, packet[1] == 255
        let noDataPacket = createPacket(
            command: 67, bytes: [255] + [UInt8](repeating: 0, count: 14)
        )
        let sportDetails = parser.parse(packet: noDataPacket)
        #expect(sportDetails == nil) // As per current implementation, returns nil for NoData
        // Check if parser reset
        #expect(parser.index == 0)
    }

    @Test func sportDetailParser_NewCalorieProtocol() throws {
        let parser = SportDetailParser()
        // New calorie protocol packet: index 0, packet[1] == 240, packet[3] == 1
        let newCaloriePacket = createPacket(
            command: 67, bytes: [240, 0, 1] + [UInt8](repeating: 0, count: 12)
        )
        #expect(parser.parse(packet: newCaloriePacket) == nil) // Not complete yet
        #expect(parser.newCalorieProtocol == true)
        #expect(parser.index == 1)
    }
}

// Helper for BCD, already in BLEManager.swift but useful here for creating test packets
private func byteToBCD(_ byte: Int) -> UInt8 {
    assert(byte < 100 && byte >= 0)
    let tens = byte / 10
    let ones = byte % 10
    return UInt8((tens << 4) | ones)
}
