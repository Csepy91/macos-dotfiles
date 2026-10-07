import AppKit
import Foundation

struct LauncherApp: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let bundleIdentifier: String?

    /// Cached per-path icons (main-actor). Avoids rebuilding NSImage every SwiftUI body pass.
    @MainActor
    private static var iconCache: [String: NSImage] = [:]

    @MainActor
    var icon: NSImage {
        if let cached = Self.iconCache[path] {
            return cached
        }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 32, height: 32)
        Self.iconCache[path] = image
        return image
    }

    @MainActor
    static func pruneIconCache(keepingPaths paths: Set<String>) {
        iconCache = iconCache.filter { paths.contains($0.key) }
    }
}

/// Indexes `.app` bundles under `/Applications`, `/System/Applications`, and `~/Applications`.
actor AppScanner {
    static let shared = AppScanner()

    private var apps: [LauncherApp] = []
    private var isScanning = false
    /// If a refresh is requested while one is in flight, run again after it finishes.
    private var needsRescan = false

    func allApps() async -> [LauncherApp] {
        if apps.isEmpty {
            await refresh()
        }
        return apps
    }

    func refresh() async {
        if isScanning {
            needsRescan = true
            return
        }
        isScanning = true
        defer {
            isScanning = false
            if needsRescan {
                needsRescan = false
                // Schedule a follow-up scan without blocking the current caller forever.
                Task { await self.refresh() }
            }
        }

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

        let paths = Set(apps.map(\.path))
        await MainActor.run {
            LauncherApp.pruneIconCache(keepingPaths: paths)
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
