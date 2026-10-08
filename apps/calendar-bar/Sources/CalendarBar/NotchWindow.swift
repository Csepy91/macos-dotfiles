import AppKit
import SwiftUI

/// Floating NSPanel anchored under a caller-provided rect (e.g. the Bar clock),
/// falling back to centered beneath the notch when no anchor is set.
final class NotchWindow: NSPanel {
    private var config: CalendarConfig
    private var blurView: NSVisualEffectView?
    private(set) var hostingView: NSHostingView<CalendarView>?
    /// AppKit screen rect of the control that opened the panel (e.g. clock).
    var anchorRect: NSRect?
    /// Bumps on each show/hide so overlapping animation completions are ignored.
    private var animationGeneration: UInt64 = 0

    init(config: CalendarConfig, rootView: CalendarView) {
        self.config = config
        let size = NSSize(
            width: config.dimensions.width,
            height: min(320, config.dimensions.maxHeight)
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hostingView = hosting

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.autoresizingMask = [.width, .height]
        applyChrome(to: effect)
        container.addSubview(effect)
        blurView = effect

        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        contentView = container
        reposition(animated: false)
    }

    func setRootView(_ rootView: CalendarView) {
        hostingView?.rootView = rootView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func apply(config: CalendarConfig) {
        self.config = config
        if let blurView {
            applyChrome(to: blurView)
        }
        reposition(animated: false)
    }

    func showAnimated(focus: @escaping () -> Void) {
        animationGeneration &+= 1
        let generation = animationGeneration
        reposition(animated: false)
        alphaValue = 0
        let target = frame
        setFrame(target.offsetBy(dx: 0, dy: 12), display: true)
        orderFrontRegardless()
        makeKey()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            focus()
        })
    }

    func hideAnimated(completion: (() -> Void)? = nil) {
        animationGeneration &+= 1
        let generation = animationGeneration
        let target = frame.offsetBy(dx: 0, dy: 10)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.orderOut(nil)
            completion?()
        })
    }

    func updateHeight(_ contentHeight: CGFloat) {
        let width = config.dimensions.width
        let height = min(max(contentHeight, 120), config.dimensions.maxHeight)
        let rect = placement(width: width, height: height)
        setFrame(rect, display: true)
    }

    func reposition(animated: Bool) {
        let width = config.dimensions.width
        let height = frame.height > 0 ? frame.height : 320
        let rect = placement(width: width, height: height)
        if animated {
            animator().setFrame(rect, display: true)
        } else {
            setFrame(rect, display: true)
        }
    }

    // MARK: - Layout helpers

    private func placement(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = anchorScreen()
        let gap: CGFloat = 4

        if let anchor = anchorRect, anchor.width > 0, anchor.height > 0 {
            // Drop below the clock; trailing-align so the panel hangs under the right edge.
            var x = anchor.maxX - width
            var y = anchor.minY - gap - height

            let margin: CGFloat = 8
            let minX = screen.visibleFrame.minX + margin
            let maxX = screen.visibleFrame.maxX - width - margin
            x = min(max(x, minX), max(minX, maxX))

            let minY = screen.visibleFrame.minY + margin
            if y < minY { y = minY }

            return NSRect(x: x, y: y, width: width, height: height)
        }

        // Fallback: centered under the notch / menu-bar strip.
        let topY = notchBottomY(on: screen)
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: topY - height,
            width: width,
            height: height
        )
    }

    private func anchorScreen() -> NSScreen {
        if let anchor = anchorRect,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    /// Y coordinate of the bottom edge of the notch / menu-bar strip (AppKit coords).
    private func notchBottomY(on screen: NSScreen) -> CGFloat {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let menuBarHeight = max(frame.maxY - visible.maxY, 0)

        let notchInset: CGFloat
        if #available(macOS 12.0, *) {
            notchInset = screen.safeAreaInsets.top
        } else {
            notchInset = 0
        }

        let strip = max(menuBarHeight, notchInset, 32)
        return frame.maxY - strip - 6
    }

    private func applyChrome(to effect: NSVisualEffectView) {
        let radius = config.theme.cornerRadius
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true

        let tint = NSColor(
            hex: config.theme.backgroundColor,
            alpha: CGFloat(config.theme.backgroundOpacity)
        )
        if effect.subviews.first(where: { $0.identifier?.rawValue == "tint" }) == nil {
            let tintView = NSView(frame: effect.bounds)
            tintView.identifier = NSUserInterfaceItemIdentifier("tint")
            tintView.wantsLayer = true
            tintView.autoresizingMask = [.width, .height]
            tintView.layer?.backgroundColor = tint.cgColor
            effect.addSubview(tintView, positioned: .below, relativeTo: nil)
        } else if let tintView = effect.subviews.first(where: { $0.identifier?.rawValue == "tint" }) {
            tintView.layer?.backgroundColor = tint.cgColor
        }

        effect.layer?.borderWidth = config.theme.borderWidth
        effect.layer?.borderColor = NSColor(hex: config.theme.borderColor).cgColor
    }
}

/// Observes resign-key to optionally hide when focus leaves the panel.
final class NotchWindowDelegate: NSObject, NSWindowDelegate {
    var onResignKey: (() -> Void)?
    var onBecomeKey: (() -> Void)?

    func windowDidResignKey(_ notification: Notification) {
        onResignKey?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onBecomeKey?()
    }
}
