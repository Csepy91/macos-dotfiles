import AppKit
import Foundation
import IOKit.ps

/// Internal battery percentage + charging state for the status bar.
@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var percent: Int?
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isPluggedIn: Bool = false

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    /// Weak bridge so the IOPS C callback never holds `self` unretained.
    private var powerSourceBridge: PowerSourceBridge?

    var isPresent: Bool { percent != nil }

    var percentLabel: String {
        guard let percent else { return "—" }
        return "\(percent)%"
    }

    var showsBolt: Bool { isCharging || isPluggedIn }

    func start() {
        stop()
        refresh()
        installPowerSourceNotifications()

        // Slow backup poll in case a notification is missed.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        removePowerSourceNotifications()
    }

    func refresh() {
        guard let snapshot = Self.readInternalBattery() else {
            if percent != nil {
                percent = nil
                isCharging = false
                isPluggedIn = false
            }
            return
        }
        if percent != snapshot.percent {
            percent = snapshot.percent
        }
        if isCharging != snapshot.charging {
            isCharging = snapshot.charging
        }
        if isPluggedIn != snapshot.pluggedIn {
            isPluggedIn = snapshot.pluggedIn
        }
    }

    // MARK: - Immediate power-source callbacks

    private func installPowerSourceNotifications() {
        removePowerSourceNotifications()
        let bridge = PowerSourceBridge()
        bridge.model = self
        powerSourceBridge = bridge
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let bridge = Unmanaged<PowerSourceBridge>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                bridge.model?.refresh()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            NSLog("[Bar] IOPSNotificationCreateRunLoopSource failed")
            powerSourceBridge = nil
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
    }

    private func removePowerSourceNotifications() {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = nil
        }
        powerSourceBridge = nil
    }

    /// Opaque target for `IOPSNotificationCreateRunLoopSource` (must outlive the source).
    private final class PowerSourceBridge {
        weak var model: BatteryViewModel?
    }

    // MARK: - IOKit

    private struct Snapshot {
        let percent: Int
        let charging: Bool
        let pluggedIn: Bool
    }

    private static func readInternalBattery() -> Snapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent: Int
            if maxCapacity > 0, maxCapacity != 100 {
                percent = Int((Double(current) / Double(maxCapacity) * 100).rounded())
            } else {
                percent = Swift.min(Swift.max(current, 0), 100)
            }

            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = state == kIOPSACPowerValue

            return Snapshot(percent: percent, charging: charging, pluggedIn: pluggedIn)
        }
        return nil
    }
}
