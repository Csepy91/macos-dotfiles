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

    var wantsRemoteAction: Bool {
        toggle || show || hide || reload
    }

    var ipcCommand: IPCCommand {
        if hide { return .hide }
        if reload { return .reload }
        if show { return .show }
        return .toggle
    }

    static func parse(_ args: [String]) -> CLIFlags {
        var flags = CLIFlags()
        for arg in args {
            switch arg {
            case "--toggle", "-t": flags.toggle = true
            case "--show": flags.show = true
            case "--hide": flags.hide = true
            case "--reload", "-r": flags.reload = true
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                break
            }
        }
        return flags
    }

    static func printHelp() {
        let help = """
        CalendarBar — notch calendar & agenda popover

        Usage:
          calendar-bar                 Start the background agent
          calendar-bar --toggle        Toggle the panel (sketchybar / skhd)
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
                self.window?.apply(config: config)
                if self.isShowing {
                    self.rebuildRootView()
                }
            }
            .store(in: &cancellables)

        viewModel.$events
            .combineLatest(viewModel.$authState, viewModel.$days)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self, self.isShowing else { return }
                self.rebuildRootView()
            }
            .store(in: &cancellables)

        if let initialCommand {
            handle(initialCommand)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyMonitor()
    }

    private func handle(_ command: IPCCommand) {
        switch command {
        case .toggle:
            toggle()
        case .show:
            show()
        case .hide:
            hide()
        case .reload:
            configManager.reload()
        case .ping:
            break
        }
    }

    private func toggle() {
        if isShowing {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        ensureWindow()
        viewModel.prepareForShow(showEvents: configManager.config.behavior.showEvents)
        rebuildRootView()
        isShowing = true
        viewModel.isVisible = true
        suppressHideOnBlur = true
        window?.showAnimated { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.suppressHideOnBlur = false
            }
        }
        installKeyMonitor()
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false
        viewModel.isVisible = false
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

    private func rebuildRootView() {
        guard let window else { return }
        window.setRootView(makeRootView())
        window.apply(config: configManager.config)
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
