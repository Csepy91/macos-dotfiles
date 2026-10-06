import AppKit
import ApplicationServices
import CoreGraphics

/// Opens OmniWM's native status-item dropdown (extras menu bar).
/// SketchyBar sits on top of that icon, so we AX-press it via SkyLight briefly.

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32
@_silgen_name("SLSSetMenuBarVisibilityOverrideOnDisplay")
func SLSSetMenuBarVisibilityOverrideOnDisplay(_ cid: Int32, _ did: Int32, _ enabled: Bool)
@_silgen_name("SLSSetMenuBarInsetAndAlpha")
func SLSSetMenuBarInsetAndAlpha(_ cid: Int32, _ u1: Double, _ u2: Double, _ alpha: Float)

private let omniBundleID = "com.barut.OmniWM"

private func axClick(_ element: AXUIElement) {
  AXUIElementPerformAction(element, kAXCancelAction as CFString)
  usleep(80_000)
  AXUIElementPerformAction(element, kAXPressAction as CFString)
}

private func omniExtrasItem() -> AXUIElement? {
  guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == omniBundleID
  }) else {
    return nil
  }
  let ax = AXUIElementCreateApplication(app.processIdentifier)
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

@discardableResult
private func openOmniMenu() -> Bool {
  let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(opts)

  // Ensure OmniWM is running so its status item exists.
  if NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == omniBundleID }) == nil {
    NSWorkspace.shared.openApplication(
      at: URL(fileURLWithPath: "/Applications/OmniWM.app"),
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, _ in }
    usleep(400_000)
  }

  guard let item = omniExtrasItem() else {
    return false
  }

  let cid = SLSMainConnectionID()
  SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 0.0)
  SLSSetMenuBarVisibilityOverrideOnDisplay(cid, 0, true)
  SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 0.0)
  usleep(100_000)
  axClick(item)
  SLSSetMenuBarVisibilityOverrideOnDisplay(cid, 0, false)
  SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 1.0)
  return true
}

if !openOmniMenu() {
  fputs("Failed to open OmniWM status menu\n", stderr)
  exit(1)
}
