import AppKit
import Foundation

/// System actions mirroring the macOS Apple menu.
enum SystemActions {
    private static let aboutThisMacURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/Applications/About This Mac.app"
    )

    static func openAboutThisMac() {
        if FileManager.default.fileExists(atPath: aboutThisMacURL.path) {
            NSWorkspace.shared.open(aboutThisMacURL)
            return
        }
        openURL("x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension")
    }

    static func openSystemInformation() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app"))
    }

    static func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preferences") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        openURL("x-apple.systempreferences:")
    }

    /// Opens System Settings → Battery (Ventura+ pane, with older fallbacks).
    static func openBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.battery",
            "x-apple.systempreferences:com.apple.settings.Battery"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        openSystemSettings()
    }

    static func openActivityMonitor() {
        let config = NSWorkspace.OpenConfiguration()
        // Prefer bundle-id lookup — `open(fileURL)` can reveal the .app package in Finder.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        let path = "/System/Applications/Utilities/Activity Monitor.app"
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    static func openAppStore() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AppStore") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func forceQuit() {
        // ⌘⌥⎋ — opens the Force Quit Applications window.
        runAppleScript(
            """
            tell application "System Events"
              key code 53 using {command down, option down}
            end tell
            """
        )
    }

    static func sleep() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                NSLog("[Bar] pmset sleepnow failed: \(error)")
            }
        }
    }

    /// Restart with the standard confirmation sheet.
    static func restart() {
        runAppleScript("tell application \"System Events\" to restart")
    }

    /// Restart immediately (⌥ alternate — no confirmation).
    static func restartNow() {
        runAppleScript("tell application \"loginwindow\" to «event aevtrrst»")
    }

    /// Shut down with the standard confirmation sheet.
    static func shutDown() {
        runAppleScript("tell application \"System Events\" to shut down")
    }

    /// Shut down immediately (⌥ alternate — no confirmation).
    static func shutDownNow() {
        runAppleScript("tell application \"loginwindow\" to «event aevtrsdn»")
    }

    static func lockScreen() {
        // Prefer Control+Command+Q; fall back to CGSession.
        runAppleScript(
            """
            tell application "System Events"
              keystroke "q" using {command down, control down}
            end tell
            """
        )
    }

    /// Log out with confirmation.
    static func logOut() {
        runAppleScript("tell application \"System Events\" to log out")
    }

    /// Log out immediately (⌥ alternate — no confirmation).
    static func logOutNow() {
        runAppleScript("tell application \"loginwindow\" to «event aevtlogo»")
    }

    static var currentUserDisplayName: String {
        let name = NSFullUserName()
        return name.isEmpty ? NSUserName() : name
    }

    // MARK: - Helpers

    private static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
                if let error {
                    NSLog("[Bar] AppleScript failed: \(error)")
                }
            }
        }
    }
}
