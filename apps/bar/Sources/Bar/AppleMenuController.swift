import AppKit
import SwiftUI

/// Themed Apple menu with ⌥ alternates (About ↔ System Information, Restart… ↔ Restart, …).
@MainActor
final class AppleMenuController: ObservableObject {
    static let shared = AppleMenuController()

    @Published private(set) var isPresented = false
    @Published var optionHeld = false
    @Published var hoveredItemID: String?

    private var panel: KeyableMenuPanel?
    private var flagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
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
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        isPresented = false
        optionHeld = false
        hoveredItemID = nil
    }

    private func present(relativeTo buttonFrameInScreen: NSRect, theme: ThemeConfig) {
        BarPopoverCoordinator.willPresent()
        optionHeld = NSEvent.modifierFlags.contains(.option)
        hoveredItemID = nil

        let root = AppleMenuView(controller: self, theme: theme)
        let hosting = NonVibrantMenuHostingView(rootView: root)
        let size = NSSize(width: 268, height: AppleMenuView.preferredHeight)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = KeyableMenuPanel(
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

        let x = buttonFrameInScreen.minX
        let y = buttonFrameInScreen.minY - size.height - 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        self.panel = panel
        isPresented = true
        installMonitors()
    }

    private func installMonitors() {
        removeMonitors()

        let updateOption: (NSEvent) -> Void = { [weak self] event in
            let held = event.modifierFlags.contains(.option)
            Task { @MainActor in
                guard let self, self.isPresented else { return }
                if self.optionHeld != held {
                    self.optionHeld = held
                }
            }
        }

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: updateOption)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            updateOption(event)
            return event
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                guard let self, self.isPresented, let panel = self.panel else { return }
                let screenPoint = Self.screenLocation(of: event)
                if !panel.frame.contains(screenPoint) {
                    self.dismiss()
                }
            }
        }
        // Global misses same-app clicks (other bar buttons). Local covers those, with
        // suppress so the originating Button's mouseUp does not immediately reopen.
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

        // Esc dismisses — local swallows the key when the panel is key; global covers the rest.
        let handleEscape: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == 53 else { return false } // Escape
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
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
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

/// Panel that can become key so Esc is delivered locally.
private final class KeyableMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class NonVibrantMenuHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

// MARK: - SwiftUI menu chrome

struct AppleMenuView: View {
    @ObservedObject var controller: AppleMenuController
    let theme: ThemeConfig

    static let preferredHeight: CGFloat = 8 + (10 * 28) + (3 * 9) + 8

    var body: some View {
        let option = controller.optionHeld

        VStack(alignment: .leading, spacing: 0) {
            item("about", option ? "System Information…" : "About This Mac") {
                option ? SystemActions.openSystemInformation() : SystemActions.openAboutThisMac()
            }
            item("settings", "System Settings…") { SystemActions.openSystemSettings() }
            item("appstore", "App Store…") { SystemActions.openAppStore() }

            separator

            item("forcequit", "Force Quit…") { SystemActions.forceQuit() }

            separator

            item("sleep", "Sleep") { SystemActions.sleep() }
            item("restart", option ? "Restart" : "Restart…") {
                option ? SystemActions.restartNow() : SystemActions.restart()
            }
            item("shutdown", option ? "Shut Down" : "Shut Down…") {
                option ? SystemActions.shutDownNow() : SystemActions.shutDown()
            }

            separator

            item("lock", "Lock Screen") { SystemActions.lockScreen() }
            item(
                "logout",
                option
                    ? "Log Out \(SystemActions.currentUserDisplayName)"
                    : "Log Out \(SystemActions.currentUserDisplayName)…"
            ) {
                option ? SystemActions.logOutNow() : SystemActions.logOut()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(width: 268, alignment: .leading)
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
        .animation(.easeOut(duration: 0.08), value: option)
        .animation(.easeOut(duration: 0.08), value: controller.hoveredItemID)
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

    private func item(_ id: String, _ title: String, action: @escaping () -> Void) -> some View {
        let highlighted = controller.hoveredItemID == id

        return Button {
            controller.dismiss()
            DispatchQueue.main.async(execute: action)
        } label: {
            Text(title)
                .foregroundColor(
                    highlighted
                        ? Color(hex: theme.backgroundColor)
                        : Color(hex: theme.textColor)
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
