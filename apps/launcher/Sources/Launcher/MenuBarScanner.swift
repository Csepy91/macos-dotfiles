import AppKit
import ApplicationServices
import Foundation

struct MenuCommand: Identifiable, Hashable {
    let id: String
    /// Leaf menu item title (e.g. "New Text File").
    let title: String
    /// Top-level menu (e.g. "File").
    let rootMenu: String
    /// Intermediate path between root and title (e.g. "Open Recent"), if any.
    let nest: String
    /// Full "File › … › Title" path — used for search ranking.
    let path: String
    let element: AXUIElement

    /// Single-line label under the section header.
    var displayTitle: String {
        nest.isEmpty ? title : "\(nest) › \(title)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuCommand, rhs: MenuCommand) -> Bool {
        lhs.id == rhs.id
    }
}

/// Recursively walks the frontmost app's menu bar via Accessibility APIs.
enum MenuBarScanner {
    /// Live TCC check. Prefer `WithOptions(nil)` over `AXIsProcessTrusted()` —
    /// the latter can cache a stale deny across System Settings toggles.
    /// Never pass `prompt: true` automatically; ghost Accessibility rows make
    /// the system dialog lie after ad-hoc re-signs.
    static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opts)
        }
        return AXIsProcessTrustedWithOptions(nil)
    }

    static func scanFrontmost() -> [MenuCommand] {
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        return scan(app: app)
    }

    static func scan(app: NSRunningApplication) -> [MenuCommand] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            axApp,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        )
        guard status == .success, let menuBar = menuBarRef else { return [] }

        var commands: [MenuCommand] = []
        collect(
            element: menuBar as! AXUIElement,
            path: [],
            into: &commands,
            appName: app.localizedName ?? app.bundleIdentifier ?? "App"
        )
        return commands
    }

    static func perform(_ command: MenuCommand) {
        // Refuse stale elements whose owning process is gone.
        guard let pid = pid(of: command.element),
              let running = NSRunningApplication(processIdentifier: pid),
              !running.isTerminated
        else {
            NSLog("[Launcher] Menu command target app is gone — skipping press")
            return
        }
        running.activate(options: [.activateIgnoringOtherApps])
        AXUIElementPerformAction(command.element, kAXPressAction as CFString)
    }

    // MARK: - Private

    private static func collect(
        element: AXUIElement,
        path: [String],
        into commands: inout [MenuCommand],
        appName: String
    ) {
        let title = stringAttribute(element, kAXTitleAttribute as CFString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip the Apple menu entirely — system items are noisy in a palette.
        if title == "Apple" {
            return
        }

        var nextPath = path
        if let title, !title.isEmpty {
            nextPath = path + [title]
        }

        let role = stringAttribute(element, kAXRoleAttribute as CFString)
        let enabled = boolAttribute(element, kAXEnabledAttribute as CFString) ?? true

        if role == (kAXMenuItemRole as String),
           enabled,
           let title,
           !title.isEmpty,
           title != "-",
           nextPath.count >= 2
        {
            let rootMenu = nextPath[0]
            let nest = nextPath.dropFirst().dropLast().joined(separator: " › ")
            let fullPath = nextPath.joined(separator: " › ")
            commands.append(
                MenuCommand(
                    id: "\(appName)::\(fullPath)",
                    title: title,
                    rootMenu: rootMenu,
                    nest: nest,
                    path: fullPath,
                    element: element
                )
            )
        }

        guard let children = children(of: element) else { return }
        for child in children {
            collect(element: child, path: nextPath, into: &commands, appName: appName)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var ref: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &ref
        )
        guard status == .success, let list = ref as? [AXUIElement] else { return nil }
        return list
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return (ref as? Bool) ?? (ref as? NSNumber)?.boolValue
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let status = AXUIElementGetPid(element, &pid)
        return status == .success ? pid : nil
    }
}
