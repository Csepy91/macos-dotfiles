import AppKit
import SwiftUI

/// Floating NSPanel anchored directly beneath the primary display notch.
final class NotchWindow: NSPanel {
    private var config: CalendarConfig
    private var blurView: NSVisualEffectView?
    private(set) var hostingView: NSHostingView<CalendarView>?

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
        }, completionHandler: {
            focus()
        })
    }

    func hideAnimated(completion: (() -> Void)? = nil) {
        let target = frame.offsetBy(dx: 0, dy: 10)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }

    func updateHeight(_ contentHeight: CGFloat) {
        let width = config.dimensions.width
        let height = min(max(contentHeight, 120), config.dimensions.maxHeight)
        var newFrame = frame
        let screen = anchorScreen()
        let topY = notchBottomY(on: screen)
        newFrame.size = NSSize(width: width, height: height)
        newFrame.origin.x = screen.frame.midX - width / 2
        newFrame.origin.y = topY - height
        setFrame(newFrame, display: true)
    }

    func reposition(animated: Bool) {
        let screen = anchorScreen()
        let width = config.dimensions.width
        let height = frame.height > 0 ? frame.height : 320
        let topY = notchBottomY(on: screen)
        let origin = NSPoint(x: screen.frame.midX - width / 2, y: topY - height)
        let rect = NSRect(origin: origin, size: NSSize(width: width, height: height))
        if animated {
            animator().setFrame(rect, display: true)
        } else {
            setFrame(rect, display: true)
        }
    }

    // MARK: - Layout helpers

    private func anchorScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
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
        // Sit a few points below the strip so the panel clears the notch.
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
