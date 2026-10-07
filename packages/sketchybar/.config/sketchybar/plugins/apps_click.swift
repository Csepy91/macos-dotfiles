import AppKit
import ApplicationServices
import Foundation

/// Opens OmniWM Controls under the SketchyBar cog with no left-edge flash.
/// Strategy:
/// 1. Cover the left spawn strip with a wallpaper-matched window (and pump so it paints)
/// 2. Click extras; on first AX sighting, park Controls off-screen
/// 3. Pin under the cog while still covered, then drop the cover

private let omniBundleID = "com.barut.OmniWM"

private func axClick(_ element: AXUIElement) {
  AXUIElementPerformAction(element, kAXCancelAction as CFString)
  usleep(30_000)
  AXUIElementPerformAction(element, kAXPressAction as CFString)
}

private func omniAppElement() -> AXUIElement? {
  guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == omniBundleID
  }) else {
    return nil
  }
  return AXUIElementCreateApplication(app.processIdentifier)
}

private func omniExtrasItem(_ ax: AXUIElement) -> AXUIElement? {
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

private func axSize(_ element: AXUIElement) -> CGSize {
  var sizeRef: AnyObject?
  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
  var size = CGSize.zero
  if let sv = sizeRef {
    AXValueGetValue(sv as! AXValue, .cgSize, &size)
  }
  return size
}

private func axPosition(_ element: AXUIElement) -> CGPoint {
  var posRef: AnyObject?
  AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
  var pos = CGPoint.zero
  if let pv = posRef {
    AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
  }
  return pos
}

private func setAXPosition(_ element: AXUIElement, _ point: CGPoint) {
  var p = point
  if let val = AXValueCreate(.cgPoint, &p) {
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, val)
  }
}

private func findControlsPanel(_ ax: AXUIElement) -> AXUIElement? {
  var wins: AnyObject?
  guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wins) == .success,
        let windows = wins as? [AXUIElement]
  else {
    return nil
  }
  for w in windows {
    var title: AnyObject?
    AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title)
    if (title as? String) == "OmniWM Controls" {
      return w
    }
  }
  return nil
}

private func sketchyAppsRect() -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? {
  let task = Process()
  task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")
  task.arguments = ["--query", "apps"]
  let out = Pipe()
  task.standardOutput = out
  task.standardError = Pipe()
  do {
    try task.run()
    task.waitUntilExit()
  } catch {
    return nil
  }
  let data = out.fileHandleForReading.readDataToEndOfFile()
  guard
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    let rects = json["bounding_rects"] as? [String: Any],
    let display = rects["display-1"] as? [String: Any],
    let origin = display["origin"] as? [Double],
    let size = display["size"] as? [Double],
    origin.count >= 2,
    size.count >= 2
  else {
    return nil
  }
  return (CGFloat(origin[0]), CGFloat(origin[1]), CGFloat(size[0]), CGFloat(size[1]))
}

private func targetUnderCog(
  _ panel: AXUIElement,
  cog: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
) -> CGPoint {
  let panelSize = axSize(panel)
  var newPos = CGPoint(
    x: cog.x + cog.w - panelSize.width,
    y: cog.y + cog.h
  )
  if newPos.x < 8 {
    newPos.x = max(8, cog.x)
  }
  return newPos
}

private func pinControlsUnderCog(
  _ panel: AXUIElement,
  cog: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)
) {
  setAXPosition(panel, targetUnderCog(panel, cog: cog))
}

private func pumpRunLoop(_ seconds: CFTimeInterval) {
  let until = Date(timeIntervalSinceNow: seconds)
  while Date() < until {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
  }
}

/// Cover over OmniWM's default left spawn strip, matching the desktop wallpaper.
private final class SpawnCover {
  private let window: NSWindow

  init(screen: NSScreen) {
    let frame = screen.frame
    // Controls ~280 wide + open animation padding.
    let coverWidth: CGFloat = 520
    let coverRect = NSRect(x: frame.minX, y: frame.minY, width: coverWidth, height: frame.height)

    window = NSWindow(
      contentRect: coverRect,
      styleMask: .borderless,
      backing: .buffered,
      defer: false,
      screen: screen
    )
    window.isOpaque = true
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.animationBehavior = .none

    let wallpaperPath = NSHomeDirectory() + "/.config/wallpaper/default.png"
    if let wall = NSImage(contentsOfFile: wallpaperPath) {
      let view = NSImageView(frame: NSRect(origin: .zero, size: coverRect.size))
      view.image = wall
      // Crop/scale like the desktop: fill the strip from the left of the image.
      view.imageScaling = .scaleProportionallyUpOrDown
      view.imageAlignment = .alignTopLeft
      window.contentView = view
      // Sample a dark pixel fallback under the image while it loads.
      window.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0)
    } else {
      window.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0)
    }

    window.orderFrontRegardless()
    window.displayIfNeeded()
  }

  func close() {
    window.orderOut(nil)
  }
}

@discardableResult
private func openOmniMenu() -> Bool {
  let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(opts)

  if NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == omniBundleID }) == nil {
    NSWorkspace.shared.openApplication(
      at: URL(fileURLWithPath: "/Applications/OmniWM.app"),
      configuration: NSWorkspace.OpenConfiguration()
    ) { _, _ in }
    usleep(400_000)
  }

  guard let ax = omniAppElement(), let item = omniExtrasItem(ax) else {
    return false
  }

  if findControlsPanel(ax) != nil {
    axClick(item)
    usleep(100_000)
    if findControlsPanel(ax) != nil {
      axClick(item)
      usleep(100_000)
    }
  }

  let cog = sketchyAppsRect() ?? (x: 1600, y: 0, w: 32, h: 38)
  let screen = NSScreen.main ?? NSScreen.screens[0]

  // Already on the main thread — never DispatchQueue.main.sync here.
  let cover = SpawnCover(screen: screen)
  pumpRunLoop(0.08)

  let done = DispatchSemaphore(value: 0)
  var success = false

  DispatchQueue.global(qos: .userInitiated).async {
    let deadline = Date().addingTimeInterval(0.85)
    var parked = false
    while Date() < deadline {
      if let panel = findControlsPanel(ax) {
        if !parked {
          setAXPosition(panel, CGPoint(x: -8000, y: -8000))
          parked = true
        }
        let target = targetUnderCog(panel, cog: cog)
        let hold = Date().addingTimeInterval(0.16)
        while Date() < hold {
          setAXPosition(panel, target)
          usleep(1_500)
        }
        setAXPosition(panel, target)
        let pos = axPosition(panel)
        if pos.x > 200 {
          success = true
          break
        }
      }
      usleep(800)
    }
    done.signal()
  }

  axClick(item)
  _ = done.wait(timeout: .now() + 1.0)

  if let panel = findControlsPanel(ax) {
    pinControlsUnderCog(panel, cog: cog)
  }
  pumpRunLoop(0.05)
  cover.close()
  pumpRunLoop(0.02)

  if let panel = findControlsPanel(ax) {
    pinControlsUnderCog(panel, cog: cog)
  }

  return success
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

if !openOmniMenu() {
  fputs("Failed to open OmniWM Controls under cog\n", stderr)
  exit(1)
}
