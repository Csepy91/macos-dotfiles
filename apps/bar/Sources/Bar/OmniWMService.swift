import Foundation

/// One OmniWM workspace row used by the bar.
struct WorkspaceInfo: Identifiable, Equatable, Codable {
    var id: String { rawName }
    var rawName: String
    var displayName: String
    var isCurrent: Bool
    var isVisible: Bool
    var windowCount: Int

    var isOccupied: Bool { windowCount > 0 }

    enum CodingKeys: String, CodingKey {
        case rawName
        case displayName
        case isCurrent
        case isVisible
        case windowCount
        case counts
    }

    init(
        rawName: String,
        displayName: String,
        isCurrent: Bool,
        isVisible: Bool,
        windowCount: Int
    ) {
        self.rawName = rawName
        self.displayName = displayName
        self.isCurrent = isCurrent
        self.isVisible = isVisible
        self.windowCount = windowCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawName = try c.decodeIfPresent(String.self, forKey: .rawName) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? rawName
        isCurrent = try c.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        if let count = try c.decodeIfPresent(Int.self, forKey: .windowCount) {
            windowCount = count
        } else if let counts = try? c.nestedContainer(keyedBy: CountsKeys.self, forKey: .counts) {
            windowCount = try counts.decodeIfPresent(Int.self, forKey: .total) ?? 0
        } else {
            windowCount = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rawName, forKey: .rawName)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(isCurrent, forKey: .isCurrent)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encode(windowCount, forKey: .windowCount)
    }

    private enum CountsKeys: String, CodingKey {
        case total
    }
}

/// Optional compact payload for `bar --omniwm-space '<json>'`.
struct OmniWMSpacePayload: Codable, Equatable {
    var active: String?
    var occupied: [String]?
    var workspaces: [WorkspaceInfo]?
}

/// Event-driven OmniWM bridge: one-shot CLI query + `omniwmctl subscribe`
/// stream (no polling timers).
@MainActor
final class OmniWMService {
    static let distributedNotificationName = Notification.Name("com.dotfiles.bar.omniwm-space")

    private let ctlPath: String
    private var subscribeProcess: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var notificationObserver: NSObjectProtocol?
    private var restartWorkItem: DispatchWorkItem?
    private var refreshDebounce: DispatchWorkItem?
    private var isStopping = false
    /// Exponential backoff for subscribe restarts (caps thrash when omniwmctl is missing).
    private var restartDelay: TimeInterval = 1.0
    private let maxRestartDelay: TimeInterval = 60.0

    /// Fired when OmniWM state should be re-queried / applied.
    var onWorkspacesChanged: (([WorkspaceInfo]?) -> Void)?
    /// Fired for distributed-notification / external space payloads.
    var onSpaceCommand: ((String) -> Void)?

    init(ctlPath: String? = nil) {
        self.ctlPath = ctlPath ?? Self.resolveOmniwmctl()
    }

    func start() {
        isStopping = false
        installNotificationObserver()
        startSubscription()
        refreshFromCLI()
    }

    func stop() {
        isStopping = true
        restartWorkItem?.cancel()
        restartWorkItem = nil
        refreshDebounce?.cancel()
        refreshDebounce = nil
        tearDownSubscription()
        removeNotificationObserver()
    }

    /// Re-query OmniWM and push results through `onWorkspacesChanged`.
    func refreshFromCLI() {
        let path = ctlPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let workspaces = Self.queryWorkspacesSync(ctlPath: path)
            DispatchQueue.main.async {
                self?.onWorkspacesChanged?(workspaces)
            }
        }
    }

    func switchToWorkspace(_ rawName: String) {
        let path = ctlPath
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["command", "switch-workspace", "anywhere", rawName]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Query

    nonisolated static func queryWorkspacesSync(ctlPath: String) -> [WorkspaceInfo]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ctlPath)
        process.arguments = [
            "query", "workspaces",
            "--fields", "raw-name,display-name,is-current,is-visible,window-counts",
            "--format", "json"
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[Bar] omniwmctl launch failed: \(error)")
            return nil
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !data.isEmpty else {
            return nil
        }
        return parseWorkspacesQuery(data)
    }

    nonisolated static func parseWorkspacesQuery(_ data: Data) -> [WorkspaceInfo]? {
        struct Envelope: Decodable {
            let ok: Bool?
            let result: ResultBlock?
        }
        struct ResultBlock: Decodable {
            let payload: Payload?
        }
        struct Payload: Decodable {
            let workspaces: [WorkspaceInfo]?
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.ok != false,
              let list = envelope.result?.payload?.workspaces
        else {
            return nil
        }
        return list.filter { !$0.rawName.isEmpty }
    }

    // MARK: - Subscribe (event bus)

    private func startSubscription() {
        tearDownSubscription()
        guard !isStopping else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ctlPath)
        process.arguments = [
            "subscribe",
            "active-workspace,windows-changed,layout-changed",
            "--reconnect",
            "--format", "ndjson"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.isStopping else { return }
                NSLog("[Bar] omniwmctl subscribe exited — restarting")
                self.scheduleSubscriptionRestart()
            }
        }

        do {
            try process.run()
        } catch {
            NSLog("[Bar] Failed to start omniwmctl subscribe: \(error)")
            scheduleSubscriptionRestart()
            return
        }

        // Successful spawn — reset backoff so a later clean exit recovers quickly.
        restartDelay = 1.0
        subscribeProcess = process
        stdoutPipe = stdout
        stderrPipe = stderr

        let handle = stdout.fileHandleForReading
        readHandle = handle
        handle.readabilityHandler = { [weak self] fileHandle in
            let chunk = fileHandle.availableData
            guard !chunk.isEmpty else {
                fileHandle.readabilityHandler = nil
                return
            }
            // Any NDJSON event → debounced re-query.
            DispatchQueue.main.async {
                self?.scheduleRefreshFromEvent()
            }
        }

        // Drain stderr so a chatty omniwmctl cannot fill the pipe and stall.
        let errHandle = stderr.fileHandleForReading
        stderrHandle = errHandle
        errHandle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            if chunk.isEmpty {
                fileHandle.readabilityHandler = nil
            }
        }
    }

    private func scheduleRefreshFromEvent() {
        refreshDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshFromCLI()
        }
        refreshDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    private func scheduleSubscriptionRestart() {
        restartWorkItem?.cancel()
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, maxRestartDelay)
        NSLog("[Bar] omniwmctl subscribe restart in %.0fs", delay)
        let item = DispatchWorkItem { [weak self] in
            self?.startSubscription()
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func tearDownSubscription() {
        readHandle?.readabilityHandler = nil
        readHandle = nil
        stderrHandle?.readabilityHandler = nil
        stderrHandle = nil
        if let process = subscribeProcess, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        subscribeProcess = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    // MARK: - Distributed notifications

    private func installNotificationObserver() {
        removeNotificationObserver()
        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let payload = (note.userInfo?["payload"] as? String)
                ?? (note.object as? String)
                ?? ""
            Task { @MainActor in
                self?.onSpaceCommand?(payload)
            }
        }
    }

    private func removeNotificationObserver() {
        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
            self.notificationObserver = nil
        }
    }

    static func resolveOmniwmctl() -> String {
        if let path = ProcessInfo.processInfo.environment["OMNIWMCTL"],
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let candidates = [
            "/opt/homebrew/bin/omniwmctl",
            "/usr/local/bin/omniwmctl"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/omniwmctl"
    }
}
