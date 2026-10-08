import AppKit
import Combine
import Foundation
import SwiftUI

enum LauncherMode: String {
    case apps = "Apps"
    case menu = "Menu"
}

enum LauncherItem: Identifiable, Hashable {
    case app(LauncherApp)
    case menu(MenuCommand)

    var id: String {
        switch self {
        case .app(let app): return "app:\(app.id)"
        case .menu(let cmd): return "menu:\(cmd.id)"
        }
    }

    var title: String {
        switch self {
        case .app(let app): return app.name
        case .menu(let cmd): return cmd.displayTitle
        }
    }

    var subtitle: String {
        switch self {
        case .app(let app): return app.path
        case .menu: return ""
        }
    }

    var searchKey: String {
        switch self {
        case .app(let app): return app.name
        case .menu(let cmd): return cmd.path
        }
    }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var mode: LauncherMode = .apps
    @Published var selectedIndex: Int = 0
    @Published var results: [LauncherItem] = []
    @Published var accessibilityTrusted: Bool = MenuBarScanner.isTrusted()
    @Published var isVisible: Bool = false

    private var apps: [LauncherApp] = []
    private var menuCommands: [MenuCommand] = []
    /// App that was frontmost when the panel opened (for Menu Search after we steal focus).
    private var targetApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .combineLatest($mode)
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] query, mode in
                self?.recompute(query: query, mode: mode)
            }
            .store(in: &cancellables)
    }

    /// Snapshot menu commands **before** the panel becomes key / activates,
    /// otherwise AX would read Launcher's own (empty) menu bar.
    func prepareForShow(preferredMode: LauncherMode?) {
        if let preferredMode {
            mode = preferredMode
        }
        query = ""
        selectedIndex = 0
        accessibilityTrusted = MenuBarScanner.isTrusted()

        // Remember the real frontmost app before we become key.
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != "com.dotfiles.launcher" {
            targetApp = front
        }

        if mode == .menu {
            refreshMenuCommands()
        }

        recompute(query: query, mode: mode)

        Task {
            apps = await AppScanner.shared.allApps()
            if mode == .apps {
                recompute(query: query, mode: mode)
            }
        }
    }

    func toggleMode() {
        mode = (mode == .apps) ? .menu : .apps
        query = ""
        selectedIndex = 0
        if mode == .menu {
            refreshMenuCommands()
        }
        recompute(query: query, mode: mode)
    }

    /// Drop stale AX refs when the scanned app quits.
    func handleAppTerminated(_ app: NSRunningApplication?) {
        guard let app else { return }
        let matchesTarget: Bool = {
            if let targetApp {
                return targetApp.processIdentifier == app.processIdentifier
            }
            return false
        }()
        if matchesTarget {
            targetApp = nil
            menuCommands = []
            if mode == .menu {
                results = []
            }
        }
    }

    /// Opens Privacy → Accessibility and polls for a live grant. Does **not**
    /// call the system prompt — after ad-hoc rebuilds Settings can show Launcher
    /// as enabled while TCC still denies the current binary.
    func requestAccessibilityAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if MenuBarScanner.isTrusted(prompt: false) {
                    refreshMenuCommands()
                    recompute(query: query, mode: mode)
                    return
                }
            }
        }
    }

    private func refreshMenuCommands() {
        accessibilityTrusted = MenuBarScanner.isTrusted(prompt: false)
        // Bail if the remembered app is gone.
        if let targetApp, targetApp.isTerminated {
            self.targetApp = nil
            menuCommands = []
            return
        }
        let scanned: [MenuCommand]
        if let targetApp {
            scanned = MenuBarScanner.scan(app: targetApp)
        } else {
            scanned = MenuBarScanner.scanFrontmost()
        }
        // A successful menu-bar read is ground truth if the API flag lags.
        if !scanned.isEmpty {
            accessibilityTrusted = true
        }
        menuCommands = scanned
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = (next % results.count + results.count) % results.count
    }

    func selectIndex(_ index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
    }

    @discardableResult
    func activateSelection() -> Bool {
        guard results.indices.contains(selectedIndex) else { return false }
        return activate(results[selectedIndex])
    }

    @discardableResult
    func activate(_ item: LauncherItem) -> Bool {
        switch item {
        case .app(let app):
            let url = URL(fileURLWithPath: app.path)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    NSLog("[Launcher] Failed to open \(app.path): \(error)")
                }
            }
            return true
        case .menu(let command):
            if let targetApp, targetApp.isTerminated {
                menuCommands = []
                return false
            }
            return MenuBarScanner.perform(command)
        }
    }

    func refreshApps() {
        Task {
            await AppScanner.shared.refresh()
            apps = await AppScanner.shared.allApps()
            if mode == .apps {
                recompute(query: query, mode: mode)
            }
        }
    }

    private func recompute(query: String, mode: LauncherMode) {
        // Leading `:` switches into menu mode (Raycast-style).
        var effectiveQuery = query
        var effectiveMode = mode
        if query.hasPrefix(":") {
            effectiveMode = .menu
            effectiveQuery = String(query.dropFirst())
            if self.mode != .menu {
                self.mode = .menu
                refreshMenuCommands()
            }
        }

        let items: [LauncherItem]
        switch effectiveMode {
        case .apps:
            let ranked = FuzzySearch.ranked(query: effectiveQuery, items: apps, key: \.name)
            items = ranked.map { .app($0) }
        case .menu:
            // Do not re-walk AX on every keystroke — scan only on mode entry / grant.
            let ranked = FuzzySearch.ranked(query: effectiveQuery, items: menuCommands, key: \.path)
            items = ranked.map { .menu($0) }
        }

        results = items
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }
}
