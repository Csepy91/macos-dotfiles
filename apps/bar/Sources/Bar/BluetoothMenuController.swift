import AppKit
import SwiftUI

/// Themed Bluetooth popover: power toggle + paired devices to connect/disconnect.
@MainActor
final class BluetoothMenuController: ObservableObject {
    static let shared = BluetoothMenuController()

    @Published private(set) var isPresented = false
    @Published var hoveredItemID: String?
    @Published private(set) var powerOn = false
    @Published private(set) var devices: [BluetoothService.Device] = []
    @Published private(set) var statusMessage: String?

    private var panel: KeyableBluetoothPanel?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var theme = ThemeConfig.catppuccinMacchiato
    private var refreshTimer: Timer?
    /// Local mouseDown dismisses before Button mouseUp — suppress the reopen.
    private var suppressPresentUntil: Date?

    private init() {}

    func toggle(relativeTo buttonFrameInScreen: NSRect, theme: ThemeConfig) {
        if let until = suppressPresentUntil, Date() < until {
            suppressPresentUntil = nil
            return
        }
        if isPresented {
            dismiss()
        } else {
            present(relativeTo: buttonFrameInScreen, theme: theme)
        }
    }

    func dismiss() {
        stopRefreshTimer()
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        isPresented = false
        hoveredItemID = nil
        statusMessage = nil
    }

    func togglePower() {
        let next = !powerOn
        statusMessage = next ? "Turning Bluetooth on…" : "Turning Bluetooth off…"
        rebuildPanelContent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            BluetoothService.setPower(next)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, self.isPresented else { return }
                self.reload()
                self.statusMessage = nil
                self.rebuildPanelContent()
            }
        }
    }

    func toggleConnection(_ device: BluetoothService.Device) {
        let connecting = !device.isConnected
        statusMessage = connecting ? "Connecting \(device.name)…" : "Disconnecting \(device.name)…"
        rebuildPanelContent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if connecting {
                _ = BluetoothService.connect(address: device.address)
            } else {
                _ = BluetoothService.disconnect(address: device.address)
            }
            Thread.sleep(forTimeInterval: 0.4)
            DispatchQueue.main.async {
                guard let self, self.isPresented else { return }
                self.reload()
                self.statusMessage = nil
                self.rebuildPanelContent()
            }
        }
    }

    func openBluetoothSettings() {
        dismiss()
        let candidates = [
            "x-apple.systempreferences:com.apple.BluetoothSettings",
            "x-apple.systempreferences:com.apple.preference.bluetooth"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        SystemActions.openSystemSettings()
    }

    // MARK: - Present

    private func present(relativeTo buttonFrameInScreen: NSRect, theme: ThemeConfig) {
        BarPopoverCoordinator.willPresent()
        self.theme = theme
        hoveredItemID = nil
        reload()

        let root = BluetoothMenuView(controller: self, theme: theme)
        let hosting = NonVibrantBluetoothHostingView(rootView: root)
        let size = preferredSize()
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = KeyableBluetoothPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        let x = buttonFrameInScreen.maxX - size.width
        let y = buttonFrameInScreen.minY - size.height - 4
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(buttonFrameInScreen) })
            ?? NSScreen.main
        var frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = max(frame.origin.y, visible.minY + 8)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        self.panel = panel
        isPresented = true
        installMonitors()
        startRefreshTimer()
    }

    private func preferredSize() -> NSSize {
        let rows = 3 + (powerOn ? devices.count : 0) + (statusMessage != nil ? 1 : 0)
        let height = 12 + CGFloat(max(rows, 3)) * 28 + 12
        return NSSize(width: 280, height: min(max(height, 110), 420))
    }

    private func rebuildPanelContent() {
        guard let panel else { return }
        let root = BluetoothMenuView(controller: self, theme: theme)
        let hosting = NonVibrantBluetoothHostingView(rootView: root)
        let size = preferredSize()
        hosting.frame = NSRect(origin: .zero, size: size)

        var frame = panel.frame
        let bottom = frame.maxY
        frame.size = size
        frame.origin.y = bottom - size.height
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
    }

    private func reload() {
        let status = BluetoothService.status()
        powerOn = status.powerOn
        devices = powerOn ? BluetoothService.pairedDevices() : []
    }

    private func startRefreshTimer() {
        stopRefreshTimer()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                let before = self.devices
                let beforePower = self.powerOn
                self.reload()
                if before != self.devices || beforePower != self.powerOn {
                    self.rebuildPanelContent()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.isPresented, let panel = self.panel else { return }
                let screenPoint = Self.screenLocation(of: event)
                if !panel.frame.contains(screenPoint) {
                    self.dismiss()
                }
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.isPresented, let panel = self.panel else { return }
                let screenPoint = Self.screenLocation(of: event)
                if !panel.frame.contains(screenPoint) {
                    self.suppressPresentUntil = Date().addingTimeInterval(0.35)
                    self.dismiss()
                }
            }
            return event
        }

        let handleEscape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            Task { @MainActor in
                self?.dismiss()
            }
            return true
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleEscape(event) ? nil : event
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            _ = handleEscape(event)
        }
    }

    private func removeMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private static func screenLocation(of event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return event.locationInWindow
    }
}

private final class KeyableBluetoothPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NonVibrantBluetoothHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

// MARK: - SwiftUI

struct BluetoothMenuView: View {
    @ObservedObject var controller: BluetoothMenuController
    let theme: ThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            separator

            if controller.powerOn {
                item("power", icon: "bluetooth.slash", title: "Turn Bluetooth Off") {
                    controller.togglePower()
                }
            } else {
                item("power", icon: "bluetooth", title: "Turn Bluetooth On") {
                    controller.togglePower()
                }
            }

            if let message = controller.statusMessage {
                Text(message)
                    .font(menuFont)
                    .foregroundColor(Color(hex: theme.subtextColor))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            if controller.powerOn {
                if !controller.devices.isEmpty {
                    separator
                    ForEach(controller.devices) { device in
                        deviceRow(device)
                    }
                }

                separator

                item("settings", icon: "gearshape", title: "Bluetooth Settings…") {
                    controller.openBluetoothSettings()
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: theme.backgroundColor, opacity: max(theme.backgroundOpacity, 0.94)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(hex: theme.borderColor).opacity(0.5), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .font(menuFont)
        .foregroundColor(Color(hex: theme.textColor))
        .animation(.easeOut(duration: 0.08), value: controller.hoveredItemID)
    }

    private var header: some View {
        let title: String = {
            if !controller.powerOn { return "Bluetooth Off" }
            let connected = controller.devices.filter(\.isConnected)
            if let first = connected.first {
                if connected.count == 1 {
                    return "Connected: \(first.name)"
                }
                return "Connected: \(connected.count) devices"
            }
            return "Not Connected"
        }()
        let color = (!controller.powerOn || !controller.devices.contains(where: \.isConnected))
            ? Color(hex: theme.subtextColor)
            : Color(hex: theme.accentColor)

        return HStack(spacing: 8) {
            Image(systemName: controller.powerOn ? "bluetooth" : "bluetooth.slash")
            Text(title)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func deviceRow(_ device: BluetoothService.Device) -> some View {
        let title = device.isConnected ? "\(device.name)  ✓" : device.name
        let icon = device.isConnected ? "checkmark.circle.fill" : "circle"
        return item("dev-\(device.address)", icon: icon, title: title, accent: device.isConnected) {
            controller.toggleConnection(device)
        }
    }

    private var menuFont: Font {
        let size = theme.fontSize
        if NSFont(name: theme.fontFamily, size: size) != nil {
            return .custom(theme.fontFamily, size: size)
        }
        return .system(size: size)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(hex: theme.borderColor).opacity(0.35))
            .frame(height: 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
    }

    private func item(
        _ id: String,
        icon: String,
        title: String,
        accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let highlighted = controller.hoveredItemID == id
        let base = accent ? Color(hex: theme.accentColor) : Color(hex: theme.textColor)

        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(
                highlighted
                    ? Color(hex: theme.backgroundColor)
                    : base
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: theme.accentColor).opacity(highlighted ? 1.0 : 0.0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                controller.hoveredItemID = id
            } else if controller.hoveredItemID == id {
                controller.hoveredItemID = nil
            }
        }
    }
}
