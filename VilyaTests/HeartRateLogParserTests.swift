//
//  HeartRateLogParserTests.swift
//  VilyaTests
//
//  Created by Jonathan Milligan on 5/24/25.
//

@testable import Vilya
import XCTest

final class HeartRateLogParserTests: XCTestCase {
    var parser: HeartRateLogParser!

    override func setUp() {
        super.setUp()
        parser = HeartRateLogParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    func testReset() {
        // Given: Parser with some state
        parser.rawHeartRates = [70, 75]
        parser.timestamp = Date()
        parser.size = 2
        parser.index = 10
        parser.end = true
        parser.range = 10
        parser.isTodayLog = true
        parser.setTargetDateForCurrentLog(Date())

        // When: Reset is called
        parser.reset()

        // Then: All properties are reset to default values
        XCTAssertTrue(parser.rawHeartRates.isEmpty)
        XCTAssertNil(parser.timestamp)
        XCTAssertEqual(parser.size, 0)
        XCTAssertEqual(parser.index, 0)
        XCTAssertFalse(parser.end)
        XCTAssertEqual(parser.range, 5) // Default range
        XCTAssertFalse(parser.isTodayLog)
        // Accessing private `requestedDateForLog` for verification is tricky without modifying the class.
        // We can infer its reset if other dependent logic behaves as expected.
    }

    func testSetTargetDateForCurrentLog() {
        let testDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        parser.setTargetDateForCurrentLog(testDate)

        // Test by attempting to parse an empty log (0xFF), which relies on requestedDateForLog
        let emptyLogPacket = Data([21, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // Checksum will be off, but parser checks cmd and subtype first
        let log = parser.parse(packet: emptyLogPacket)

        XCTAssertNotNil(log, "Log should not be nil for an empty packet if target date is set.")
        XCTAssertEqual(log?.size, 0)
        XCTAssertTrue(log?.heartRates.isEmpty ?? false)
        XCTAssertNotNil(log?.timestamp)
        if let logTimestamp = log?.timestamp {
            XCTAssertTrue(Calendar.current.isDate(logTimestamp, inSameDayAs: Calendar.current.startOfDay(for: testDate)), "Log timestamp should be the start of the target date.")
        }
    }

    func testParse_InvalidPacket_WrongCommand() {
        let packet = Data([0xAA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA])
        XCTAssertNil(parser.parse(packet: packet))
    }

    func testParse_EmptyLogPacket_0xFF() {
        let targetDate = Date()
        parser.setTargetDateForCurrentLog(targetDate)
        // CMD_READ_HEART_RATE = 21, SubType = 255
        let packet = Data([0x15, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x14])
        let log = parser.parse(packet: packet)

        XCTAssertNotNil(log)
        XCTAssertEqual(log?.size, 0)
        XCTAssertTrue(log?.heartRates.isEmpty ?? false)
        XCTAssertEqual(log?.index, 0) // As per current implementation for 0xFF
        XCTAssertEqual(log?.range, 5) // Default range
        XCTAssertTrue(Calendar.current.isDate(log!.timestamp, inSameDayAs: Calendar.current.startOfDay(for: targetDate)))

        // Verify parser resets after completing a log
        XCTAssertTrue(parser.rawHeartRates.isEmpty)
    }

    func testParse_HeaderPacket_SubType0() {
        // CMD_READ_HEART_RATE = 21, SubType = 0, Size = 2, Range = 10
        let packet = Data([0x15, 0x00, 0x02, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21])
        let log = parser.parse(packet: packet)

        XCTAssertNil(log) // Header packet doesn't complete the log
        XCTAssertFalse(parser.end)
        XCTAssertEqual(parser.size, 2)
        XCTAssertEqual(parser.range, 10)
        XCTAssertEqual(parser.rawHeartRates.count, 2 * 13) // size * 13
        XCTAssertTrue(parser.rawHeartRates.allSatisfy { $0 == -1 }) // Pre-allocated with -1
    }

    func testParse_FirstDataPacket_SubType1() {
        // Setup with header first
        let headerPacket = Data([0x15, 0x00, 0x02, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1C]) // Size = 2, Checksum adjusted
        _ = parser.parse(packet: headerPacket)

        // CMD_READ_HEART_RATE = 21, SubType = 1
        // Timestamp (e.g., 1678886400 -> 00 00 10 64 at 2..<6)
        // Rates: 70, 71, 72, 73, 74, 75, 76, 77, 78 (at 6..<15)
        let tsValue: Int32 = 1_678_886_400 // Example timestamp
        var littleEndianTsValue = tsValue.littleEndian // Store in a mutable variable
        let tsData = Data(bytes: &littleEndianTsValue, count: MemoryLayout<Int32>.size)

        var dataBytes: [UInt8] = [0x15, 0x01]
        dataBytes.append(contentsOf: tsData)
        let ratesPayload: [UInt8] = [70, 71, 72, 73, 74, 75, 76, 77, 78] // 9 heart rates
        dataBytes.append(contentsOf: ratesPayload)
        // dataBytes is now 15 bytes long (2 cmd/sub + 4 ts + 9 rates)

        var packetData = Data(dataBytes) // packetData is 15 bytes
        var sum: UInt32 = 0
        for byte_val in packetData { // Sum over the 15 bytes of data
            sum += UInt32(byte_val)
        }
        packetData.append(UInt8(sum & 0xFF)) // Append checksum, packetData is now 16 bytes
        let packet = packetData

        let log = parser.parse(packet: packet)

        XCTAssertNil(log) // First data packet doesn't complete the log if size > 1
        XCTAssertNotNil(parser.timestamp)
        XCTAssertEqual(parser.timestamp?.timeIntervalSince1970, TimeInterval(tsValue))
        XCTAssertEqual(parser.index, 9)
        XCTAssertEqual(Array(parser.rawHeartRates.prefix(9)), [70, 71, 72, 73, 74, 75, 76, 77, 78])
    }

    func testParse_FullLogSequence() {
        let targetDate = Date()
        parser.setTargetDateForCurrentLog(targetDate)

        // 1. Header Packet (size = 1, meaning only one data packet of subtype 1 is expected)
        let headerPacket = Data([0x15, 0x00, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1B])
        XCTAssertNil(parser.parse(packet: headerPacket))
        XCTAssertEqual(parser.size, 1)

        // 2. Data Packet (subtype 1, which is also the last packet as size = 1)
        let tsValue: Int32 = 1_678_886_400 // Example: 2023-03-15 12:00:00 PM GMT
        var tsData = Data()
        withUnsafeBytes(of: tsValue.littleEndian) { tsData.append(contentsOf: $0) }

        var dataBytes: [UInt8] = [0x15, 0x01] // Command 21, SubType 1
        dataBytes.append(contentsOf: tsData) // Bytes 2-5: Timestamp
        let rates: [UInt8] = [60, 62, 61, 63, 60, 65, 64, 66, 67] // 9 heart rates
        dataBytes.append(contentsOf: rates) // Bytes 6-14: Heart rates
        // Pad to 15 bytes before checksum
        while dataBytes.count < 15 {
            dataBytes.append(0x00)
        }

        var packet = Data(dataBytes)
        var sum: UInt32 = 0
        for i in 0 ..< 15 {
            sum += UInt32(packet[i])
        }
        packet.append(UInt8(sum & 0xFF)) // Append checksum

        let log = parser.parse(packet: packet)

        XCTAssertNotNil(log, "Log should be complete.")
        XCTAssertEqual(log?.timestamp.timeIntervalSince1970, TimeInterval(tsValue))
        XCTAssertEqual(log?.size, 1) // From header
        XCTAssertEqual(log?.index, 9) // 9 rates read
        XCTAssertEqual(log?.range, 5) // From header
        XCTAssertEqual(log?.heartRates.count, 288) // Padded/truncated to 288
        XCTAssertEqual(Array(log!.heartRates.prefix(9)), rates.map { Int($0) })

        // Verify parser resets
        XCTAssertTrue(parser.rawHeartRates.isEmpty)
    }

    func testHeartRatesComputedProperty_Padding() {
        parser.rawHeartRates = [70, 75] // Less than 288
        let rates = parser.heartRates
        XCTAssertEqual(rates.count, 288)
        XCTAssertEqual(rates[0], 70)
        XCTAssertEqual(rates[1], 75)
        XCTAssertEqual(rates[2], 0) // Padded with 0
    }

    func testHeartRatesComputedProperty_Truncation() {
        parser.rawHeartRates = Array(repeating: 70, count: 300) // More than 288
        let rates = parser.heartRates
        XCTAssertEqual(rates.count, 288)
        XCTAssertTrue(rates.allSatisfy { $0 == 70 })
    }

    func testHeartRatesComputedProperty_ExactSize() {
        parser.rawHeartRates = Array(repeating: 65, count: 288)
        let rates = parser.heartRates
        XCTAssertEqual(rates.count, 288)
        XCTAssertTrue(rates.allSatisfy { $0 == 65 })
    }
}
