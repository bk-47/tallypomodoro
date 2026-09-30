import SwiftUI
import AppKit

/// The menu bar item, drawn in Courier Prime and handed to macOS as a template image
/// so it goes white on a dark menu bar.
struct MenuBarLabel: View {
    @ObservedObject private var engine = TimerEngine.shared
    @AppStorage(Prefs.Key.menuSeconds) private var showSeconds = true
    @AppStorage(Prefs.Key.menuStyle) private var style = MenuStyle.plain.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: rendered)
            .onAppear { WindowOpener.shared.register(openWindow) }
    }

    private var text: String {
        switch engine.state {
        case .idle: return ""
        case .finished:
            if engine.isInOvertime {
                return showSeconds ? "+" + Fmt.timer(engine.overtime) : "+\(engine.overtime / 60)m"
            }
            return "done"
        default:
            if showSeconds { return Fmt.timer(engine.remaining) }
            return "\(Int((Double(engine.remaining) / 60).rounded(.up)))m"
        }
    }

    private var rendered: NSImage {
        let content = HStack(spacing: 5) {
            MenuGlyph(state: engine.state, phase: engine.phase)
                .frame(width: 9, height: 9)
            if !text.isEmpty {
                MenuTime(text: text, style: MenuStyle(rawValue: style) ?? .plain)
            }
        }
        .foregroundStyle(Color.black)
        .frame(height: 18)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 16, height: 16))
        // A template image: macOS draws it black on a light menu bar and white on a dark one.
        image.isTemplate = true
        return image
    }
}

enum MenuStyle: String, CaseIterable {
    case plain, outline, shadow, solid

    var title: String {
        switch self {
        case .plain: return "plain"
        case .outline: return "outline"
        case .shadow: return "shadow"
        case .solid: return "solid"
        }
    }
}

/// The time in the menu bar, plain or in a box. Everything is drawn in one colour with
/// cut-outs (not white), so macOS can flip it for a dark menu bar.
struct MenuTime: View {
    let text: String
    let style: MenuStyle

    var body: some View {
        let label = Text(text).font(Theme.font(13)).padding(.horizontal, 4)
        switch style {
        case .plain:
            Text(text).font(Theme.font(14))
        case .outline:
            label
                .frame(height: 16)
                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
        case .shadow:
            label
                .frame(height: 15)
                .background {
                    ZStack {
                        Rectangle().fill(Color.black).offset(x: 2, y: 2)
                        Rectangle().fill(Color.black).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1))
                .padding(.trailing, 2)
                .padding(.bottom, 2)
        case .solid:
            ZStack {
                Rectangle().fill(Color.black)
                label.blendMode(.destinationOut)
            }
            .compositingGroup()
            .fixedSize(horizontal: false, vertical: false)
            .frame(height: 16)
        }
    }
}

/// Idle: hollow square. Work: solid. Break: dithered. Paused: two bars.
struct MenuGlyph: View {
    let state: RunState
    let phase: Phase

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            switch state {
            case .idle:
                ctx.stroke(Path(r.insetBy(dx: 0.5, dy: 0.5)), with: .foreground, lineWidth: 1)
            case .paused:
                ctx.fill(Path(CGRect(x: 1, y: 0, width: 2.5, height: size.height)), with: .foreground)
                ctx.fill(Path(CGRect(x: size.width - 3.5, y: 0, width: 2.5, height: size.height)), with: .foreground)
            case .running where phase.isBreak:
                for x in 0..<Int(size.width) {
                    for y in 0..<Int(size.height) where (x + y) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .foreground)
                    }
                }
                ctx.stroke(Path(r.insetBy(dx: 0.5, dy: 0.5)), with: .foreground, lineWidth: 1)
            default:
                ctx.fill(Path(r), with: .foreground)
            }
        }
    }
}

/// The panel that opens from the menu bar. Timer actions leave it open so you can see the change;
/// opening a window closes it.
struct MenuContent: View {
    @ObservedObject private var engine = TimerEngine.shared
    @ObservedObject private var store = LogStore.shared
    @AppStorage(Prefs.Key.extend) private var extendBy = 5
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuPanel {
            Group {
                MenuInfo(text: engine.menuStatus)
                if !engine.label.trimmed.isEmpty {
                    MenuInfo(text: engine.label.trimmed)
                }
                MenuDivider()
                MenuRow(title: engine.primaryTitle) { engine.primary() }
                if engine.state != .idle {
                    MenuRow(title: "add \(extendBy) min") { engine.extend() }
                }
                if let title = engine.secondaryTitle {
                    MenuRow(title: title) { engine.secondary() }
                }
                if engine.offersStop {
                    MenuRow(title: "stop") { engine.stop() }
                }
            }
            Group {
                MenuDivider()
                MenuInfo(text: "today: \(store.todayPomodoros) done, \(store.todayMinutes.hoursMinutes)")
                MenuDivider()
                MenuRow(title: "show timer", detail: "⌘1") { show("timer") }
                MenuRow(title: "mini timer", detail: "⌘3") { show("mini") }
                MenuRow(title: "stats", detail: "⌘2") { show("stats") }
                MenuRow(title: "settings…", detail: "⌘,") { show("settings") }
                MenuDivider()
                MenuRow(title: "quit tally", detail: "⌘q") { NSApp.terminate(nil) }
            }
        }
        .frame(width: 250)
        .padding(10)
        .background(Theme.paper)
        .font(Theme.font(13))
        .foregroundStyle(Theme.ink)
        .textCase(.lowercase)
        .environment(\.colorScheme, .light)
    }

    private func show(_ id: String) {
        NSApp.activate()
        openWindow(id: id)
    }
}
