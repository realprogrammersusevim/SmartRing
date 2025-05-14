//
//  DataModel.swift
//  Vilya
//
//  Created by Jonathan Milligan on 1/29/25.
//

import Foundation
import SwiftData

@Model
final class HeartRateData {
    @Attribute(.unique) var timestamp: Date
    var heartRate: Int

    init(timestamp: Date, heartRate: Int) {
        self.timestamp = timestamp
        self.heartRate = heartRate
    }
}

@Model
final class BloodOxygenData {
    @Attribute(.unique) var timestamp: Date
    var bloodOxygen: Int

    init(timestamp: Date, bloodOxygen: Int) {
        self.timestamp = timestamp
        self.bloodOxygen = bloodOxygen
    }
}
