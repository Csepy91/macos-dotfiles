import AppKit
import Combine
import Foundation
import SwiftUI

enum LauncherMode: String {
    case apps = "Apps"
    case menu = "Menu"
    case clipboard = "Clipboard"
}

enum LauncherItem: Identifiable, Hashable {
    case app(LauncherApp)
    case menu(MenuCommand)
    case clipboard(ClipboardEntry)

    var id: String {
        switch self {
        case .app(let app): return "app:\(app.id)"
        case .menu(let cmd): return "menu:\(cmd.id)"
        case .clipboard(let entry): return "clip:\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .app(let app): return app.name
        case .menu(let cmd): return cmd.displayTitle
        case .clipboard(let entry): return entry.displayTitle
        }
    }

    var subtitle: String {
        switch self {
        case .app(let app): return app.path
        case .menu: return ""
        case .clipboard(let entry):
            switch entry.kind {
            case .text: return RelativeTime.string(from: entry.createdAt)
            case .image: return "Image · \(RelativeTime.string(from: entry.createdAt))"
            }
        }
    }

    var searchKey: String {
        switch self {
        case .app(let app): return app.name
        case .menu(let cmd): return cmd.path
        case .clipboard(let entry): return entry.searchKey
        }
    }
}

enum RelativeTime {
    static func string(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
    /// App that was frontmost when the panel opened (for Menu Search / paste after we steal focus).
    private var targetApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private let clipboardStore = ClipboardHistoryStore.shared
    private var accessibilityPollTask: Task<Void, Never>?
    private var appsRefreshTask: Task<Void, Never>?

    init() {
        $query
            .combineLatest($mode)
            .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
            .sink { [weak self] query, mode in
                self?.recompute(query: query, mode: mode)
            }
            .store(in: &cancellables)

        clipboardStore.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .clipboard else { return }
                self.recompute(query: self.query, mode: .clipboard)
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
        } else {
            menuCommands = []
        }

        recompute(query: query, mode: mode)

        appsRefreshTask?.cancel()
        appsRefreshTask = Task { [weak self] in
            let apps = await AppScanner.shared.allApps()
            guard let self, !Task.isCancelled else { return }
            self.apps = apps
            if self.mode == .apps {
                self.recompute(query: self.query, mode: self.mode)
            }
        }
    }

    func toggleMode() {
        switch mode {
        case .apps: mode = .menu
        case .menu: mode = .clipboard
        case .clipboard: mode = .apps
        }
        query = ""
        selectedIndex = 0
        if mode == .menu {
            refreshMenuCommands()
        } else {
            menuCommands = []
        }
        recompute(query: query, mode: mode)
    }

    /// Drop retained AX menu elements when the panel hides.
    func clearMenuCommands() {
        menuCommands = []
    }

    func cancelPendingWork() {
        accessibilityPollTask?.cancel()
        accessibilityPollTask = nil
        appsRefreshTask?.cancel()
        appsRefreshTask = nil
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
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, !Task.isCancelled else { return }
                if MenuBarScanner.isTrusted(prompt: false) {
                    self.refreshMenuCommands()
                    self.recompute(query: self.query, mode: self.mode)
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

    /// Clipboard mode: copy selected entry then paste into the previously focused app.
    @discardableResult
    func pasteSelection() -> Bool {
        guard mode == .clipboard else { return activateSelection() }
        guard results.indices.contains(selectedIndex),
              case .clipboard(let entry) = results[selectedIndex]
        else { return false }
        guard clipboardStore.copyToPasteboard(entry) else { return false }
        return pasteIntoTargetApp()
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
        case .clipboard(let entry):
            return clipboardStore.copyToPasteboard(entry)
        }
    }

    func refreshApps() {
        appsRefreshTask?.cancel()
        appsRefreshTask = Task { [weak self] in
            await AppScanner.shared.refresh()
            let apps = await AppScanner.shared.allApps()
            guard let self, !Task.isCancelled else { return }
            self.apps = apps
            if self.mode == .apps {
                self.recompute(query: self.query, mode: self.mode)
            }
        }
    }

    private func pasteIntoTargetApp() -> Bool {
        guard let app = targetApp, !app.isTerminated else {
            // No target — clipboard was still updated.
            return true
        }
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        guard activated else { return true }

        // Delay so the target becomes key before Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.postCommandV()
        }
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 9 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func recompute(query: String, mode: LauncherMode) {
        // Leading `:` → Menu; leading `;` → Clipboard (Raycast-style).
        var effectiveQuery = query
        var effectiveMode = mode
        if query.hasPrefix(":") {
            effectiveMode = .menu
            effectiveQuery = String(query.dropFirst())
            if self.mode != .menu {
                self.mode = .menu
                refreshMenuCommands()
            }
        } else if query.hasPrefix(";") {
            effectiveMode = .clipboard
            effectiveQuery = String(query.dropFirst())
            if self.mode != .clipboard {
                self.mode = .clipboard
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
        case .clipboard:
            let ranked = FuzzySearch.ranked(
                query: effectiveQuery,
                items: clipboardStore.entries,
                key: \.searchKey
            )
            items = ranked.map { .clipboard($0) }
        }

        results = items
        if selectedIndex >= results.count {
            selectedIndex = max(0, results.count - 1)
        }
    }
}
