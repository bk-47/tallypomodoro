import SwiftUI
import AppKit
import Combine

/// A borderless panel that can take the keyboard (so Return and Esc work)
/// without pulling the whole app to the front.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows the "block done" / "break over" pop-up above everything, full-screen apps included,
/// and closes it as soon as the timer leaves the finished state (whichever button was used).
@MainActor
final class PopupController {
    static let shared = PopupController()

    private var panel: KeyablePanel?
    private var stateWatch: AnyCancellable?

    private init() {
        stateWatch = TimerEngine.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state != .finished { self?.close() }
            }
    }

    func show() {
        close()
        let hosting = NSHostingView(rootView: PopupView())
        hosting.frame.size = hosting.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .aqua)

        // Top centre of whichever screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40))
        }

        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct PopupView: View {
    @ObservedObject private var engine = TimerEngine.shared
    @AppStorage(Prefs.Key.longEvery) private var longEvery = 4
    @AppStorage(Prefs.Key.extend) private var extendBy = 5

    private var isWork: Bool { engine.phase == .work }
    private var label: String { engine.label.trimmed }

    var body: some View {
        ClassicWindow(
            title: "tally",
            id: "popup",
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 18) {
                        icon
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isWork ? "block done" : "break over")
                                .font(Theme.font(13, bold: true))
                            ForEach(lines, id: \.self) { Text($0) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)

                    buttons
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 18)

                    DottedRule().padding(.horizontal, 22)
                    Text(isWork ? "return starts the break. esc stops. both save the block."
                                : "return starts work. esc ends for now.")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
            },
            onClose: { engine.stop() }
        )
        .frame(width: 470)
    }

    @ViewBuilder
    private var icon: some View {
        if isWork {
            Rectangle().fill(Theme.ink).frame(width: 32, height: 32)
        } else {
            Rectangle().fill(Theme.dither)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                .frame(width: 32, height: 32)
        }
    }

    private var lines: [String] {
        if isWork {
            let what = label.isEmpty ? "this block" : label
            let done = engine.dotsFilled
            let next = engine.nextBreak == .longBreak ? "a long break" : "a short break"
            return [
                "\(what), \(engine.blockMinutes)m saved.",
                "\(done) of \(longEvery) done. next is \(next), \(engine.nextBreakMinutes) min.",
            ]
        } else {
            let nextBlock = min(engine.cycleCount + 1, longEvery)
            return [
                label.isEmpty ? "ready for the next block?" : "back to \(label)?",
                "next is block \(nextBlock) of \(longEvery).",
            ]
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if isWork {
                Button("stop") { engine.stop() }
                    .buttonStyle(ClassicButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("skip break") { engine.skip() }
                    .buttonStyle(ClassicButtonStyle())
                Button("+\(extendBy)") { engine.extend() }
                    .buttonStyle(ClassicButtonStyle())
                Button("start break") { engine.startNext() }
                    .buttonStyle(ClassicButtonStyle(isDefault: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("done") { engine.stop() }
                    .buttonStyle(ClassicButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("+\(extendBy)") { engine.extend() }
                    .buttonStyle(ClassicButtonStyle())
                Button("start work") { engine.startNext() }
                    .buttonStyle(ClassicButtonStyle(isDefault: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
