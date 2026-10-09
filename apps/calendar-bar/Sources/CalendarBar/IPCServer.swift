import Foundation

enum IPCCommand: Equatable {
    case toggle(anchor: CGRect?)
    case show(anchor: CGRect?)
    case hide
    case reload
    /// Probe used for single-instance detection (no UI side effects).
    case ping

    static func parse(_ line: String) -> IPCCommand? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let head = parts[0].lowercased()
        let rest = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let anchor = Self.parseAnchor(rest)

        switch head {
        case "ping":
            return .ping
        case "reload":
            return .reload
        case "hide":
            return .hide
        case "show":
            return .show(anchor: anchor)
        case "toggle":
            return .toggle(anchor: anchor)
        default:
            return nil
        }
    }

    /// `x,y,w,h` in AppKit screen coordinates.
    private static func parseAnchor(_ raw: String) -> CGRect? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let bits = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard bits.count == 4,
              let x = Double(bits[0]),
              let y = Double(bits[1]),
              let w = Double(bits[2]),
              let h = Double(bits[3])
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    var wireValue: String {
        switch self {
        case .ping: return "ping"
        case .reload: return "reload"
        case .hide: return "hide"
        case .show(let anchor):
            if let anchor { return "show \(Self.encodeAnchor(anchor))" }
            return "show"
        case .toggle(let anchor):
            if let anchor { return "toggle \(Self.encodeAnchor(anchor))" }
            return "toggle"
        }
    }

    private static func encodeAnchor(_ rect: CGRect) -> String {
        "\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
    }
}

/// Unix-domain socket so `calendar-bar --toggle` / `--reload` can talk to the
/// long-running LSUIElement instance (skhd / Bar-friendly).
final class IPCServer {
    static let shared = IPCServer()

    private var listener: UnixSocketListener?
    private let queue = DispatchQueue(label: "com.dotfiles.calendar-bar.ipc")

    var onCommand: ((IPCCommand) -> Void)?

    private init() {}

    static var socketURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("CalendarBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ipc.sock")
    }

    /// Returns `true` if another CalendarBar daemon already owns the IPC socket.
    static func isDaemonRunning() -> Bool {
        send(.ping)
    }

    /// Bind the IPC socket. Returns `false` if another process won the race
    /// (or bind failed) — callers must exit without showing UI.
    @discardableResult
    func start() -> Bool {
        let url = Self.socketURL

        // Weak on the outer closure — an inner-only [weak self] would force an
        // implicit strong capture here (Swift #ImplicitStrongCapture).
        let wire: (UnixSocketListener) -> Void = { [weak self] listener in
            listener.onMessage = { [weak self] line in
                guard let command = IPCCommand.parse(line) else { return }
                if case .ping = command { return }
                DispatchQueue.main.async {
                    self?.onCommand?(command)
                }
            }
        }

        // Bind without unlinking first — never steal a live peer's socket path.
        let first = UnixSocketListener(path: url.path, queue: queue)
        wire(first)
        if first.start() {
            self.listener = first
            return true
        }

        if Self.isDaemonRunning() {
            NSLog("[CalendarBar] IPC listen failed — live peer owns \(url.path)")
            return false
        }

        try? FileManager.default.removeItem(at: url)
        let second = UnixSocketListener(path: url.path, queue: queue)
        wire(second)
        guard second.start() else {
            NSLog("[CalendarBar] IPC listen failed at \(url.path)")
            return false
        }
        self.listener = second
        return true
    }

    /// Tear down the listener (cancels the DispatchSource, closes the FD, unlinks the sock).
    func stop() {
        onCommand = nil
        listener = nil
    }

    /// Attempt to send a command to a running instance. Returns `true` if delivered.
    @discardableResult
    static func send(_ command: IPCCommand) -> Bool {
        UnixSocketClient.send(command.wireValue + "\n", to: socketURL.path)
    }
}

// MARK: - Minimal Unix socket helpers (no Network.framework required)

private final class UnixSocketListener {
    private let path: String
    private let queue: DispatchQueue
    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?

    var onMessage: ((String) -> Void)?

    init(path: String, queue: DispatchQueue) {
        self.path = path
        self.queue = queue
    }

    @discardableResult
    func start() -> Bool {
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(serverFD)
            serverFD = -1
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { src in
                buffer.copyMemory(from: src)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            serverFD = -1
            return false
        }

        guard listen(serverFD, 4) == 0 else {
            close(serverFD)
            serverFD = -1
            return false
        }

        chmod(path, S_IRUSR | S_IWUSR)

        let fd = serverFD
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler { [weak self] in
            close(fd)
            self?.serverFD = -1
        }
        self.source = source
        source.resume()
        return true
    }

    private func acceptClient() {
        let client = accept(serverFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        // Bound wait so a silent peer cannot stall the IPC queue.
        var polls = [pollfd(fd: client, events: Int16(POLLIN), revents: 0)]
        let ready = poll(&polls, 1, 200)
        guard ready > 0, (polls[0].revents & Int16(POLLIN)) != 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 512)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer.prefix(n))
        if let line = String(data: data, encoding: .utf8) {
            onMessage?(line)
        }
    }

    deinit {
        if let source {
            source.cancel()
            self.source = nil
        } else if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}

private enum UnixSocketClient {
    static func send(_ message: String, to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            pathBytes.withUnsafeBytes { src in
                buffer.copyMemory(from: src)
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        let bytes = Array(message.utf8)
        let written = bytes.withUnsafeBufferPointer { ptr in
            Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
        return written == bytes.count
    }
}
