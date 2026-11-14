import CoreBluetooth
import Foundation

/// Reads the standard GATT Battery Service (0x180F) of Bluetooth LE keyboards macOS is already connected to.
/// It only shares the system's existing link (no pairing, no writes). Bluetooth permission is asked for the
/// first time a Bluetooth LE keyboard shows up, never before.
final class BluetoothBatteryMonitor: NSObject {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    /// Lowercased peripheral name → battery levels (split keyboards report one per half).
    var onChange: (([String: [Int]]) -> Void)?

    private var central: CBCentralManager?
    private var wantedNames: Set<String> = []
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// Per peripheral, in discovery order, so halves keep their position.
    private var levels: [UUID: [(characteristic: ObjectIdentifier, value: Int)]] = [:]

    /// Watch these Bluetooth LE keyboards (by product name, which is also their advertised name).
    func watch(names: Set<String>) {
        wantedNames = Set(names.map { $0.lowercased() })
        if central == nil {
            // An app without the usage description is killed on first Bluetooth access (e.g. `swift run`).
            guard !wantedNames.isEmpty,
                  Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil else { return }
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        connectWanted()
    }

    /// Re-read levels for keyboards whose firmware does not notify on change.
    func refresh() {
        for peripheral in peripherals.values where peripheral.state == .connected {
            for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
                for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
        connectWanted()
    }

    private func connectWanted() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let wanted = connected.filter { wantedNames.contains(($0.name ?? "").lowercased()) }
        let wantedIDs = Set(wanted.map(\.identifier))

        for (id, peripheral) in peripherals where !wantedIDs.contains(id) {
            central.cancelPeripheralConnection(peripheral)
            forget(id)
        }
        for peripheral in wanted where peripherals[peripheral.identifier] == nil {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
        publish()
    }

    private func forget(_ id: UUID) {
        peripherals[id] = nil
        levels[id] = nil
    }

    private func publish() {
        var result: [String: [Int]] = [:]
        for (id, values) in levels where !values.isEmpty {
            guard let name = peripherals[id]?.name?.lowercased() else { continue }
            result[name, default: []].append(contentsOf: values.map(\.value))
        }
        onChange?(result)
    }
}

extension BluetoothBatteryMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            connectWanted()
        } else {
            peripherals.removeAll()
            levels.removeAll()
            publish()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        forget(peripheral.identifier)
        publish()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        forget(peripheral.identifier)
        publish()
    }
}

extension BluetoothBatteryMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
            peripheral.readValue(for: characteristic)
            if characteristic.properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.batteryLevel, let byte = characteristic.value?.first,
              peripherals[peripheral.identifier] != nil else { return }
        let key = ObjectIdentifier(characteristic)
        var values = levels[peripheral.identifier] ?? []
        if let index = values.firstIndex(where: { $0.characteristic == key }) {
            values[index].value = Int(byte)
        } else {
            values.append((key, Int(byte)))
        }
        levels[peripheral.identifier] = values
        publish()
    }
}
