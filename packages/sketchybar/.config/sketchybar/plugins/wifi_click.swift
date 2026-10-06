import AppKit
import ApplicationServices
import CoreGraphics

/// Opens the native Control Center Wi-Fi menu (same popup as the macOS menu bar).
/// Adapted from FelixKratz/dotfiles sketchybar menus helper.

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32
@_silgen_name("SLSSetMenuBarVisibilityOverrideOnDisplay")
func SLSSetMenuBarVisibilityOverrideOnDisplay(_ cid: Int32, _ did: Int32, _ enabled: Bool)
@_silgen_name("SLSSetMenuBarInsetAndAlpha")
func SLSSetMenuBarInsetAndAlpha(_ cid: Int32, _ u1: Double, _ u2: Double, _ alpha: Float)

private func axClick(_ element: AXUIElement) {
  AXUIElementPerformAction(element, kAXCancelAction as CFString)
  usleep(150_000)
  AXUIElementPerformAction(element, kAXPressAction as CFString)
}

private func findExtrasItem(alias: String) -> AXUIElement? {
  guard let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
    return nil
  }

  var targetPID: pid_t = 0
  var targetBounds = CGRect.null

  for window in windowList {
    guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0x19,
          let owner = window[kCGWindowOwnerName as String] as? String,
          let name = window[kCGWindowName as String] as? String,
          let pidNum = window[kCGWindowOwnerPID as String] as? NSNumber,
          let boundsDict = window[kCGWindowBounds as String] as? NSDictionary
    else { continue }

    let key = "\(owner),\(name)"
    guard key == alias else { continue }
    targetPID = pid_t(truncating: pidNum)
    guard let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
    targetBounds = rect
    break
  }

  guard targetPID != 0 else { return nil }

  let app = AXUIElementCreateApplication(targetPID)
  var extras: AnyObject?
  guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &extras) == .success,
        let extrasEl = extras
  else { return nil }

  var children: AnyObject?
  guard AXUIElementCopyAttributeValue(extrasEl as! AXUIElement, kAXVisibleChildrenAttribute as CFString, &children) == .success,
        let items = children as? [AXUIElement]
  else { return nil }

  for item in items {
    var positionRef: AnyObject?
    var sizeRef: AnyObject?
    AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionRef)
    AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeRef)
    guard let posVal = positionRef, let sizeVal = sizeRef else { continue }

    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)

    if abs(position.x - targetBounds.origin.x) <= 10 {
      return item
    }
  }
  return nil
}

private func pressByDescription(containing needles: [String]) -> Bool {
  let apps = NSWorkspace.shared.runningApplications
  guard let cc = apps.first(where: { $0.bundleIdentifier == "com.apple.controlcenter" }) else {
    return false
  }
  let app = AXUIElementCreateApplication(cc.processIdentifier)

  for attr in [kAXExtrasMenuBarAttribute as CFString, kAXMenuBarAttribute as CFString] {
    var menubar: AnyObject?
    guard AXUIElementCopyAttributeValue(app, attr, &menubar) == .success, let mb = menubar else {
      continue
    }
    var children: AnyObject?
    guard AXUIElementCopyAttributeValue(mb as! AXUIElement, kAXVisibleChildrenAttribute as CFString, &children) == .success,
          let items = children as? [AXUIElement]
    else { continue }

    for item in items {
      var desc: AnyObject?
      AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &desc)
      let text = (desc as? String) ?? ""
      if needles.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
        axClick(item)
        return true
      }
    }
  }
  return false
}

private func openWifiMenu() -> Bool {
  // Prompt for Accessibility if needed (same idea as Felix menus helper).
  let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(opts)

  let aliases = ["Control Center,WiFi", "Control Center,Wi-Fi", "Control Centre,WiFi"]
  let cid = SLSMainConnectionID()

  for alias in aliases {
    guard let item = findExtrasItem(alias: alias) else { continue }
    SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 0.0)
    SLSSetMenuBarVisibilityOverrideOnDisplay(cid, 0, true)
    SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 0.0)
    axClick(item)
    SLSSetMenuBarVisibilityOverrideOnDisplay(cid, 0, false)
    SLSSetMenuBarInsetAndAlpha(cid, 0, 1, 1.0)
    return true
  }

  if pressByDescription(containing: ["Wi-Fi", "WiFi", "Wifi"]) {
    return true
  }
  return false
}

if !openWifiMenu() {
  // Fallback: System Settings → Wi-Fi
  if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
    NSWorkspace.shared.open(url)
  }
}
