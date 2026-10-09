import Foundation

/// Bluetooth icon + connected-device label for the status bar.
@MainActor
final class BluetoothViewModel: ObservableObject {
    @Published private(set) var powerOn = false
    @Published private(set) var connectedDevices: [BluetoothService.Device] = []

    private var timer: Timer?
    private var sampleGeneration: UInt64 = 0

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
        sampleGeneration &+= 1
    }

    func refresh() {
        sampleGeneration &+= 1
        let generation = sampleGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = BluetoothService.status()
            DispatchQueue.main.async {
                guard let self, generation == self.sampleGeneration else { return }
                if self.powerOn != status.powerOn {
                    self.powerOn = status.powerOn
                }
                if self.connectedDevices != status.connected {
                    self.connectedDevices = status.connected
                }
            }
        }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
