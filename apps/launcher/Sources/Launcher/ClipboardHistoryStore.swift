import AppKit
import Combine
import Foundation

enum ClipboardEntryKind: String, Codable, Hashable {
    case text
    case image
}

struct ClipboardEntry: Identifiable, Hashable, Codable {
    let id: String
    let kind: ClipboardEntryKind
    /// Plain-text body, or a short label for images.
    let preview: String
    let createdAt: Date
    /// Relative filename under `images/`, if any.
    let imageFilename: String?

    var searchKey: String { preview }

    var displayTitle: String {
        switch kind {
        case .text:
            let trimmed = preview
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "(empty)" }
            if trimmed.count > 120 {
                return String(trimmed.prefix(117)) + "…"
            }
            return trimmed
        case .image:
            return preview.isEmpty ? "Image" : preview
        }
    }
}

/// Polls the general pasteboard, persists text/image history, and publishes entries.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var entries: [ClipboardEntry] = []

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    /// When true, the next pasteboard change is from our own write — skip recording.
    private var ignoreNextChange = false
    private var maxItems: Int = 100

    private let fm = FileManager.default

    private var rootDirectory: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Launcher/clipboard", isDirectory: true)
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent("index.json")
    }

    private var imagesDirectory: URL {
        rootDirectory.appendingPathComponent("images", isDirectory: true)
    }

    private init() {
        ensureDirectories()
        loadFromDisk()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start(maxItems: Int) {
        self.maxItems = max(1, maxItems)
        pruneToCap()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateMaxItems(_ maxItems: Int) {
        self.maxItems = max(1, maxItems)
        pruneToCap()
    }

    /// Write an entry back to the pasteboard without re-inserting it into history.
    func copyToPasteboard(_ entry: ClipboardEntry) -> Bool {
        let pb = NSPasteboard.general
        ignoreNextChange = true
        pb.clearContents()

        switch entry.kind {
        case .text:
            pb.setString(entry.preview, forType: .string)
            lastChangeCount = pb.changeCount
            return true
        case .image:
            guard let filename = entry.imageFilename else {
                ignoreNextChange = false
                return false
            }
            let url = imagesDirectory.appendingPathComponent(filename)
            guard let image = NSImage(contentsOf: url) else {
                ignoreNextChange = false
                return false
            }
            pb.writeObjects([image])
            lastChangeCount = pb.changeCount
            return true
        }
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.kind == .image, let filename = entry.imageFilename else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(filename))
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        if let string = pb.string(forType: .string), !string.isEmpty {
            // Prefer text when both are present (e.g. rich copy).
            recordText(string)
            return
        }

        if let image = readImage(from: pb) {
            recordImage(image)
        }
    }

    private func readImage(from pb: NSPasteboard) -> NSImage? {
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first
        {
            return image
        }
        // TIFF / PNG data fallbacks.
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
           let image = NSImage(data: data)
        {
            return image
        }
        return nil
    }

    private func recordText(_ text: String) {
        if let newest = entries.first,
           newest.kind == .text,
           newest.preview == text
        {
            return
        }
        let entry = ClipboardEntry(
            id: UUID().uuidString,
            kind: .text,
            preview: text,
            createdAt: Date(),
            imageFilename: nil
        )
        insert(entry)
    }

    private func recordImage(_ image: NSImage) {
        guard let png = pngData(from: image) else { return }

        // Dedupe against newest image by byte equality when possible.
        if let newest = entries.first,
           newest.kind == .image,
           let filename = newest.imageFilename
        {
            let url = imagesDirectory.appendingPathComponent(filename)
            if let existing = try? Data(contentsOf: url), existing == png {
                return
            }
        }

        let id = UUID().uuidString
        let filename = "\(id).png"
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            NSLog("[Launcher] Failed to write clipboard image: \(error)")
            return
        }

        let w = Int(image.size.width.rounded())
        let h = Int(image.size.height.rounded())
        let entry = ClipboardEntry(
            id: id,
            kind: .image,
            preview: "Image \(w)×\(h)",
            createdAt: Date(),
            imageFilename: filename
        )
        insert(entry)
    }

    private func insert(_ entry: ClipboardEntry) {
        entries.insert(entry, at: 0)
        pruneToCap()
        saveToDisk()
    }

    private func pruneToCap() {
        guard entries.count > maxItems else { return }
        let removed = entries.suffix(from: maxItems)
        for entry in removed {
            if let filename = entry.imageFilename {
                try? fm.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            }
        }
        entries = Array(entries.prefix(maxItems))
        saveToDisk()
    }

    // MARK: - Persistence

    private func ensureDirectories() {
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    private func loadFromDisk() {
        ensureDirectories()
        guard let data = try? Data(contentsOf: indexURL) else {
            entries = []
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([ClipboardEntry].self, from: data)
        } catch {
            NSLog("[Launcher] Failed to load clipboard index: \(error)")
            entries = []
        }
    }

    private func saveToDisk() {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(entries)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("[Launcher] Failed to save clipboard index: \(error)")
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
