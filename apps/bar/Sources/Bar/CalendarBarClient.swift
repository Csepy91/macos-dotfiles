import AppKit
import Foundation

/// Talks to the rice CalendarBar agent (`calendar-bar --toggle`).
enum CalendarBarClient {
    /// Toggle the calendar panel, anchored under `anchor` (AppKit screen coords).
    static func toggle(anchor: NSRect? = nil) {
        let command = wireToggle(anchor: anchor)
        DispatchQueue.global(qos: .userInitiated).async {
            if send(command) { return }
            var args = ["--toggle"]
            if let anchor, anchor.width > 0, anchor.height > 0 {
                args.append(contentsOf: [
                    "--anchor",
                    "\(anchor.origin.x),\(anchor.origin.y),\(anchor.size.width),\(anchor.size.height)"
                ])
            }
            launch(args)
        }
    }

    private static func wireToggle(anchor: NSRect?) -> String {
        guard let anchor, anchor.width > 0, anchor.height > 0 else { return "toggle" }
        return "toggle \(anchor.origin.x),\(anchor.origin.y),\(anchor.size.width),\(anchor.size.height)"
    }

    private static var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CalendarBar", isDirectory: true)
            .appendingPathComponent("ipc.sock")
            .path
    }

    @discardableResult
    private static func send(_ command: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketPath
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

        let message = Array((command + "\n").utf8)
        let written = message.withUnsafeBufferPointer { ptr in
            Darwin.write(fd, ptr.baseAddress, ptr.count)
        }
        return written == message.count
    }

    private static func launch(_ args: [String]) {
        let candidates = [
            NSHomeDirectory() + "/Applications/CalendarBar.app/Contents/MacOS/CalendarBar",
            "/Applications/CalendarBar.app/Contents/MacOS/CalendarBar"
        ]
        guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            NSLog("[Bar] CalendarBar.app not found — run ./scripts/install-calendar-bar.sh")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
