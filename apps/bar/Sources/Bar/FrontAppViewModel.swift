import AppKit
import Foundation

/// Tracks the frontmost / focused application for the bar pill.
@MainActor
final class FrontAppViewModel: ObservableObject {
    @Published private(set) var appName: String = ""
    @Published private(set) var bundleID: String?
    @Published private(set) var icon: NSImage?

    private var activateObserver: NSObjectProtocol?
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.dotfiles.bar"

    func start() {
        stop()
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
            self.activateObserver = nil
        }
    }

    func refresh() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            appName = ""
            bundleID = nil
            icon = nil
            return
        }
        // Ignore Bar itself so a click on the strip does not blank the pill.
        if app.bundleIdentifier == ownBundleID {
            return
        }
        appName = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? app.bundleIdentifier
            ?? ""
        bundleID = app.bundleIdentifier
        icon = app.icon
    }
}
