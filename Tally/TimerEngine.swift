import AppKit
import Combine

enum RunState { case idle, running, paused, finished }

/// The timer. A block moves idle → running ⇄ paused → finished.
/// A finished block isn't written to the log until you start the next one, skip, stop or quit,
/// so +5 can reopen it and it still lands as one entry.
@MainActor
final class TimerEngine: ObservableObject {
    static let shared = TimerEngine()

    @Published private(set) var phase: Phase = .work
    @Published private(set) var state: RunState = .idle
    @Published private(set) var remaining = 0
    @Published private(set) var planned = 0
    @Published private(set) var cycleCount = 0
    @Published var label: String = UserDefaults.standard.string(forKey: "lastLabel") ?? "" {
        didSet { UserDefaults.standard.set(label, forKey: "lastLabel") }
    }

    private(set) var addedMinutes = 0
    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    private var blockStart: Date?
    private var lastResume: Date?
    private var activeTime: TimeInterval = 0
    private var finishedAt: Date?
    private var ticker: Timer?
    private var prefsObserver: AnyCancellable?

    private init() {
        resetIdleDisplay()
        prefsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state == .idle else { return }
                    self.resetIdleDisplay()
                }
            }
    }

    // MARK: - Display

    var progress: Double {
        guard planned > 0 else { return 0 }
        if state == .idle { return 0 }
        return min(1, max(0, 1 - Double(remaining) / Double(planned)))
    }

    var dotsFilled: Int {
        state == .finished && phase == .work ? cycleCount + 1 : cycleCount
    }

    var statusTitle: String {
        switch state {
        case .idle: return "\(phase.title), \(planned / 60) min"
        case .running: return addedMinutes > 0 ? "\(phase.title) (+\(addedMinutes) min)" : phase.title
        case .paused: return "Paused"
        case .finished: return phase == .work ? "Block done" : "Break over"
        }
    }

    var menuStatus: String {
        switch state {
        case .idle: return "\(phase.title) ready"
        case .finished: return statusTitle
        default: return "\(statusTitle), \(Fmt.timer(remaining)) left"
        }
    }

    var primaryTitle: String {
        switch state {
        case .idle: return phase == .work ? "Start" : "Start break"
        case .running: return "Pause"
        case .paused: return "Resume"
        case .finished: return phase == .work ? "Start break" : "Start work"
        }
    }

    var secondaryTitle: String? {
        switch state {
        case .idle: return phase.isBreak ? "Skip break" : nil
        case .running, .paused: return phase.isBreak ? "Skip break" : "Stop"
        case .finished: return phase == .work ? "Skip break" : "Done"
        }
    }

    /// A finished work block can also just be stopped (saved, no break).
    var offersStop: Bool { state == .finished && phase == .work }

    /// Minutes the finished (or current) block has actually run.
    var blockMinutes: Int {
        var t = activeTime
        if state == .running, let resumed = lastResume { t += Date().timeIntervalSince(resumed) }
        return Int((t / 60).rounded())
    }

    /// The break that follows the current work block.
    var nextBreak: Phase {
        cycleCount + 1 >= Prefs.longEvery ? .longBreak : .shortBreak
    }

    var nextBreakMinutes: Int {
        nextBreak == .longBreak ? Prefs.longMinutes : Prefs.shortMinutes
    }

    // MARK: - Actions

    func primary() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .finished: startNext()
        }
    }

    func secondary() {
        switch state {
        case .idle: skip()
        case .running, .paused: if phase.isBreak { skip() } else { stop() }
        case .finished: if phase == .work { skip() } else { stop() }
        }
    }

    func start() {
        guard state == .idle else { return }
        let now = Date()
        planned = length(of: phase)
        remaining = planned
        blockStart = now
        lastResume = now
        activeTime = 0
        addedMinutes = 0
        endDate = now.addingTimeInterval(TimeInterval(planned))
        state = .running
        startTicker()
    }

    func pause() {
        guard state == .running, let end = endDate, let resumed = lastResume else { return }
        let now = Date()
        activeTime += now.timeIntervalSince(resumed)
        pausedRemaining = max(0, end.timeIntervalSince(now))
        endDate = nil
        lastResume = nil
        state = .paused
        stopTicker()
        tick()
    }

    func resume() {
        guard state == .paused else { return }
        let now = Date()
        endDate = now.addingTimeInterval(pausedRemaining)
        lastResume = now
        state = .running
        startTicker()
    }

    func extend() {
        let minutes = Prefs.extendBy
        let secs = TimeInterval(minutes * 60)
        switch state {
        case .idle:
            return
        case .running:
            endDate = endDate?.addingTimeInterval(secs)
        case .paused:
            pausedRemaining += secs
        case .finished:
            let now = Date()
            endDate = now.addingTimeInterval(secs)
            lastResume = now
            finishedAt = nil
            state = .running
            Notifier.shared.clear()
            startTicker()
        }
        addedMinutes += minutes
        planned += minutes * 60
        tick()
    }

    func startNext() {
        guard state == .finished else { return }
        commit(completed: true)
        advance()
        state = .idle
        Notifier.shared.clear()
        start()
    }

    /// Ends here. Whatever ran is saved, nothing is left running, and the timer is ready for work.
    func stop() {
        switch state {
        case .idle:
            return
        case .running, .paused:
            commit(completed: false)
        case .finished:
            commit(completed: true)
            if phase == .work { advance() }
        }
        endBreakCycleIfNeeded()
        phase = .work
        goIdle()
    }

    /// Skips the break (the one about to start, or the one running) and starts the next work block straight away.
    /// A finished work block is saved first.
    func skip() {
        switch state {
        case .finished where phase == .work:
            commit(completed: true)
            advance()
        case .finished, .running, .paused:
            guard phase.isBreak else { return }
            commit(completed: state == .finished)
        case .idle:
            guard phase.isBreak else { return }
        }
        endBreakCycleIfNeeded()
        phase = .work
        state = .idle
        stopTicker()
        Notifier.shared.clear()
        start()
    }

    /// After a long break (taken or skipped) the cycle starts again.
    private func endBreakCycleIfNeeded() {
        if phase == .longBreak { cycleCount = 0 }
    }

    func handleNotificationAction(_ id: String) {
        switch id {
        case Notifier.startNext: if state == .finished { startNext() }
        case Notifier.extend: if state == .finished { extend() }
        case Notifier.skip: if state == .finished { skip() }
        case Notifier.stop: if state == .finished { stop() }
        default: WindowOpener.shared.show("timer")
        }
    }

    /// Writes whatever is in progress to the log before the app quits.
    func prepareForQuit() {
        switch state {
        case .finished: commit(completed: true)
        case .running, .paused: commit(completed: false)
        case .idle: break
        }
    }

    // MARK: - Internals

    private func length(of p: Phase) -> Int {
        switch p {
        case .work: return Prefs.workMinutes * 60
        case .shortBreak: return Prefs.shortMinutes * 60
        case .longBreak: return Prefs.longMinutes * 60
        }
    }

    private func resetIdleDisplay() {
        planned = length(of: phase)
        remaining = planned
    }

    private func advance() {
        switch phase {
        case .work:
            cycleCount += 1
            phase = cycleCount >= Prefs.longEvery ? .longBreak : .shortBreak
        case .shortBreak:
            phase = .work
        case .longBreak:
            cycleCount = 0
            phase = .work
        }
    }

    private func goIdle() {
        state = .idle
        stopTicker()
        resetIdleDisplay()
        Notifier.shared.clear()
    }

    private func commit(completed: Bool) {
        guard let start = blockStart else { return }
        let now = Date()
        let end: Date
        if state == .finished, let f = finishedAt {
            end = f
        } else {
            if state == .running, let resumed = lastResume {
                activeTime += now.timeIntervalSince(resumed)
            }
            end = now
        }
        let secs = Int(activeTime.rounded())
        // Blocks stopped in the first minute are treated as false starts.
        if completed || secs >= 60 {
            LogStore.shared.add(LogEntry(
                label: label.trimmed,
                phase: phase,
                start: start,
                end: end,
                seconds: secs,
                completed: completed,
                addedMinutes: addedMinutes
            ))
        }
        blockStart = nil
        lastResume = nil
        endDate = nil
        finishedAt = nil
        activeTime = 0
        addedMinutes = 0
    }

    private func finish() {
        guard state == .running, let end = endDate, let resumed = lastResume else { return }
        activeTime += end.timeIntervalSince(resumed)
        finishedAt = end
        endDate = nil
        lastResume = nil
        remaining = 0
        state = .finished
        stopTicker()
        if Prefs.showsPopup {
            PopupController.shared.show()
        } else {
            Notifier.shared.blockFinished(phase: phase, label: label.trimmed)
        }
        if Prefs.playsSound { NSSound(named: "Glass")?.play() }
    }

    private func tick() {
        switch state {
        case .running:
            guard let end = endDate else { return }
            let left = end.timeIntervalSinceNow
            if left <= 0 { finish(); return }
            let secs = Int(left.rounded(.up))
            if secs != remaining { remaining = secs }
        case .paused:
            remaining = Int(pausedRemaining.rounded(.up))
        default:
            break
        }
    }

    private func startTicker() {
        stopTicker()
        tick()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
