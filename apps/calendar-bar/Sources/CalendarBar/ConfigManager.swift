import Combine
import Foundation

/// Loads `~/.config/calendar/config.json` and hot-reloads on change.
@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config: CalendarConfig = .default

    private var source: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?
    private var restartWorkItem: DispatchWorkItem?
    private var openRetryWorkItem: DispatchWorkItem?
    private var openRetryDelay: TimeInterval = 2
    private let maxOpenRetryDelay: TimeInterval = 60

    var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/calendar/config.json")
    }

    private init() {
        load()
        startWatching()
    }

    func reload() {
        load()
    }

    /// Ensures the config directory exists. Does **not** seed `config.json` —
    /// that file is owned by the stowed `packages/calendar` tree. Missing file
    /// → in-memory Catppuccin Macchiato defaults until stow (or the user) provides one.
    func ensureDefaultConfigExists() {
        let dir = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func load() {
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            config = .default
            return
        }

        do {
            let decoder = JSONDecoder()
            config = try decoder.decode(CalendarConfig.self, from: data)
        } catch {
            NSLog("[CalendarBar] Failed to parse config.json: \(error)")
            // Keep last-known-good config rather than thrashing on a typo mid-edit.
        }
    }

    private func startWatching() {
        stopWatching()
        ensureDefaultConfigExists()

        let path = configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            scheduleOpenRetry()
            return
        }

        openRetryDelay = 2

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.scheduleReload()
            // Never cancel a DispatchSource from inside its own handler — defer.
            if flags.contains(.delete) || flags.contains(.rename) {
                self.scheduleWatcherRestart()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    private func scheduleOpenRetry() {
        openRetryWorkItem?.cancel()
        let delay = openRetryDelay
        openRetryDelay = min(openRetryDelay * 2, maxOpenRetryDelay)
        let item = DispatchWorkItem { [weak self] in
            self?.load()
            self?.startWatching()
        }
        openRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.load()
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func scheduleWatcherRestart() {
        restartWorkItem?.cancel()
        // Atomic editors rename/delete the file; stopWatching cancels any pending
        // debounced reload, so load here before re-attaching the watcher.
        let item = DispatchWorkItem { [weak self] in
            self?.load()
            self?.startWatching()
        }
        restartWorkItem = item
        DispatchQueue.main.async(execute: item)
    }

    private func stopWatching() {
        openRetryWorkItem?.cancel()
        openRetryWorkItem = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        source?.cancel()
        source = nil
    }
}
