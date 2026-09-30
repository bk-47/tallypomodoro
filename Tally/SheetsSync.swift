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

    /// Link to the sheet itself, learned from a successful test.
    @Published private(set) var sheetLink: URL? =
        UserDefaults.standard.string(forKey: Prefs.Key.sheetLink).flatMap { URL(string: $0) }

    @Published private(set) var busy = false

    func test() {
        guard let url else {
            status = "That URL doesn't look right. It should start with https://script.google.com/ and end in /exec."
            return
        }
        status = "Testing."
        busy = true
        let req = request(url, body: ["test": true])
        Task {
            let reply = await sendForReply(req)
            busy = false
            guard let reply, reply["ok"] as? Bool == true else {
                status = "Couldn't connect. Check the URL, and that the web app's access is set to Anyone."
                return
            }
            if let link = reply["sheet"] as? String, let u = URL(string: link) {
                sheetLink = u
                UserDefaults.standard.set(link, forKey: Prefs.Key.sheetLink)
            }
            let version = reply["version"] as? Int ?? 1
            if version < SheetsSetup.scriptVersion {
                status = "Connected, but the script in the sheet is an older version. Copy the new one, paste it over the old, and redeploy as a new version."
            } else {
                status = "Connected. Finished blocks will be added to the sheet, and the dashboard builds itself with the first one."
                flush()
            }
        }
    }

    /// Asks the script to (re)build the dashboard tab.
    func buildDashboard() {
        guard let url else { status = "Add the web app URL first."; return }
        status = "Building the dashboard. This can take half a minute."
        busy = true
        var req = request(url, body: ["action": "dashboard"])
        req.timeoutInterval = 120
        Task {
            let reply = await sendForReply(req)
            busy = false
            if reply?["dashboard"] as? Bool == true {
                status = "Dashboard built. Open the sheet to see it."
            } else if reply?["ok"] as? Bool == true {
                status = "The script in the sheet is an older version. Copy the new one, paste it over the old, and redeploy as a new version."
            } else {
                status = "Couldn't build it. Check the connection with test."
            }
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
        // Generous: the first rows in a new sheet also build the dashboard.
        req.timeoutInterval = 90
        return req
    }

    private func sendForReply(_ req: URLRequest) async -> [String: Any]? {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
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
