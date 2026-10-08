import Foundation
import IOBluetooth

/// Low-level Bluetooth helpers via IOBluetooth (+ power preference SPI).
enum BluetoothService {
    /// Serialize IOBluetooth / power SPI across the bar poll and menu actions.
    private static let lock = NSLock()

    struct Device: Identifiable, Equatable {
        var id: String { address }
        let address: String
        let name: String
        let isConnected: Bool
    }

    struct Status: Equatable {
        let powerOn: Bool
        let connected: [Device]
    }

    // Undocumented but stable SPI used by blueutil / most status bars.
    @_silgen_name("IOBluetoothPreferenceGetControllerPowerState")
    private static func getPowerState() -> Int32

    @_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
    private static func setPowerState(_ state: Int32)

    static func status() -> Status {
        lock.lock()
        defer { lock.unlock() }
        let powerOn = getPowerState() != 0
        guard powerOn else {
            return Status(powerOn: false, connected: [])
        }
        let connected = pairedDevicesUnlocked().filter(\.isConnected)
        return Status(powerOn: true, connected: connected)
    }

    static func setPower(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        setPowerState(on ? 1 : 0)
    }

    static func pairedDevices() -> [Device] {
        lock.lock()
        defer { lock.unlock() }
        return pairedDevicesUnlocked()
    }

    private static func pairedDevicesUnlocked() -> [Device] {
        guard let raw = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        let devices: [Device] = raw.compactMap { device in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            let name = (device.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? address
            return Device(address: address, name: name, isConnected: device.isConnected())
        }
        return devices.sorted { lhs, rhs in
            if lhs.isConnected != rhs.isConnected { return lhs.isConnected && !rhs.isConnected }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    static func connect(address: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        if device.isConnected() { return true }
        return device.openConnection() == kIOReturnSuccess
    }

    @discardableResult
    static func disconnect(address: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let device = IOBluetoothDevice(addressString: address) else { return false }
        guard device.isConnected() else { return true }
        return device.closeConnection() == kIOReturnSuccess
    }
}
