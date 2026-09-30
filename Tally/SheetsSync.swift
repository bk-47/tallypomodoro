import Foundation

/// Sends finished blocks to a Google Sheet through an Apps Script web app.
/// Rows that can't be sent are kept and retried every few minutes.
@MainActor
final class SheetsSync: ObservableObject {
    static let shared = SheetsSync()

    @Published private(set) var status = ""

    private var pending: [LogEntry] = []
    private var sending = false
    private let fileURL: URL
    private var retryTimer: Timer?

    private init() {
        fileURL = LogStore.shared.folder.appendingPathComponent("sheets-pending.json")
        if let data = try? Data(contentsOf: fileURL) {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            pending = (try? d.decode([LogEntry].self, from: data)) ?? []
        }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private var url: URL? {
        let s = Prefs.sheetsURL.trimmed
        guard !s.isEmpty, let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }

    func note(_ message: String) { status = message }

    func enqueue(_ entries: [LogEntry]) {
        guard url != nil else { return }
        let include = Prefs.includesBreaks
        let incoming = entries.filter { include || $0.phase == .work }
        // A renamed block replaces its queued copy; the script updates rows it already has.
        let ids = Set(incoming.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        pending.append(contentsOf: incoming)
        save()
        flush()
    }

    /// Queues everything in the log. The script ignores rows it already has.
    func sendAll() {
        guard url != nil else { status = "Add the web app URL first."; return }
        let include = Prefs.includesBreaks
        let queued = Set(pending.map(\.id))
        pending += LogStore.shared.entries.filter { (include || $0.phase == .work) && !queued.contains($0.id) }
        save()
        status = "Sending \(pending.count) rows."
        flush()
    }

    func test() {
        guard let url else {
            status = "That URL doesn't look right. It should start with https://script.google.com/"
            return
        }
        status = "Testing."
        let req = request(url, body: ["test": true])
        Task {
            let ok = await send(req)
            status = ok
                ? "Connected. Finished blocks will be added to the sheet."
                : "Couldn't connect. Check the URL, and that the web app's access is set to Anyone."
        }
    }

    func flush() {
        guard !sending, let url, !pending.isEmpty else { return }
        sending = true
        let batch = Array(pending.prefix(200))
        let req = request(url, body: ["rows": batch.map { row($0) }])
        Task {
            let ok = await send(req)
            sending = false
            if ok {
                let sent = Set(batch.map(\.id))
                pending.removeAll { sent.contains($0.id) }
                save()
                status = pending.isEmpty ? "Sheet up to date." : "Sending \(pending.count) more rows."
                if !pending.isEmpty { flush() }
            } else {
                status = "Couldn't reach the sheet. \(pending.count) rows waiting, will retry."
            }
        }
    }

    private func row(_ e: LogEntry) -> [String: Any] {
        [
            "id": e.id.uuidString,
            "date": Fmt.isoDay.string(from: e.start),
            "start": Fmt.clock.string(from: e.start),
            "end": Fmt.clock.string(from: e.end),
            "label": e.label,
            "type": e.phase.title,
            "minutes": (e.minutes * 10).rounded() / 10,
            "completed": e.completed,
            "added": e.addedMinutes,
        ]
    }

    private func request(_ url: URL, body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30
        return req
    }

    private func send(_ req: URLRequest) async -> Bool {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return false }
            // A wrongly deployed script returns a Google sign-in page with status 200, so check the body.
            return String(decoding: data, as: UTF8.self).contains("\"ok\":true")
        } catch {
            return false
        }
    }

    private func save() {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(pending).write(to: fileURL, options: .atomic)
    }
}
