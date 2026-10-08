import Foundation

/// Wi-Fi icon + down/up Mbps for the status bar.
@MainActor
final class WiFiViewModel: ObservableObject {
    @Published private(set) var powerOn = false
    @Published private(set) var connected = false
    @Published private(set) var ssid: String?
    @Published private(set) var rssi: Int?
    @Published private(set) var downMbps: Double = 0
    @Published private(set) var upMbps: Double = 0

    private var timer: Timer?
    private var interfaceName = "en0"
    private var prevSample: (t: TimeInterval, rx: UInt64, tx: UInt64)?

    var symbolName: String {
        guard powerOn else { return "wifi.slash" }
        guard connected else { return "wifi.slash" }
        guard let rssi else { return "wifi" }
        // Rough SF Symbol strength bands (RSSI dBm).
        if rssi >= -55 { return "wifi" }
        if rssi >= -70 { return "wifi" }
        return "wifi.exclamationmark"
    }

    var speedLabel: String {
        guard powerOn, connected else { return "offline" }
        return "↓\(Self.formatMbps(downMbps)) ↑\(Self.formatMbps(upMbps)) Mbps"
    }

    func start() {
        stop()
        tick()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        prevSample = nil
    }

    func refresh() {
        tick()
    }

    private func tick() {
        let status = WiFiService.status()
        interfaceName = status.interfaceName
        powerOn = status.powerOn
        connected = status.connected
        ssid = status.ssid
        rssi = status.rssi

        guard status.powerOn, status.connected,
              let bytes = WiFiService.linkBytes(interface: interfaceName)
        else {
            downMbps = 0
            upMbps = 0
            prevSample = nil
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let prev = prevSample {
            let dt = now - prev.t
            if dt >= 0.4 {
                let downBits = Double(bytes.rx &- prev.rx) * 8.0
                let upBits = Double(bytes.tx &- prev.tx) * 8.0
                downMbps = max(0, downBits / (dt * 1_000_000))
                upMbps = max(0, upBits / (dt * 1_000_000))
            }
        }
        prevSample = (now, bytes.rx, bytes.tx)
    }

    private static func formatMbps(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.0f", value)
    }
}
