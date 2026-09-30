import AppKit

/// The time log, saved as JSON in ~/Library/Application Support/tally/log.json
@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []

    let folder: URL
    private let fileURL: URL

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("tally", isDirectory: true)
        fileURL = folder.appendingPathComponent("log.json")
        // Older builds used "Tally". Same folder on a normal Mac drive; moved across on a case-sensitive one.
        let oldFolder = support.appendingPathComponent("Tally", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: oldFolder.path) && !fm.fileExists(atPath: folder.path) {
            try? fm.moveItem(at: oldFolder, to: folder)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try Self.decoder.decode([LogEntry].self, from: data).sorted { $0.start < $1.start }
        } catch {
            // Keep a copy of a file we can't read rather than overwrite it on the next save.
            let backup = folder.appendingPathComponent("log-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        do {
            try Self.encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("tally: couldn't save the log: \(error)")
        }
    }

    func add(_ entry: LogEntry) {
        entries.append(entry)
        save()
        SheetsSync.shared.enqueue([entry])
    }

    func rename(_ id: UUID, to label: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].label = label.trimmed.lowercased()
        save()
        SheetsSync.shared.enqueue([entries[i]])
    }

    /// Renames every block with this label (case doesn't matter). Returns how many changed.
    @discardableResult
    func renameAll(from old: String, to new: String) -> Int {
        let from = old.trimmed.lowercased()
        let to = new.trimmed.lowercased()
        guard from != to else { return 0 }
        var changed: [LogEntry] = []
        for i in entries.indices where entries[i].label.lowercased() == from {
            entries[i].label = to
            changed.append(entries[i])
        }
        guard !changed.isEmpty else { return 0 }
        save()
        SheetsSync.shared.enqueue(changed)
        return changed.count
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func entries(in interval: DateInterval) -> [LogEntry] {
        entries.filter { $0.start >= interval.start && $0.start < interval.end }
    }

    /// Most recently used labels first, no duplicates.
    func labels(limit: Int? = nil) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in entries.reversed() where e.phase == .work && !e.label.isEmpty {
            let key = e.label.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(key)
            if let limit, out.count == limit { break }
        }
        return out
    }

    var recentLabels: [String] { labels(limit: 12) }
    var allLabels: [String] { labels() }

    private var todayWork: [LogEntry] {
        let start = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.phase == .work && $0.start >= start }
    }

    var todayPomodoros: Int { todayWork.filter(\.completed).count }
    var todayMinutes: Int { todayWork.reduce(0) { $0 + $1.seconds } / 60 }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
