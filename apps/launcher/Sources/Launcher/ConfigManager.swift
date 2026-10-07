import Combine
import Foundation

/// Loads `~/.config/launcher/config.json` and hot-reloads on change.
@MainActor
final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config: LauncherConfig = .default

    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/launcher/config.json")
    }

    private init() {
        load()
        startWatching()
    }

    func reload() {
        load()
    }

    func ensureDefaultConfigExists() {
        let url = configURL
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard !fm.fileExists(atPath: url.path) else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(LauncherConfig.default) else { return }
        try? data.write(to: url, options: .atomic)
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
            config = try decoder.decode(LauncherConfig.self, from: data)
        } catch {
            NSLog("[Launcher] Failed to parse config.json: \(error)")
            // Keep last-known-good config rather than thrashing on a typo mid-edit.
        }
    }

    private func startWatching() {
        stopWatching()
        ensureDefaultConfigExists()

        let path = configURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // File may appear later — retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startWatching()
            }
            return
        }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            // Debounce editors that write via temp+rename.
            self.scheduleReload()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.startWatching()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    private func scheduleReload() {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.load()
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            fileDescriptor = -1
        }
    }

}
