//
//  BLEManager.swift
//  My Health
//
//  Created by Jonathan Milligan on 1/29/25.
//

import CoreBluetooth
import SwiftUI

class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var isScanning = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var receivedData: String = "" // For debugging/raw data
    
    private var centralManager: CBCentralManager!
    private var smartRingServiceUUID: CBUUID!
    private var dataCharacteristicUUID: CBUUID!
    
    init(serviceUUID: String, dataCharacteristicUUID: String) {
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        self.smartRingServiceUUID = CBUUID(string: serviceUUID)
        self.dataCharacteristicUUID = CBUUID(string: dataCharacteristicUUID)
    }
    
    func startScanning() {
        discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(withServices: [smartRingServiceUUID!], options: nil)
        isScanning = true
        print("Scanning started...")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        print("Scanning stopped.")
    }
    
    func connect(peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        print(String(format: "Connected to %@", peripheral.name ?? "Unknown device"))
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripheral = nil
        print("Disconnected from \(peripheral.name ?? "Unknown device")")
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered ON")
        case .poweredOff:
            print("Bluetooth is powered OFF")
        case .unsupported:
            print( "Bluetooth is not supported on this device.")
        case .resetting:
            print( "Bluetooth is resetting.")
        case .unknown:
            print( "Bluetooth state unknown.")
        case .unauthorized:
            print( "Bluetooth is unauthorized.")
        @unknown default:
            print( "Unknown Bluetooth state.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
            print( "Discovered \(peripheral.name ?? "Unknown device")")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print( "Connected to \(peripheral.name ?? "Unknown device")")
        peripheral.discoverServices([smartRingServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "Unknown device")")
        connectedPeripheral = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print( "Failed to connect to \(peripheral.name ?? "Unknown device")")
        connectedPeripheral = nil
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print( "Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        for service in services {
            print( "Discovered service: \(service.uuid)")
            peripheral.discoverCharacteristics([dataCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("Discovered characteristic: \(characteristic)")
            if characteristic.uuid == dataCharacteristicUUID! {
                peripheral.setNotifyValue(true, for: characteristic) // Subscribe to notifications for data
                print("Subscribed to characteristic: \(characteristic)")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating value for characteristic: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }

        // Process the received data (parse and log)
        if characteristic.uuid == dataCharacteristicUUID! {
            // TODO: Process data here
        }
    }
    
    private func processData(data: Data) {
        // TODO: Copy parsing from Python library
    }
}
