import AppKit
import ApplicationServices
import Combine
import Foundation

/// Native macOS fullscreen only: hide the bar, reveal it when the pointer
/// hits the top edge (menu-bar style), hide again when the pointer leaves.
@MainActor
final class FullscreenMonitor: ObservableObject {
    /// Drive window visibility from this — not raw `isFullscreen`.
    @Published private(set) var shouldHideBar = false

    private(set) var isFullscreen = false

    /// Once revealed, keep the bar up while the pointer stays in this top band.
    var barHeight: CGFloat = 38

    private var observers: [NSObjectProtocol] = []
    private var debounce: DispatchWorkItem?
    private var hideLeaveWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var isRunning = false
    private var isRevealed = false

    /// Hot edge that triggers reveal (points from top of screen).
    private let revealEdge: CGFloat = 39
    /// Extra padding below the bar before we consider the pointer “away”.
    private let stayPadding: CGFloat = 39
    private let hideDelay: TimeInterval = 0.5

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installObservers()
        scheduleFullscreenEvaluate(delay: 0)
    }

    func stop() {
        isRunning = false
        debounce?.cancel()
        debounce = nil
        hideLeaveWork?.cancel()
        hideLeaveWork = nil
        stopMousePolling()
        removeObservers()
        isFullscreen = false
        isRevealed = false
        shouldHideBar = false
    }

    // MARK: - Observers

    private func installObservers() {
        removeObservers()
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default

        observers = [
            workspace.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleFullscreenEvaluate(delay: 0.05) }
            },
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleFullscreenEvaluate(delay: 0.08) }
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.scheduleFullscreenEvaluate(delay: 0.08) }
            }
        ]
    }

    private func removeObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        for obs in observers {
            workspace.removeObserver(obs)
            center.removeObserver(obs)
        }
        observers.removeAll()
    }

    // MARK: - Fullscreen evaluate

    private func scheduleFullscreenEvaluate(delay: TimeInterval) {
        guard isRunning else { return }
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateFullscreen()
        }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func evaluateFullscreen() {
        guard isRunning else { return }
        let next = Self.isNativeFullscreenSpace()
        guard next != isFullscreen else {
            if next { updateRevealFromMouse() }
            return
        }

        isFullscreen = next
        if next {
            isRevealed = false
            shouldHideBar = true
            startMousePolling()
            updateRevealFromMouse()
        } else {
            stopMousePolling()
            hideLeaveWork?.cancel()
            hideLeaveWork = nil
            isRevealed = false
            shouldHideBar = false
        }
    }

    // MARK: - Top-edge reveal

    private func startMousePolling() {
        stopMousePolling()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateRevealFromMouse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopMousePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func updateRevealFromMouse() {
        guard isRunning, isFullscreen else { return }

        let inZone = Self.pointerInTopZone(
            revealed: isRevealed,
            revealEdge: revealEdge,
            stayHeight: barHeight + stayPadding
        )

        if inZone {
            hideLeaveWork?.cancel()
            hideLeaveWork = nil
            if !isRevealed || shouldHideBar {
                isRevealed = true
                shouldHideBar = false
            }
            return
        }

        guard isRevealed || !shouldHideBar else { return }
        guard hideLeaveWork == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.isFullscreen else { return }
            // Re-check — pointer may have returned during the delay.
            if Self.pointerInTopZone(
                revealed: true,
                revealEdge: self.revealEdge,
                stayHeight: self.barHeight + self.stayPadding
            ) {
                self.hideLeaveWork = nil
                return
            }
            self.isRevealed = false
            self.shouldHideBar = true
            self.hideLeaveWork = nil
        }
        hideLeaveWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: item)
    }

    /// AppKit coords: Y grows upward; top of screen is `frame.maxY`.
    nonisolated static func pointerInTopZone(
        revealed: Bool,
        revealEdge: CGFloat,
        stayHeight: CGFloat
    ) -> Bool {
        let loc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) })
                ?? NSScreen.main
        else { return false }

        let distanceFromTop = screen.frame.maxY - loc.y
        let threshold = revealed ? stayHeight : revealEdge
        return distanceFromTop >= 0 && distanceFromTop <= threshold
    }

    // MARK: - Detection

    nonisolated static func isNativeFullscreenSpace() -> Bool {
        if let ax = frontmostWindowIsFullscreen() {
            return ax
        }
        if let hasMenuStrip = hasSystemMenuBarStrip() {
            return !hasMenuStrip
        }
        return false
    }

    nonisolated static func frontmostWindowIsFullscreen() -> Bool? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.dotfiles.bar"
        else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if let focused = copyAXWindow(axApp, attribute: kAXFocusedWindowAttribute as CFString),
           let value = copyAXFullscreen(focused) {
            return value
        }
        if let main = copyAXWindow(axApp, attribute: kAXMainWindowAttribute as CFString),
           let value = copyAXFullscreen(main) {
            return value
        }
        return nil
    }

    nonisolated private static func copyAXWindow(
        _ element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let ref
        else { return nil }
        return (ref as! AXUIElement)
    }

    nonisolated private static func copyAXFullscreen(_ window: AXUIElement) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &ref) == .success else {
            return nil
        }
        if let number = ref as? NSNumber { return number.boolValue }
        if let bool = ref as? Bool { return bool }
        return nil
    }

    nonisolated static func hasSystemMenuBarStrip() -> Bool? {
        guard let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for window in info {
            guard (window[kCGWindowOwnerName as String] as? String) == "Window Server" else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer > 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let height = bounds["Height"] as? CGFloat
            else { continue }
            if height >= 16, height <= 48 {
                return true
            }
        }
        return false
    }
}
