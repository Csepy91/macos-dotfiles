import Foundation

/// Bluetooth icon + connected-device label for the status bar.
@MainActor
final class BluetoothViewModel: ObservableObject {
    @Published private(set) var powerOn = false
    @Published private(set) var connectedDevices: [BluetoothService.Device] = []

    private var timer: Timer?

    var symbolName: String {
        powerOn ? "bluetooth" : "bluetooth.slash"
    }

    var statusLabel: String {
        if !powerOn { return "off" }
        if let first = connectedDevices.first {
            return Self.truncate(first.name, limit: 16)
        }
        return "on"
    }

    var helpText: String {
        if !powerOn { return "Bluetooth Off" }
        if connectedDevices.isEmpty { return "Bluetooth On" }
        let names = connectedDevices.map(\.name).joined(separator: ", ")
        return "Bluetooth: \(names)"
    }

    func start() {
        stop()
        refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let status = BluetoothService.status()
        if powerOn != status.powerOn {
            powerOn = status.powerOn
        }
        if connectedDevices != status.connected {
            connectedDevices = status.connected
        }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
