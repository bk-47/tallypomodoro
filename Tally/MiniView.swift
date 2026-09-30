import SwiftUI
import AppKit

/// The small timer that floats over your work: a strip or a small dial (chosen in settings).
struct MiniView: View {
    @ObservedObject private var engine = TimerEngine.shared
    @AppStorage(Prefs.Key.miniStyle) private var style = "strip"
    @AppStorage(Prefs.Key.extend) private var extendBy = 5
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if style == "dial" { dial } else { strip }
        }
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
        .padding(.top, 4)
        .padding(.leading, 4)
        .padding(.bottom, 6)
        .padding(.trailing, 6)
        .font(Theme.font(13))
        .foregroundStyle(Theme.ink)
        .textCase(.lowercase)
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
        .background(WindowAccessor(pinned: true))
        .contextMenu {
            Button("full timer") { expand() }
            Button(style == "dial" ? "switch to strip" : "switch to dial") { style = style == "dial" ? "strip" : "dial" }
            Button("close") { dismissWindow(id: "mini") }
        }
        .onAppear { WindowOpener.shared.register(openWindow) }
    }

    private func expand() {
        openWindow(id: "timer")
        dismissWindow(id: "mini")
    }

    private var labelText: String {
        let l = engine.label.trimmed
        if engine.phase.isBreak || l.isEmpty { return engine.statusTitle }
        return l
    }

    /// The readout, inverted (white on black) while a finished block keeps counting.
    private func clock(_ size: CGFloat) -> some View {
        let inverted = engine.isInOvertime
        return Text(engine.clockText)
            .font(Theme.font(size))
            .kerning(-0.5)
            .padding(.horizontal, inverted ? 4 : 0)
            .foregroundStyle(inverted ? Theme.paper : (engine.state == .paused ? Theme.muted : Theme.ink))
            .background(inverted ? Theme.ink : Color.clear)
    }

    // MARK: Strip

    private var strip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MenuGlyph(state: engine.state, phase: engine.phase)
                    .frame(width: 10, height: 10)
                clock(24)
                Text(labelText)
                    .font(Theme.font(11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { engine.primary() } label: {
                    PlayPauseGlyph(running: engine.state == .running)
                        .frame(width: 14, height: 16)
                }
                .buttonStyle(BoxButtonStyle())
                .help(engine.primaryTitle)
                if engine.state != .idle {
                    Button("+\(extendBy)") { engine.extend() }
                        .buttonStyle(BoxButtonStyle())
                        .font(Theme.font(12))
                        .help("add \(extendBy) minutes")
                }
                Button { expand() } label: {
                    ZoomGlyph().frame(width: 11, height: 11)
                }
                .buttonStyle(.plain)
                .help("full timer")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)

            progressLine
        }
        .frame(width: 300)
    }

    private var progressLine: some View {
        let p = engine.isInOvertime ? 1 : engine.progress
        return GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.paper)
                if engine.phase == .work {
                    Rectangle().fill(Theme.ink).frame(width: g.size.width * p)
                } else {
                    Rectangle().fill(Theme.dither).frame(width: g.size.width * p)
                }
            }
        }
        .frame(height: 3)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 1).offset(y: -1) }
        .padding(.horizontal, 1)
        .padding(.bottom, 1)
    }

    // MARK: Dial

    private var dial: some View {
        VStack(spacing: 0) {
            TitleBar(
                title: "tally",
                onClose: { dismissWindow(id: "mini") },
                height: 15,
                fontSize: 10,
                onZoom: { expand() }
            )
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [1, 5]))
                        .frame(width: 100, height: 100)
                    ring
                    clock(22)
                }
                .frame(width: 112, height: 112)
                Text(labelText)
                    .font(Theme.font(10))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 132)
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { engine.primary() }
            .help("click to \(engine.primaryTitle.lowercased()). right-click for more.")
        }
        .frame(width: 150)
    }

    @ViewBuilder
    private var ring: some View {
        let p = engine.isInOvertime ? 1 : engine.progress
        if engine.phase == .work {
            Circle()
                .trim(from: 0, to: p)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 6))
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 100)
        } else {
            Circle()
                .trim(from: 0, to: p)
                .stroke(Theme.dither, style: StrokeStyle(lineWidth: 6))
                .rotationEffect(.degrees(-90))
                .frame(width: 100, height: 100)
        }
    }
}
