import AppKit
import SwiftUI

/// Full-width status bar pinned to the top edge of the primary display,
/// spanning left → notch → right.
final class TopBarWindow: NSPanel {
    private var config: BarConfig
    private var blurView: NSVisualEffectView?
    private(set) var hostingView: NSHostingView<WorkspaceBarView>?

    init(config: BarConfig, rootView: WorkspaceBarView) {
        self.config = config
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(
            width: screen.frame.width,
            height: config.dimensions.height
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true

        // Non-vibrant hosting: NSVisualEffectView vibrancy otherwise eats SwiftUI text.
        let hosting = NonVibrantHostingView(rootView: rootView)
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

    func setRootView(_ rootView: WorkspaceBarView) {
        hostingView?.rootView = rootView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(config: BarConfig) {
        self.config = config
        if let blurView {
            applyChrome(to: blurView)
        }
        reposition(animated: false)
    }

    func showBar() {
        setHiddenForFullscreen(false)
    }

    /// Instant hide/show for native macOS fullscreen Spaces.
    ///
    /// Stay ordered in while hidden (`ignoresMouseEvents`) so reveal does not
    /// `orderFront` under the cursor and accidentally activate the leftmost
    /// workspace pill.
    func setHiddenForFullscreen(_ hidden: Bool) {
        if hidden {
            BarPopoverCoordinator.dismissAll()
            alphaValue = 0
            ignoresMouseEvents = true
            return
        }
        reposition(animated: false)
        alphaValue = 1
        ignoresMouseEvents = false
        orderFrontRegardless()
    }

    func reposition(animated: Bool) {
        let screen = anchorScreen()
        let height = max(CGFloat(config.dimensions.height), 24)
        let margin = CGFloat(config.dimensions.marginTop)
        // Edge-to-edge: full display width, flush to the top (through the notch).
        let rect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - height - margin,
            width: screen.frame.width,
            height: height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(rect, display: true)
            }
        } else {
            setFrame(rect, display: true)
        }
    }

    // MARK: - Layout helpers

    private func anchorScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
    }

    private func applyChrome(to effect: NSVisualEffectView) {
        // Full-bleed strip: no rounded outer corners (pills handle their own radius).
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 0
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

        // No outer chrome border — full-bleed strip. Remove any leftover hairline.
        effect.layer?.borderWidth = 0
        effect.subviews
            .filter { $0.identifier?.rawValue == "bottom-border" }
            .forEach { $0.removeFromSuperview() }
    }
}

/// Prevents AppKit vibrancy from washing out SwiftUI text over the blur material.
private final class NonVibrantHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}
