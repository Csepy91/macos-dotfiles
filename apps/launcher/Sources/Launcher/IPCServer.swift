import Foundation

enum IPCCommand: String {
    case toggle
    case menu
    case show
    case hide
    case reload
}

/// Unix-domain socket used so `launcher --toggle` / `--menu` / `--reload` can
/// talk to the long-running LSUIElement instance (skhd-friendly).
final class IPCServer {
    static let shared = IPCServer()

    private var listener: NWUnixListener?
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

    func start() {
        let url = Self.socketURL
        try? FileManager.default.removeItem(at: url)

        let listener = NWUnixListener(path: url.path, queue: queue)
        listener.onMessage = { [weak self] line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let command = IPCCommand(rawValue: trimmed) else { return }
            DispatchQueue.main.async {
                self?.onCommand?(command)
            }
        }
        listener.start()
        self.listener = listener
    }

    /// Attempt to send a command to a running instance. Returns `true` if delivered.
    @discardableResult
    static func send(_ command: IPCCommand) -> Bool {
        NWUnixClient.send(command.rawValue + "\n", to: socketURL.path)
    }
}

// MARK: - Minimal Unix socket helpers (no Network.framework required)

private final class NWUnixListener {
    private let path: String
    private let queue: DispatchQueue
    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?

    var onMessage: ((String) -> Void)?

    init(path: String, queue: DispatchQueue) {
        self.path = path
        self.queue = queue
    }

    func start() {
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        precondition(pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path))
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
            return
        }

        guard listen(serverFD, 4) == 0 else {
            close(serverFD)
            serverFD = -1
            return
        }

        // Restrict socket to the current user.
        chmod(path, S_IRUSR | S_IWUSR)

        let fd = serverFD
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    private func acceptClient() {
        let client = accept(serverFD, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }

        var buffer = [UInt8](repeating: 0, count: 256)
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { return }
        let data = Data(buffer.prefix(n))
        if let line = String(data: data, encoding: .utf8) {
            onMessage?(line)
        }
    }

    deinit {
        source?.cancel()
        if serverFD >= 0 { close(serverFD) }
        try? FileManager.default.removeItem(atPath: path)
    }
}

private enum NWUnixClient {
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
