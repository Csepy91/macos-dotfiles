import AppKit
import CoreLocation
import SwiftUI

/// Themed Wi-Fi popover: power toggle + scanned networks to join.
@MainActor
final class WiFiMenuController: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WiFiMenuController()

    @Published private(set) var isPresented = false
    @Published var hoveredItemID: String?
    @Published private(set) var powerOn = false
    @Published private(set) var currentSSID: String?
    @Published private(set) var networks: [WiFiService.Network] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage: String?

    private var panel: KeyableWiFiPanel?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var theme = ThemeConfig.catppuccinMacchiato
    private let locationManager = CLLocationManager()
    private var pendingScanAfterAuth = false
    /// Local mouseDown dismisses before Button mouseUp — suppress the reopen.
    private var suppressPresentUntil: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
    }

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
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        isPresented = false
        hoveredItemID = nil
        isScanning = false
        statusMessage = nil
        pendingScanAfterAuth = false
    }

    func togglePower() {
        let next = !powerOn
        statusMessage = next ? "Turning Wi-Fi on…" : "Turning Wi-Fi off…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            WiFiService.setPower(next)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let self, self.isPresented else { return }
                self.reloadStatus()
                if next {
                    self.beginScan()
                } else {
                    self.networks = []
                    self.statusMessage = nil
                    self.rebuildPanelContent()
                }
            }
        }
    }

    func join(_ network: WiFiService.Network) {
        statusMessage = "Joining \(network.ssid)…"
        rebuildPanelContent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var password = WiFiService.keychainPassword(for: network.ssid)
            if password == nil, !network.isOpen {
                let prompted = DispatchQueue.main.sync {
                    Self.promptPassword(for: network.ssid)
                }
                guard let prompted else {
                    DispatchQueue.main.async {
                        self?.statusMessage = nil
                        self?.rebuildPanelContent()
                    }
                    return
                }
                password = prompted
            }

            _ = WiFiService.join(ssid: network.ssid, password: password)
            Thread.sleep(forTimeInterval: 1.0)

            DispatchQueue.main.async {
                guard let self else { return }
                self.reloadStatus()
                self.statusMessage = nil
                self.dismiss()
            }
        }
    }

    // MARK: - Present

    private func present(relativeTo buttonFrameInScreen: NSRect, theme: ThemeConfig) {
        BarPopoverCoordinator.willPresent()
        self.theme = theme
        hoveredItemID = nil
        // Status (CoreWLAN / ipconfig) off-main, then show + scan.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = WiFiService.status()
            DispatchQueue.main.async {
                guard let self else { return }
                self.powerOn = status.powerOn
                self.currentSSID = status.ssid
                self.showPanel(relativeTo: buttonFrameInScreen)
                self.beginScan()
            }
        }
    }

    private func showPanel(relativeTo buttonFrameInScreen: NSRect) {
        let root = WiFiMenuView(controller: self, theme: theme)
        let hosting = NonVibrantWiFiHostingView(rootView: root)
        let size = preferredSize()
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = KeyableWiFiPanel(
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

        // Trailing-align under the Wi-Fi button (right-side control).
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
    }

    private func preferredSize() -> NSSize {
        let rows = 2 + (powerOn ? networks.count : 0) + (statusMessage != nil || isScanning ? 1 : 0)
        let height = 12 + CGFloat(max(rows, 2)) * 28 + 12
        return NSSize(width: 280, height: min(max(height, 96), 420))
    }

    private func rebuildPanelContent() {
        guard let panel else { return }
        let root = WiFiMenuView(controller: self, theme: theme)
        let hosting = NonVibrantWiFiHostingView(rootView: root)
        let size = preferredSize()
        hosting.frame = NSRect(origin: .zero, size: size)

        var frame = panel.frame
        let bottom = frame.maxY
        frame.size = size
        frame.origin.y = bottom - size.height
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
    }

    private func reloadStatus() {
        // CoreWLAN / ipconfig can block — never run on the main actor.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status = WiFiService.status()
            DispatchQueue.main.async {
                guard let self else { return }
                let powerChanged = self.powerOn != status.powerOn
                self.powerOn = status.powerOn
                self.currentSSID = status.ssid
                if self.isPresented, powerChanged {
                    self.rebuildPanelContent()
                }
            }
        }
    }

    private func beginScan() {
        guard powerOn else {
            networks = []
            isScanning = false
            statusMessage = nil
            rebuildPanelContent()
            return
        }

        ensureLocationThenScan()
    }

    private func ensureLocationThenScan() {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            performScan()
        case .notDetermined:
            pendingScanAfterAuth = true
            statusMessage = "Allow Location to scan…"
            rebuildPanelContent()
            locationManager.requestWhenInUseAuthorization()
        default:
            // Still try — CoreWLAN may work; SSID may be redacted.
            performScan()
        }
    }

    private func performScan() {
        isScanning = true
        statusMessage = "Scanning…"
        rebuildPanelContent()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = WiFiService.scan()
            DispatchQueue.main.async {
                guard let self, self.isPresented else { return }
                self.isScanning = false
                switch result {
                case .success(let nets):
                    self.networks = nets
                    self.statusMessage = nets.isEmpty ? "No networks found" : nil
                case .failure:
                    self.networks = []
                    self.statusMessage = "Scan failed"
                }
                self.rebuildPanelContent()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.pendingScanAfterAuth else { return }
            let status = manager.authorizationStatus
            guard status != .notDetermined else { return }
            self.pendingScanAfterAuth = false
            if self.isPresented, self.powerOn {
                self.performScan()
            }
        }
    }

    // MARK: - Password prompt

    private static func promptPassword(for ssid: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Password for “\(ssid)”"
        alert.informativeText = "Enter the Wi-Fi password to join this network."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue
        return value.isEmpty ? nil : value
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

private final class KeyableWiFiPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NonVibrantWiFiHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

// MARK: - SwiftUI

struct WiFiMenuView: View {
    @ObservedObject var controller: WiFiMenuController
    let theme: ThemeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            separator

            if controller.powerOn {
                item("power", icon: "wifi.slash", title: "Turn Wi-Fi Off") {
                    controller.togglePower()
                }
            } else {
                item("power", icon: "wifi", title: "Turn Wi-Fi On") {
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

            if controller.powerOn, !controller.networks.isEmpty {
                separator
                ForEach(controller.networks) { network in
                    networkRow(network)
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
            if !controller.powerOn { return "Wi-Fi Off" }
            if let ssid = controller.currentSSID { return "Connected: \(ssid)" }
            return "Select a network"
        }()
        let color = (!controller.powerOn || controller.currentSSID == nil)
            ? Color(hex: theme.subtextColor)
            : Color(hex: theme.accentColor)

        return HStack(spacing: 8) {
            Image(systemName: controller.powerOn ? "wifi" : "wifi.slash")
            Text(title)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func networkRow(_ network: WiFiService.Network) -> some View {
        let isCurrent = controller.currentSSID == network.ssid
        let title = isCurrent ? "\(network.ssid)  ✓" : network.ssid
        let icon = network.isOpen ? "lock.open.fill" : signalIcon(rssi: network.rssi)

        return item("net-\(network.ssid)", icon: icon, title: title, accent: isCurrent) {
            controller.join(network)
        }
    }

    private func signalIcon(rssi: Int) -> String {
        if rssi >= -55 { return "wifi" }
        if rssi >= -70 { return "wifi" }
        return "wifi.exclamationmark"
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
