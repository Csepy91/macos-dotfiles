import AppKit
import Combine
import SwiftUI

@main
enum LauncherMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let flags = CLIFlags.parse(args)

        // If a daemon is already running, forward the CLI command and exit.
        if flags.wantsRemoteAction {
            let command = flags.ipcCommand
            if IPCServer.send(command) {
                return
            }
            // No daemon yet — fall through and become it, applying the action on launch.
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(initialCommand: flags.ipcCommand, registerHotkey: !flags.noHotkey)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct CLIFlags {
    var toggle = false
    var menu = false
    var show = false
    var hide = false
    var reload = false
    var noHotkey = false

    var wantsRemoteAction: Bool {
        toggle || menu || show || hide || reload
    }

    var ipcCommand: IPCCommand {
        if menu { return .menu }
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
            case "--menu", "-m": flags.menu = true
            case "--show": flags.show = true
            case "--hide": flags.hide = true
            case "--reload", "-r": flags.reload = true
            case "--no-hotkey": flags.noHotkey = true
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
        Launcher — keyboard-driven app launcher & menu-bar command palette

        Usage:
          launcher                 Start the background agent
          launcher --toggle        Toggle the panel (skhd)
          launcher --menu          Open in Menu Search mode
          launcher --show          Show the panel
          launcher --hide          Hide the panel
          launcher --reload        Reload ~/.config/launcher/config.json
          launcher --no-hotkey     Skip registering the global hotkey
          launcher --help          Show this help

        Config: ~/.config/launcher/config.json
        """
        print(help)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = LauncherViewModel()
    private let configManager = ConfigManager.shared
    private var window: NotchWindow?
    private let windowDelegate = NotchWindowDelegate()
    private var localMonitor: Any?
    private var focusToken = UUID()
    private var cancellables = Set<AnyCancellable>()
    private var initialCommand: IPCCommand
    private var registerHotkey: Bool
    private var isShowing = false

    init(initialCommand: IPCCommand, registerHotkey: Bool) {
        self.initialCommand = initialCommand
        self.registerHotkey = registerHotkey
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

        if registerHotkey {
            HotkeyManager.shared.onHotkey = { [weak self] in
                Task { @MainActor in
                    self?.toggle(mode: nil)
                }
            }
            HotkeyManager.shared.update(from: configManager.config.behavior.hotkey)
        }

        configManager.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                guard let self else { return }
                self.window?.apply(config: config)
                if self.registerHotkey {
                    HotkeyManager.shared.update(from: config.behavior.hotkey)
                }
            }
            .store(in: &cancellables)

        // Warm the app index in the background.
        viewModel.refreshApps()

        // Apply the CLI action that started this process (if any).
        // Bare launch (no flags) stays hidden as a menu-bar agent.
        if CommandLine.arguments.count > 1 {
            handle(initialCommand)
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.refreshApps()
            }
        }
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.refreshApps()
            }
        }
    }

    private func handle(_ command: IPCCommand) {
        switch command {
        case .toggle:
            toggle(mode: nil)
        case .menu:
            if isShowing, viewModel.mode == .menu {
                hide()
            } else {
                show(mode: .menu)
            }
        case .show:
            show(mode: .apps)
        case .hide:
            hide()
        case .reload:
            configManager.reload()
        }
    }

    private func toggle(mode: LauncherMode?) {
        if isShowing {
            hide()
        } else {
            show(mode: mode)
        }
    }

    private func show(mode: LauncherMode?) {
        ensureWindow()
        viewModel.prepareForShow(preferredMode: mode ?? .apps)
        focusToken = UUID()
        rebuildRootView()
        isShowing = true
        viewModel.isVisible = true
        window?.showAnimated { [weak self] in
            self?.focusToken = UUID()
            self?.rebuildRootView()
        }
        installKeyMonitor()
    }

    private func hide() {
        guard isShowing else { return }
        isShowing = false
        viewModel.isVisible = false
        removeKeyMonitor()
        window?.hideAnimated()
    }

    private func ensureWindow() {
        if window != nil { return }

        windowDelegate.onResignKey = { [weak self] in
            guard let self else { return }
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

    private func makeRootView() -> MainView {
        MainView(
            viewModel: viewModel,
            configManager: configManager,
            onHeightChange: { [weak self] height in
                self?.window?.updateHeight(height)
            },
            onRequestClose: { [weak self] in
                self?.hide()
            },
            focusToken: focusToken
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
            let handled = LauncherKeyRouter.handle(
                event: event,
                viewModel: self.viewModel,
                onClose: { self.hide() },
                onActivate: { self.hide() }
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
