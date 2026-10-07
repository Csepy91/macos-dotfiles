import AppKit
import Foundation

struct LauncherApp: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String?

    @MainActor
    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }
}

/// Indexes `.app` bundles under `/Applications`, `/System/Applications`, and `~/Applications`.
actor AppScanner {
    static let shared = AppScanner()

    private var apps: [LauncherApp] = []
    private var isScanning = false

    func allApps() async -> [LauncherApp] {
        if apps.isEmpty {
            await refresh()
        }
        return apps
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let roots = defaultRoots()
        var found: [String: LauncherApp] = [:]

        for root in roots {
            let urls = enumerateApps(at: root)
            for url in urls {
                let path = url.path
                let name = url.deletingPathExtension().lastPathComponent
                let bundleID = Bundle(url: url)?.bundleIdentifier
                let key = bundleID ?? path
                if found[key] == nil {
                    found[key] = LauncherApp(
                        id: key,
                        name: name,
                        path: path,
                        bundleIdentifier: bundleID
                    )
                }
            }
        }

        apps = found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func defaultRoots() -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        let homeApps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        if FileManager.default.fileExists(atPath: homeApps.path) {
            roots.append(homeApps)
        }
        return roots
    }

    private func enumerateApps(at root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            results.append(url)
            enumerator.skipDescendants()
        }
        return results
    }
}
