import Foundation

enum IPCCommand: String {
    case toggle
    case menu
    case clipboard
    case show
    case hide
    case reload
    /// Probe used for single-instance detection (no UI side effects).
    case ping
}

/// Unix-domain socket used so `launcher --toggle` / `--menu` / `--reload` can
/// talk to the long-running LSUIElement instance (skhd-friendly).
final class IPCServer {
    static let shared = IPCServer()

    private var listener: UnixSocketListener?
    private let queue = DispatchQueue(label: "com.dotfiles.launcher.ipc")

    var onCommand: ((IPCCommand) -> Void)?

    private init() {}

    static var socketURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Launcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ipc.sock")
    }

    /// Returns `true` if another Launcher daemon already owns the IPC socket.
    static func isDaemonRunning() -> Bool {
        send(.ping)
    }

    /// Bind the IPC socket. Returns `false` if another process won the race
    /// (or bind failed) — callers must exit without showing UI.
    @discardableResult
    func start() -> Bool {
        let url = Self.socketURL
        // Only unlink if we are becoming the daemon; callers must ensure no live peer.
        try? FileManager.default.removeItem(at: url)

        let listener = UnixSocketListener(path: url.path, queue: queue)
        listener.onMessage = { [weak self] line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let command = IPCCommand(rawValue: trimmed) else { return }
            if command == .ping { return }
            DispatchQueue.main.async {
                self?.onCommand?(command)
            }
        }
        guard listener.start() else {
            NSLog("[Launcher] IPC listen failed at \(url.path)")
            return false
        }
        self.listener = listener
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
        UnixSocketClient.send(command.rawValue + "\n", to: socketURL.path)
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

        // Restrict socket to the current user.
        chmod(path, S_IRUSR | S_IWUSR)

        let fd = serverFD
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        // Own the FD exclusively in the cancel handler — never close twice.
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

        var buffer = [UInt8](repeating: 0, count: 256)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer.prefix(n))
        if let line = String(data: data, encoding: .utf8) {
            onMessage?(line)
        }
    }

    deinit {
        // Cancel closes the FD once via setCancelHandler. Do not close again.
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
