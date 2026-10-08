import AppKit
import Combine
import SwiftUI

@main
enum BarMain {
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
        let initial: IPCCommand? = flags.wantsRemoteAction ? flags.ipcCommand : nil
        let delegate = AppDelegate(initialCommand: initial)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

struct CLIFlags {
    var reload = false
    var refresh = false
    var omniwmSpace: String?
    var omniwmSpaceSeen = false

    var wantsRemoteAction: Bool {
        reload || refresh || omniwmSpaceSeen
    }

    var ipcCommand: IPCCommand {
        if reload { return .reload }
        if refresh { return .refresh }
        if omniwmSpaceSeen { return .omniwmSpace(omniwmSpace ?? "") }
        return .refresh
    }

    static func parse(_ args: [String]) -> CLIFlags {
        var flags = CLIFlags()
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--reload", "-r":
                flags.reload = true
            case "--refresh":
                flags.refresh = true
            case "--omniwm-space", "--space":
                flags.omniwmSpaceSeen = true
                if i + 1 < args.count, !args[i + 1].hasPrefix("-") {
                    flags.omniwmSpace = args[i + 1]
                    i += 1
                } else {
                    flags.omniwmSpace = ""
                }
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                // Allow `bar --omniwm-space=3` form.
                if arg.hasPrefix("--omniwm-space=") {
                    flags.omniwmSpaceSeen = true
                    flags.omniwmSpace = String(arg.dropFirst("--omniwm-space=".count))
                } else if arg.hasPrefix("--space=") {
                    flags.omniwmSpaceSeen = true
                    flags.omniwmSpace = String(arg.dropFirst("--space=".count))
                }
            }
            i += 1
        }
        return flags
    }

    static func printHelp() {
        let help = """
        Bar — native OmniWM workspace status bar

        Usage:
          bar                        Start the background agent
          bar --omniwm-space <id>    Update active workspace (id or JSON)
          bar --omniwm-space         Re-query OmniWM workspaces
          bar --reload               Reload ~/.config/bar/config.json
          bar --refresh              Re-query OmniWM without reloading config
          bar --help                 Show this help

        Config: ~/.config/bar/config.json

        skhd / OmniWM can also post:
          com.dotfiles.bar.omniwm-space  (DistributedNotification, optional payload)
        """
        print(help)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = WorkspaceViewModel()
    private let clock = ClockViewModel()
    private let battery = BatteryViewModel()
    private let configManager = ConfigManager.shared
    private var window: TopBarWindow?
    private var cancellables = Set<AnyCancellable>()
    private var initialCommand: IPCCommand?
    private var screenObserver: NSObjectProtocol?

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
                self.viewModel.updateConfig(config)
                // Chrome only — WorkspaceBarView already observes configManager / viewModel.
                self.window?.apply(config: config)
            }
            .store(in: &cancellables)

        viewModel.updateConfig(configManager.config)
        viewModel.start()
        clock.start()
        battery.start()

        ensureWindow()
        window?.showBar()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.window?.reposition(animated: false)
            }
        }

        if let initialCommand {
            handle(initialCommand)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
        clock.stop()
        battery.stop()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func handle(_ command: IPCCommand) {
        switch command {
        case .ping:
            break
        case .reload:
            configManager.reload()
        case .refresh:
            viewModel.refresh()
        case .omniwmSpace(let payload):
            viewModel.applySpacePayload(payload)
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let panel = TopBarWindow(
            config: configManager.config,
            rootView: makeRootView()
        )
        window = panel
    }

    private func makeRootView() -> WorkspaceBarView {
        WorkspaceBarView(
            viewModel: viewModel,
            clock: clock,
            battery: battery,
            configManager: configManager
        )
    }
}
