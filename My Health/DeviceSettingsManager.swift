//
//  DeviceSettingsManager.swift
//  My Health
//
//  Created by Jonathan Milligan on 05/12/2025.
//

import Foundation

struct DeviceSettingsManager {
    static let shared = DeviceSettingsManager()

    private let defaultDeviceAddress = "D890C620-D962-42FA-A099-81A4F7605434"

    private init() {}

    func getTargetDeviceAddress() -> String {
        UserDefaults.standard.string(forKey: lastConnectedPeripheralIdentifierKey)
            ?? defaultDeviceAddress
    }
}
