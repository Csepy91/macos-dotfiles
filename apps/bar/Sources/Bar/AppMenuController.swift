import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Frontmost-app menu bar as a native `NSMenu`, skipping the Apple menu
/// (that lives on the bar's Apple logo button).
@MainActor
final class AppMenuController: NSObject {
    static let shared = AppMenuController()

    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.dotfiles.bar"

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

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        ) == .success,
            let menuBar = menuBarRef
        else {
            NSLog("[Bar] App menu bar unavailable for \(app.localizedName ?? app.bundleIdentifier ?? "?")")
            return
        }

        let menu = NSMenu(title: "App")
        menu.autoenablesItems = false

        guard let topItems = children(of: menuBar as! AXUIElement) else { return }
        for item in topItems {
            let title = stringAttribute(item, kAXTitleAttribute as CFString)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Apple menu is owned by AppleMenuButton — do not duplicate it here.
            if title == "Apple" || title.isEmpty { continue }

            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menuItem.isEnabled = boolAttribute(item, kAXEnabledAttribute as CFString) ?? true
            if let axMenu = menuChild(of: item) {
                menuItem.submenu = buildMenu(from: axMenu, owningApp: app)
            }
            menu.addItem(menuItem)
        }

        guard !menu.items.isEmpty else {
            NSLog("[Bar] App menu empty (Apple-only or no menus)")
            return
        }

        // `in: nil` → `at` is in screen coordinates (bottom-left of the button).
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: buttonFrameInScreen.minX, y: buttonFrameInScreen.minY - 2),
            in: nil
        )
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

    // MARK: - Build

    private func buildMenu(from axMenu: AXUIElement, owningApp: NSRunningApplication) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let items = children(of: axMenu) else { return menu }

        for element in items {
            let role = stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
            let title = stringAttribute(element, kAXTitleAttribute as CFString)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if title == "-" {
                menu.addItem(.separator())
                continue
            }
            guard role == (kAXMenuItemRole as String), !title.isEmpty else { continue }

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = boolAttribute(element, kAXEnabledAttribute as CFString) ?? true

            if let submenu = menuChild(of: element) {
                item.submenu = buildMenu(from: submenu, owningApp: owningApp)
            } else {
                item.target = self
                item.action = #selector(performMenuItem(_:))
                item.representedObject = AXMenuTarget(element)
            }
            menu.addItem(item)
        }
        return menu
    }

    private func menuChild(of element: AXUIElement) -> AXUIElement? {
        guard let kids = children(of: element) else { return nil }
        return kids.first {
            stringAttribute($0, kAXRoleAttribute as CFString) == (kAXMenuRole as String)
        }
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

    // MARK: - AX helpers

    private func children(of element: AXUIElement) -> [AXUIElement]? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &ref
        ) == .success else { return nil }
        return ref as? [AXUIElement]
    }

    private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else { return nil }
        return ref as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool? {
        var ref: AnyObject?
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
