import Combine
import Foundation
import SwiftUI

/// Maintains active / inactive / occupied workspace lists for the bar.
@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published private(set) var workspaces: [WorkspaceInfo] = []
    @Published private(set) var activeRawName: String?
    @Published var transitionToken = UUID()

    private let omniwm = OmniWMService()
    private var configFilter: [String]? = WorkspacesConfig.default.filterRawNames
    private var showEmpty = true

    func start() {
        omniwm.onWorkspacesChanged = { [weak self] list in
            self?.apply(list)
        }
        omniwm.onSpaceCommand = { [weak self] payload in
            self?.applySpacePayload(payload)
        }
        omniwm.start()
    }

    func stop() {
        omniwm.stop()
    }

    func updateConfig(_ config: BarConfig) {
        configFilter = config.workspaces.filterRawNames
        showEmpty = config.workspaces.showEmpty
        if !workspaces.isEmpty {
            apply(workspaces)
        }
    }

    func refresh() {
        omniwm.refreshFromCLI()
    }

    func applySpacePayload(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            omniwm.refreshFromCLI()
            return
        }

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OmniWMSpacePayload.self, from: data) {
            if let full = decoded.workspaces, !full.isEmpty {
                apply(full)
                return
            }
            if let active = decoded.active {
                optimisticActivate(active, occupied: decoded.occupied.map(Set.init))
            }
            omniwm.refreshFromCLI()
            return
        }

        optimisticActivate(trimmed, occupied: nil)
        omniwm.refreshFromCLI()
    }

    func selectWorkspace(_ rawName: String) {
        optimisticActivate(rawName, occupied: nil)
        omniwm.switchToWorkspace(rawName)
    }

    // MARK: - Private

    private func apply(_ list: [WorkspaceInfo]?) {
        guard let list else { return }

        var filtered = list
        if let allowed = configFilter, !allowed.isEmpty {
            let allow = Set(allowed)
            filtered = filtered.filter { allow.contains($0.rawName) }
            filtered.sort { a, b in
                let ia = allowed.firstIndex(of: a.rawName) ?? Int.max
                let ib = allowed.firstIndex(of: b.rawName) ?? Int.max
                return ia < ib
            }
        }

        if !showEmpty {
            filtered = filtered.filter { $0.isOccupied || $0.isCurrent || $0.isVisible }
        }

        let previousActive = activeRawName
        workspaces = filtered
        activeRawName = filtered.first(where: \.isCurrent)?.rawName
            ?? filtered.first(where: \.isVisible)?.rawName

        if activeRawName != previousActive {
            transitionToken = UUID()
        }
    }

    private func optimisticActivate(_ rawName: String, occupied: Set<String>?) {
        var next = workspaces
        if next.isEmpty {
            let names = configFilter ?? ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
            next = names.map { name in
                let isActive = name == rawName
                let isOcc = occupied?.contains(name) == true || isActive
                return WorkspaceInfo(
                    rawName: name,
                    displayName: name,
                    isCurrent: isActive,
                    isVisible: isActive,
                    windowCount: isOcc ? 1 : 0
                )
            }
        } else {
            next = next.map { ws in
                var copy = ws
                let isActive = ws.rawName == rawName
                copy.isCurrent = isActive
                copy.isVisible = isActive
                if let occupied, occupied.contains(ws.rawName) {
                    copy.windowCount = max(ws.windowCount, 1)
                }
                return copy
            }
        }

        let previous = activeRawName
        workspaces = next
        activeRawName = rawName
        if previous != rawName {
            transitionToken = UUID()
        }
    }
}
