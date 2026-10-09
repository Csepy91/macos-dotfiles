import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Frontmost-app menu bar as a native `NSMenu`, skipping the Apple menu
/// (that lives on the bar's Apple logo button).
@MainActor
final class AppMenuController: NSObject {
    static let shared = AppMenuController()

    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.dotfiles.bar"
    /// Bumped so a slow AX walk cannot pop a stale menu after a newer click.
    private var presentGeneration: UInt64 = 0

    private override init() {
        super.init()
    }

    /// Pops the front app's File / Edit / … menus under `buttonFrameInScreen`.
    /// `preferredBundleID` is used when Bar itself is frontmost after the click.
    func present(relativeTo buttonFrameInScreen: NSRect, preferredBundleID: String?) {
        BarPopoverCoordinator.willPresent()

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            NSLog("[Bar] Accessibility required to open app menu")
            return
        }

        guard let app = resolveTargetApp(preferredBundleID: preferredBundleID) else {
            NSLog("[Bar] No front app for menu")
            return
        }

        presentGeneration &+= 1
        let generation = presentGeneration
        let pid = app.processIdentifier
        let popPoint = NSPoint(x: buttonFrameInScreen.minX, y: buttonFrameInScreen.minY - 2)
        let appName = app.localizedName ?? app.bundleIdentifier ?? "?"

        // Heavy AX walks (Xcode / Chrome) must not hitch the status bar.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let roots = Self.collectTopLevelMenus(pid: pid)
            DispatchQueue.main.async {
                guard let self, generation == self.presentGeneration else { return }
                guard !roots.isEmpty else {
                    NSLog("[Bar] App menu empty (Apple-only or no menus) for \(appName)")
                    return
                }
                let menu = self.makeNSMenu(from: roots)
                menu.popUp(positioning: nil, at: popPoint, in: nil)
            }
        }
    }

    // MARK: - Actions

    @objc
    private func performMenuItem(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AXMenuTarget else { return }
        if let pid = pid(of: target.element),
           let running = NSRunningApplication(processIdentifier: pid),
           !running.isTerminated
        {
            running.activate(options: [.activateIgnoringOtherApps])
        }
        AXUIElementPerformAction(target.element, kAXPressAction as CFString)
    }

    // MARK: - Build (main)

    private func makeNSMenu(from nodes: [MenuNode]) -> NSMenu {
        let menu = NSMenu(title: "App")
        menu.autoenablesItems = false
        for node in nodes {
            menu.addItem(makeItem(from: node))
        }
        return menu
    }

    private func makeItem(from node: MenuNode) -> NSMenuItem {
        if node.isSeparator {
            return .separator()
        }
        let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
        item.isEnabled = node.enabled
        if !node.children.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for child in node.children {
                submenu.addItem(makeItem(from: child))
            }
            item.submenu = submenu
        } else if let element = node.element {
            item.target = self
            item.action = #selector(performMenuItem(_:))
            item.representedObject = AXMenuTarget(element)
        }
        return item
    }

    private func resolveTargetApp(preferredBundleID: String?) -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != ownBundleID,
           !front.isTerminated
        {
            return front
        }
        if let bid = preferredBundleID,
           let match = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == bid && !$0.isTerminated
           })
        {
            return match
        }
        return nil
    }

    // MARK: - AX collect (background)

    private struct MenuNode {
        let title: String
        let enabled: Bool
        let isSeparator: Bool
        /// Leaf AX target; nil for separators / submenu parents.
        let element: AXUIElement?
        let children: [MenuNode]
    }

    nonisolated private static func collectTopLevelMenus(pid: pid_t) -> [MenuNode] {
        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        ) == .success,
            let menuBar = menuBarRef
        else {
            return []
        }

        guard let topItems = children(of: menuBar as! AXUIElement) else { return [] }
        var roots: [MenuNode] = []
        for item in topItems {
            let title = stringAttribute(item, kAXTitleAttribute as CFString)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Apple menu is owned by AppleMenuButton — do not duplicate it here.
            if title == "Apple" || title.isEmpty { continue }

            let enabled = boolAttribute(item, kAXEnabledAttribute as CFString) ?? true
            if let axMenu = menuChild(of: item) {
                roots.append(
                    MenuNode(
                        title: title,
                        enabled: enabled,
                        isSeparator: false,
                        element: nil,
                        children: collectMenu(from: axMenu)
                    )
                )
            } else {
                roots.append(
                    MenuNode(
                        title: title,
                        enabled: enabled,
                        isSeparator: false,
                        element: item,
                        children: []
                    )
                )
            }
        }
        return roots
    }

    nonisolated private static func collectMenu(from axMenu: AXUIElement) -> [MenuNode] {
        guard let items = children(of: axMenu) else { return [] }
        var nodes: [MenuNode] = []
        for element in items {
            let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
            let title = stringAttribute(element, kAXTitleAttribute as CFString)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if title == "-" {
                nodes.append(
                    MenuNode(title: "-", enabled: false, isSeparator: true, element: nil, children: [])
                )
                continue
            }
            guard role == (kAXMenuItemRole as String), !title.isEmpty else { continue }

            let enabled = boolAttribute(element, kAXEnabledAttribute as CFString) ?? true
            if let submenu = menuChild(of: element) {
                nodes.append(
                    MenuNode(
                        title: title,
                        enabled: enabled,
                        isSeparator: false,
                        element: nil,
                        children: collectMenu(from: submenu)
                    )
                )
            } else {
                nodes.append(
                    MenuNode(
                        title: title,
                        enabled: enabled,
                        isSeparator: false,
                        element: element,
                        children: []
                    )
                )
            }
        }
        return nodes
    }

    nonisolated private static func menuChild(of element: AXUIElement) -> AXUIElement? {
        guard let kids = children(of: element) else { return nil }
        return kids.first {
            stringAttribute($0, kAXRoleAttribute as CFString) == (kAXMenuRole as String)
        }
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &ref
        ) == .success else { return nil }
        return ref as? [AXUIElement]
    }

    nonisolated private static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return ref as? String
    }

    nonisolated private static func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return (ref as? Bool) ?? (ref as? NSNumber)?.boolValue
    }

    private func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }
}

/// Retains an AX element for `NSMenuItem.representedObject`.
private final class AXMenuTarget: NSObject {
    let element: AXUIElement
    init(_ element: AXUIElement) {
        self.element = element
    }
}
