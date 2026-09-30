import SwiftUI
import AppKit

struct TimerView: View {
    @ObservedObject private var engine = TimerEngine.shared
    @ObservedObject private var store = LogStore.shared
    @AppStorage(Prefs.Key.longEvery) private var longEvery = 4
    @AppStorage(Prefs.Key.extend) private var extendBy = 5
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ClassicWindow(title: "tally", id: "timer", content: {
            VStack(spacing: 18) {
                Text(engine.statusTitle)
                dial
                LabelField(label: $engine.label, suggestions: store.recentLabels)
                    .zIndex(1)
                controls
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)
        }, onZoom: {
            openWindow(id: "mini")
            dismissWindow(id: "timer")
        })
        .frame(width: 308)
        .background(WindowAccessor(floats: true))
        .onAppear { WindowOpener.shared.register(openWindow) }
    }

    private var dial: some View {
        let p = engine.progress
        return ZStack {
            Circle()
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [1, 5]))
                .frame(width: 184, height: 184)
            if engine.phase == .work {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 8))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 184, height: 184)
            } else {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Theme.dither, style: StrokeStyle(lineWidth: 8))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 184, height: 184)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Theme.ink, lineWidth: 1)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 176, height: 176)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Theme.ink, lineWidth: 1)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 192, height: 192)
            }
            VStack(spacing: 14) {
                Text(engine.clockText)
                    .font(Theme.font(52))
                    .kerning(-1)
                    .foregroundStyle(engine.state == .paused ? Theme.muted : Theme.ink)
                CycleSquares(filled: engine.dotsFilled, total: longEvery)
            }
        }
        .frame(width: 196, height: 196)
        .animation(.linear(duration: 0.3), value: p)
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button(engine.primaryTitle) { engine.primary() }
                    .buttonStyle(ClassicButtonStyle(isDefault: true))
                if engine.state != .idle {
                    Button("+\(extendBy)") { engine.extend() }
                        .buttonStyle(ClassicButtonStyle())
                        .help("add \(extendBy) minutes to this block")
                }
                if let title = engine.secondaryTitle {
                    Button(title) { engine.secondary() }
                        .buttonStyle(ClassicButtonStyle())
                }
            }
            // Space is always kept so the window doesn't jump when this appears.
            Button("or stop here") { engine.stop() }
                .buttonStyle(LinkButtonStyle())
                .font(Theme.font(11))
                .opacity(engine.offersStop ? 1 : 0)
                .disabled(!engine.offersStop)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rule()
            HStack {
                Button("stats") { openWindow(id: "stats") }
                    .buttonStyle(LinkButtonStyle())
                Spacer()
                Text("\(store.todayPomodoros) done today, \(store.todayMinutes.hoursMinutes)")
                Spacer()
                Button("settings") { openWindow(id: "settings") }
                    .buttonStyle(LinkButtonStyle())
            }
            .font(Theme.font(11))
        }
    }
}

struct CycleSquares: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? Theme.ink : Theme.paper)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// Free text, always lower case, with recent labels offered as you type (or from the arrow).
struct LabelField: View {
    @Binding var label: String
    let suggestions: [String]

    @State private var open = false
    @State private var ignoreNextChange = false
    @FocusState private var focused: Bool

    private var matches: [String] {
        let q = label.trimmed.lowercased()
        let list = q.isEmpty
            ? suggestions
            : suggestions.filter { $0.lowercased().contains(q) && $0.lowercased() != q }
        return Array(list.prefix(6))
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $label, prompt: Text("what's this block for?"))
                .textFieldStyle(.plain)
                .font(Theme.font(13))
                .padding(.horizontal, 8)
                .focused($focused)
                .onSubmit { open = false; focused = false }
            if !suggestions.isEmpty {
                Button { open.toggle() } label: {
                    DownArrow()
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.ink).frame(width: 1) }
                .help("recent labels")
            }
        }
        .frame(height: 32)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if open && !matches.isEmpty {
                MenuPanel {
                    ForEach(matches, id: \.self) { s in
                        MenuRow(title: s) { pick(s) }
                    }
                }
                .offset(y: 36)
            }
        }
        .onChange(of: label) {
            let lower = label.lowercased()
            if lower != label { label = lower; return }
            if ignoreNextChange { ignoreNextChange = false } else if focused { open = true }
        }
        .onChange(of: focused) {
            if !focused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { open = false }
            }
        }
    }

    private func pick(_ s: String) {
        if label != s {
            ignoreNextChange = true
            label = s
        }
        open = false
        focused = false
    }
}
