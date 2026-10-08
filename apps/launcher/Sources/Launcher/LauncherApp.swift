import AppKit
import Combine
import SwiftUI

@main
enum LauncherMain {
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
        let delegate = AppDelegate(initialCommand: initial, registerHotkey: !flags.noHotkey)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct CLIFlags {
    var toggle = false
    var menu = false
    var clipboard = false
    var show = false
    var hide = false
    var reload = false
    var noHotkey = false

    var wantsRemoteAction: Bool {
        toggle || menu || clipboard || show || hide || reload
    }

    var ipcCommand: IPCCommand {
        if menu { return .menu }
        if clipboard { return .clipboard }
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
            case "--clipboard", "-c": flags.clipboard = true
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
        Launcher — keyboard-driven app launcher, menu palette & clipboard history

        Usage:
          launcher                 Start the background agent
          launcher --toggle        Toggle the panel (skhd)
          launcher --menu          Open in Menu Search mode
          launcher --clipboard     Open in Clipboard History mode
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
    private var workspaceObservers: [NSObjectProtocol] = []
    private var focusToken = UUID()
    private var cancellables = Set<AnyCancellable>()
    private var initialCommand: IPCCommand?
    private var registerHotkey: Bool
    private var isShowing = false
    /// Ignores resign-key while the panel is animating open / claiming focus.
    private var suppressHideOnBlur = false
    private var blurSuppressWorkItem: DispatchWorkItem?
    private var appRefreshWorkItem: DispatchWorkItem?

    init(initialCommand: IPCCommand?, registerHotkey: Bool) {
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
        // Lost the ping→bind race: forward any CLI action and exit without UI.
        guard IPCServer.shared.start() else {
            if let initialCommand {
                _ = IPCServer.send(initialCommand)
            }
            NSLog("[Launcher] Another daemon owns IPC — exiting")
            NSApp.terminate(nil)
            return
        }

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
                ClipboardHistoryStore.shared.updateMaxItems(config.behavior.clipboardMaxItems)
            }
            .store(in: &cancellables)

        ClipboardHistoryStore.shared.start(maxItems: configManager.config.behavior.clipboardMaxItems)
        viewModel.refreshApps()
        installWorkspaceObservers()

        if let initialCommand {
            handle(initialCommand)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        blurSuppressWorkItem?.cancel()
        appRefreshWorkItem?.cancel()
        ClipboardHistoryStore.shared.stop()
        removeKeyMonitor()
        removeWorkspaceObservers()
    }

    private func installWorkspaceObservers() {
        removeWorkspaceObservers()
        let center = NSWorkspace.shared.notificationCenter

        let launchObs = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleAppRefresh()
            }
        }

        let terminateObs = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.viewModel.handleAppTerminated(app)
                self?.scheduleAppRefresh()
            }
        }

        workspaceObservers = [launchObs, terminateObs]
    }

    private func scheduleAppRefresh() {
        appRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.viewModel.refreshApps()
        }
        appRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: item)
    }

    private func removeWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            center.removeObserver(obs)
        }
        workspaceObservers.removeAll()
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
        case .clipboard:
            if isShowing, viewModel.mode == .clipboard {
                hide()
            } else {
                show(mode: .clipboard)
            }
        case .show:
            show(mode: .apps)
        case .hide:
            hide()
        case .reload:
            configManager.reload()
        case .ping:
            break
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
        suppressHideOnBlur = true
        blurSuppressWorkItem?.cancel()
        window?.showAnimated { [weak self] in
            guard let self else { return }
            self.focusToken = UUID()
            self.rebuildRootView()
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
                onClose: { [weak self] in self?.hide() },
                onActivate: { [weak self] in self?.hide() }
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
