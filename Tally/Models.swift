import Foundation

enum Phase: String, Codable {
    case work, shortBreak, longBreak

    var isBreak: Bool { self != .work }

    var title: String {
        switch self {
        case .work: return "Work"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

struct LogEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var label: String
    var phase: Phase
    var start: Date
    var end: Date
    /// Time the clock was actually running. Pauses and the gap before a +5 are not counted.
    var seconds: Int
    /// False when the block was stopped before the timer ran out.
    var completed: Bool
    var addedMinutes: Int
    /// Minutes worked past the end before you responded. Older entries don't have this.
    var overtimeMinutes: Int? = nil

    var minutes: Double { Double(seconds) / 60 }
    var displayLabel: String { label.isEmpty ? "Unlabelled" : label }
}

enum Prefs {
    enum Key {
        static let work = "workMinutes"
        static let shortBreak = "shortBreakMinutes"
        static let longBreak = "longBreakMinutes"
        static let longEvery = "longBreakEvery"
        static let extend = "extendMinutes"
        static let menuSeconds = "menuBarSeconds"
        static let alwaysOnTop = "alwaysOnTop"
        static let hideDock = "hideDockIcon"
        static let sound = "playSound"
        static let includeBreaks = "includeBreaks"
        static let sheetsURL = "sheetsURL"
        static let popup = "showPopup"
        static let menuStyle = "menuStyle"
        static let keepCounting = "keepCounting"
        static let sheetLink = "sheetLink"
        static let miniStyle = "miniStyle"
    }

    private static var d: UserDefaults { .standard }

    static func int(_ key: String, _ fallback: Int) -> Int {
        d.object(forKey: key) == nil ? fallback : d.integer(forKey: key)
    }

    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    static var workMinutes: Int { max(1, int(Key.work, 25)) }
    static var shortMinutes: Int { max(1, int(Key.shortBreak, 5)) }
    static var longMinutes: Int { max(1, int(Key.longBreak, 15)) }
    static var longEvery: Int { max(1, int(Key.longEvery, 4)) }
    static var extendBy: Int { max(1, int(Key.extend, 5)) }
    static var playsSound: Bool { bool(Key.sound, true) }
    static var includesBreaks: Bool { bool(Key.includeBreaks, false) }
    static var sheetsURL: String { d.string(forKey: Key.sheetsURL) ?? "" }
    static var showsPopup: Bool { bool(Key.popup, true) }
    static var keepsCounting: Bool { bool(Key.keepCounting, true) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Int {
    /// Treats the value as minutes: 155 → "2h 35m".
    var hoursMinutes: String {
        let h = self / 60, m = self % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

enum Fmt {
    static func make(_ format: String, posix: Bool = false) -> DateFormatter {
        let f = DateFormatter()
        if posix { f.locale = Locale(identifier: "en_US_POSIX") }
        f.dateFormat = format
        return f
    }

    static let isoDay = make("yyyy-MM-dd", posix: true)
    static let clock = make("HH:mm", posix: true)
    static let dayShort = make("EEE d MMM")
    static let dayName = make("EEE")
    static let dayMonth = make("d MMM")
    static let monthYear = make("MMMM yyyy")

    /// Weeks start on Monday.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        c.locale = .current
        return c
    }()

    static func timer(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func pomodoros(_ n: Int) -> String {
        n == 1 ? "1 pomodoro" : "\(n) pomodoros"
    }
}
