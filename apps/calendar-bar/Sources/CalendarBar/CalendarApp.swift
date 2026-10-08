import AppKit
import Combine
import SwiftUI

@main
enum CalendarBarMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let flags = CLIFlags.parse(args)

        // Always prefer talking to an existing daemon (CLI actions + bare launch).
        if IPCServer.isDaemonRunning() {
            if flags.wantsRemoteAction {
                _ = IPCServer.send(flags.ipcCommand)
            }
            // Bare second launch: stay single-instance, do nothing.
            return
        }

        let app = NSApplication.shared
        // When becoming the daemon after a CLI action with no prior instance,
        // apply that action once launch finishes. Bare LaunchAgent start stays hidden.
        let initial: IPCCommand? = flags.wantsRemoteAction ? flags.ipcCommand : nil
        let delegate = AppDelegate(initialCommand: initial)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct CLIFlags {
    var toggle = false
    var show = false
    var hide = false
    var reload = false
    /// Optional AppKit screen rect `x,y,w,h` (e.g. from Bar clock).
    var anchor: CGRect?

    var wantsRemoteAction: Bool {
        toggle || show || hide || reload
    }

    var ipcCommand: IPCCommand {
        if hide { return .hide }
        if reload { return .reload }
        if show { return .show(anchor: anchor) }
        return .toggle(anchor: anchor)
    }

    static func parse(_ args: [String]) -> CLIFlags {
        var flags = CLIFlags()
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--toggle", "-t": flags.toggle = true
            case "--show": flags.show = true
            case "--hide": flags.hide = true
            case "--reload", "-r": flags.reload = true
            case "--anchor":
                if i + 1 < args.count {
                    flags.anchor = parseAnchor(args[i + 1])
                    i += 1
                }
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                if arg.hasPrefix("--anchor=") {
                    flags.anchor = parseAnchor(String(arg.dropFirst("--anchor=".count)))
                }
            }
            i += 1
        }
        return flags
    }

    private static func parseAnchor(_ raw: String) -> CGRect? {
        let bits = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard bits.count == 4,
              let x = Double(bits[0]),
              let y = Double(bits[1]),
              let w = Double(bits[2]),
              let h = Double(bits[3])
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func printHelp() {
        let help = """
        CalendarBar — calendar & agenda popover

        Usage:
          calendar-bar                 Start the background agent
          calendar-bar --toggle        Toggle the panel (skhd / Bar clock)
          calendar-bar --toggle --anchor x,y,w,h
                                       Toggle anchored under a screen rect
          calendar-bar --show          Show the panel
          calendar-bar --hide          Hide the panel
          calendar-bar --reload        Reload ~/.config/calendar/config.json
          calendar-bar --help          Show this help

        Config: ~/.config/calendar/config.json
        """
        print(help)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = CalendarViewModel()
    private let configManager = ConfigManager.shared
    private var window: NotchWindow?
    private let windowDelegate = NotchWindowDelegate()
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var initialCommand: IPCCommand?
    private var isShowing = false
    /// Ignores resign-key while the panel is animating open / claiming focus.
    private var suppressHideOnBlur = false
    private var blurSuppressWorkItem: DispatchWorkItem?

    init(initialCommand: IPCCommand?) {
        self.initialCommand = initialCommand
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configManager.ensureDefaultConfigExists()

        IPCServer.shared.onCommand = { [weak self] command in
            Task { @MainActor in
                self?.handle(command)
            }
        }
        IPCServer.shared.start()

        configManager.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                guard let self else { return }
                // Chrome only — CalendarView already observes configManager / viewModel.
                self.window?.apply(config: config)
            }
            .store(in: &cancellables)

        if let initialCommand {
            handle(initialCommand)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        blurSuppressWorkItem?.cancel()
        removeKeyMonitor()
    }

    private func handle(_ command: IPCCommand) {
        switch command {
        case .toggle(let anchor):
            toggle(anchor: anchor)
        case .show(let anchor):
            show(anchor: anchor)
        case .hide:
            hide()
        case .reload:
            configManager.reload()
        case .ping:
            break
        }
    }

    private func toggle(anchor: CGRect?) {
        if isShowing {
            hide()
        } else {
            show(anchor: anchor)
        }
    }

    private func show(anchor: CGRect?) {
        ensureWindow()
        if let anchor {
            window?.anchorRect = NSRect(x: anchor.origin.x, y: anchor.origin.y, width: anchor.width, height: anchor.height)
        }
        viewModel.prepareForShow(showEvents: configManager.config.behavior.showEvents)
        // Ensure hosting view has latest bindings once; further updates are ObservedObject-driven.
        window?.setRootView(makeRootView())
        window?.apply(config: configManager.config)
        isShowing = true
        viewModel.isVisible = true
        suppressHideOnBlur = true
        blurSuppressWorkItem?.cancel()
        window?.showAnimated { [weak self] in
            guard let self else { return }
            let item = DispatchWorkItem { [weak self] in
                self?.suppressHideOnBlur = false
            }
            self.blurSuppressWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }
        installKeyMonitor()
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false
        viewModel.isVisible = false
        blurSuppressWorkItem?.cancel()
        blurSuppressWorkItem = nil
        suppressHideOnBlur = false
        removeKeyMonitor()
        window?.hideAnimated()
    }

    private func ensureWindow() {
        if window != nil { return }

        windowDelegate.onResignKey = { [weak self] in
            guard let self else { return }
            guard !self.suppressHideOnBlur else { return }
            if self.configManager.config.behavior.hideOnBlur {
                self.hide()
            }
        }

        let panel = NotchWindow(
            config: configManager.config,
            rootView: makeRootView()
        )
        panel.delegate = windowDelegate
        window = panel
    }

    private func makeRootView() -> CalendarView {
        CalendarView(
            viewModel: viewModel,
            configManager: configManager,
            onHeightChange: { [weak self] height in
                self?.window?.updateHeight(height)
            },
            onRequestClose: { [weak self] in
                self?.hide()
            }
        )
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = CalendarKeyRouter.handle(
                event: event,
                viewModel: self.viewModel,
                onClose: { [weak self] in self?.hide() }
            )
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
