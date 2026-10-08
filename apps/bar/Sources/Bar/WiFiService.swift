import CoreWLAN
import Foundation
import Security

/// Low-level Wi-Fi helpers (CoreWLAN + networksetup + Keychain).
enum WiFiService {
    /// CoreWLAN is not thread-safe — serialize all shared-client access.
    private static let coreWLANLock = NSLock()

    struct Network: Identifiable, Equatable {
        var id: String { ssid }
        let ssid: String
        let rssi: Int
        let isOpen: Bool
    }

    struct Status: Equatable {
        let powerOn: Bool
        let connected: Bool
        let ssid: String?
        let rssi: Int?
        let interfaceName: String
    }

    static func hardwareInterfaceName() -> String {
        coreWLANLock.lock()
        defer { coreWLANLock.unlock() }
        return hardwareInterfaceNameUnlocked()
    }

    private static func hardwareInterfaceNameUnlocked() -> String {
        if let name = CWWiFiClient.shared().interface()?.interfaceName, !name.isEmpty {
            return name
        }
        return parseHardwarePort() ?? "en0"
    }

    static func status() -> Status {
        coreWLANLock.lock()
        defer { coreWLANLock.unlock() }

        let ifaceName = hardwareInterfaceNameUnlocked()
        guard let iface = CWWiFiClient.shared().interface() else {
            return Status(powerOn: false, connected: false, ssid: nil, rssi: nil, interfaceName: ifaceName)
        }
        let power = iface.powerOn()
        guard power else {
            return Status(powerOn: false, connected: false, ssid: nil, rssi: nil, interfaceName: ifaceName)
        }

        // CoreWLAN SSID is often redacted without Location; fall back to ipconfig.
        let ssid = iface.ssid() ?? currentSSID(interface: ifaceName)
        let rssiValue = iface.rssiValue()
        // Associated interfaces report negative RSSI; 0 usually means idle/disconnected.
        let hasSignal = rssiValue < 0
        let connected = ssid != nil || hasSignal
        return Status(
            powerOn: true,
            connected: connected,
            ssid: ssid,
            rssi: hasSignal ? Int(rssiValue) : nil,
            interfaceName: ifaceName
        )
    }

    static func setPower(_ on: Bool) {
        let iface = hardwareInterfaceName()
        run("/usr/sbin/networksetup", ["-setairportpower", iface, on ? "on" : "off"])
    }

    /// Scan nearby networks (requires Location on recent macOS). Sorted by RSSI.
    static func scan(limit: Int = 14) -> Result<[Network], Error> {
        coreWLANLock.lock()
        defer { coreWLANLock.unlock() }

        guard let iface = CWWiFiClient.shared().interface(), iface.powerOn() else {
            return .success([])
        }
        do {
            let nets = try iface.scanForNetworks(withName: nil)
            var best: [String: (rssi: Int, open: Bool)] = [:]
            for n in nets {
                guard let ssid = n.ssid, !ssid.isEmpty else { continue }
                let open = n.supportsSecurity(.none)
                let rssi = Int(n.rssiValue)
                if let prev = best[ssid] {
                    if rssi > prev.rssi { best[ssid] = (rssi, open) }
                } else {
                    best[ssid] = (rssi, open)
                }
            }
            let rows = best
                .map { Network(ssid: $0.key, rssi: $0.value.rssi, isOpen: $0.value.open) }
                .sorted { $0.rssi > $1.rssi }
            return .success(Array(rows.prefix(limit)))
        } catch {
            return .failure(error)
        }
    }

    /// Join `ssid`. Uses Keychain AirPort password when present; otherwise `password`.
    @discardableResult
    static func join(ssid: String, password: String? = nil) -> Bool {
        let iface = hardwareInterfaceName()
        let pass = password ?? keychainPassword(for: ssid) ?? ""
        if pass.isEmpty {
            return run("/usr/sbin/networksetup", ["-setairportnetwork", iface, ssid])
        }
        return run("/usr/sbin/networksetup", ["-setairportnetwork", iface, ssid, pass])
    }

    static func keychainPassword(for ssid: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrDescription as String: "AirPort network password",
            kSecAttrAccount as String: ssid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Link-layer byte counters for throughput sampling.
    static func linkBytes(interface: String) -> (rx: UInt64, tx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name == interface,
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_LINK),
               let data = current.pointee.ifa_data {
                let ifdata = data.assumingMemoryBound(to: if_data.self)
                return (UInt64(ifdata.pointee.ifi_ibytes), UInt64(ifdata.pointee.ifi_obytes))
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    // MARK: - Helpers

    private static func currentSSID(interface: String) -> String? {
        let out = capture("/usr/sbin/ipconfig", ["getsummary", interface])
        for line in out.split(separator: "\n") {
            // "  SSID : MyNetwork"
            if let range = line.range(of: "SSID : ") {
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func parseHardwarePort() -> String? {
        let out = capture("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for i in 0..<lines.count {
            let line = lines[i]
            if line.contains("Wi-Fi") || line.contains("AirPort") {
                if i + 1 < lines.count {
                    let deviceLine = lines[i + 1]
                    if let range = deviceLine.range(of: "Device: ") {
                        return String(deviceLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func capture(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
