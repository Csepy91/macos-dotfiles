import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Opens OmniWM's native status-item dropdown ("OmniWM Controls" — settings, IPC, …)
/// via Accessibility. No repositioning — OmniWM places the panel itself.
enum OmniWMControlsController {
    private static let omniBundleID = "com.barut.OmniWM"
    private static let controlsTitle = "OmniWM Controls"

    /// True after we open Controls until it is dismissed.
    private static var openedByUs = false
    /// Set on mouseDown in Bar while Controls is up so the following button
    /// action does not reopen (OmniWM closes on mouseDown; Button fires on mouseUp).
    private static var suppressOpenUntil: Date?
    private static var dismissWatcher: DispatchWorkItem?
    private static var mouseDownMonitor: Any?

    @MainActor
    static func toggle() {
        if let until = suppressOpenUntil, Date() < until {
            suppressOpenUntil = nil
            openedByUs = false
            stopDismissWatcher()
            removeMouseDownGuard()
            return
        }

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            NSLog("[Bar] Accessibility required to open OmniWM Controls")
            return
        }

        ensureOmniWMRunning()

        guard let ax = omniAppElement(), let extras = omniExtrasItem(ax) else {
            NSLog("[Bar] OmniWM extras menu item not found")
            return
        }

        let panelOpen = findControlsPanel(ax) != nil

        if panelOpen || openedByUs {
            if panelOpen {
                axPress(extras)
            }
            openedByUs = false
            suppressOpenUntil = Date().addingTimeInterval(0.45)
            stopDismissWatcher()
            removeMouseDownGuard()
            return
        }

        // Single Press only — Cancel+Press closed then immediately reopened.
        axPress(extras)
        openedByUs = true
        installMouseDownGuard()
        startDismissWatcher(ax: ax)
    }

    // MARK: - OmniWM AX

    private static func ensureOmniWMRunning() {
        if isOmniWMRunning() { return }
        let url = URL(fileURLWithPath: "/Applications/OmniWM.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        // Yield to the run loop instead of hard-blocking the main thread with usleep.
        for _ in 0..<12 {
            if isOmniWMRunning() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func isOmniWMRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == omniBundleID })
    }

    private static func omniAppElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == omniBundleID
        }) else {
            return nil
        }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    private static func omniExtrasItem(_ ax: AXUIElement) -> AXUIElement? {
        var extras: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXExtrasMenuBarAttribute as CFString, &extras) == .success,
              let extrasBar = extras
        else {
            return nil
        }
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(
            extrasBar as! AXUIElement,
            kAXVisibleChildrenAttribute as CFString,
            &children
        ) == .success,
            let items = children as? [AXUIElement],
            let item = items.first
        else {
            return nil
        }
        return item
    }

    private static func findControlsPanel(_ ax: AXUIElement) -> AXUIElement? {
        var wins: AnyObject?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wins) == .success,
              let windows = wins as? [AXUIElement]
        else {
            return nil
        }
        for window in windows {
            var title: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if (title as? String) == controlsTitle {
                return window
            }
        }
        return nil
    }

    private static func axPress(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// Any click inside Bar while Controls is open arms suppress so the cog
    /// Button action (mouseUp) does not reopen after OmniWM's mouseDown dismiss.
    private static func installMouseDownGuard() {
        removeMouseDownGuard()
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if openedByUs {
                suppressOpenUntil = Date().addingTimeInterval(0.45)
            }
            return event
        }
    }

    private static func removeMouseDownGuard() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
    }

    /// Clear `openedByUs` when Controls is dismissed without using the cog.
    private static func startDismissWatcher(ax: AXUIElement) {
        stopDismissWatcher()
        let item = DispatchWorkItem {
            guard openedByUs else { return }
            if findControlsPanel(ax) == nil {
                // Panel gone. If suppress is still active (local mouseDown just closed it),
                // keep polling until suppress expires so openedByUs / the mouse guard clear.
                if let until = suppressOpenUntil, Date() < until {
                    startDismissWatcher(ax: ax)
                    return
                }
                openedByUs = false
                suppressOpenUntil = nil
                removeMouseDownGuard()
                stopDismissWatcher()
                return
            }
            startDismissWatcher(ax: ax)
        }
        dismissWatcher = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private static func stopDismissWatcher() {
        dismissWatcher?.cancel()
        dismissWatcher = nil
    }

    /// Drop monitors / watchers on process terminate.
    @MainActor
    static func cleanup() {
        stopDismissWatcher()
        removeMouseDownGuard()
        openedByUs = false
        suppressOpenUntil = nil
    }
}
