import SwiftUI
import AppKit
import CoreText

/// Black on white, Courier Prime, lower case. The only "grey" is the dither pattern and muted info text.
enum Theme {
    static let ink = Color.black
    static let paper = Color.white
    static let muted = Color(white: 0.33)

    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "CourierPrime-Bold" : "CourierPrime-Regular", size: size)
    }

    static func registerFonts() {
        for name in ["CourierPrime-Regular", "CourierPrime-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    /// 2×2 checkerboard, the old Mac 50% grey. Used for breaks.
    static let dither: ImagePaint = {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 2, height: 2).fill()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            NSRect(x: 1, y: 1, width: 1, height: 1).fill()
            return true
        }
        return ImagePaint(image: Image(nsImage: image), scale: 1)
    }()
}

// MARK: - Window chrome

/// Square window with a striped title bar, a close box and a hard shadow.
struct ClassicWindow<Content: View>: View {
    let title: String
    let id: String
    @ViewBuilder var content: () -> Content
    var onClose: (() -> Void)? = nil
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: title) {
                if let onClose { onClose() } else { dismissWindow(id: id) }
            }
            content()
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
    }
}

struct TitleBar: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                var y: CGFloat = 4
                while y < 16 {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black))
                    y += 2
                }
            }
            HStack {
                Button(action: onClose) {
                    Rectangle()
                        .strokeBorder(Theme.ink, lineWidth: 1)
                        .background(Theme.paper)
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(.plain)
                .padding(2)
                .background(Theme.paper)
                .help("close")
                Spacer()
            }
            .padding(.horizontal, 6)
            Text(title)
                .font(Theme.font(13, bold: true))
                .padding(.horizontal, 8)
                .background(Theme.paper)
        }
        .frame(height: 20)
        .overlay(alignment: .bottom) { Rule() }
    }
}

// MARK: - Lines

struct HLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

struct Rule: View {
    var body: some View { Rectangle().fill(Theme.ink).frame(height: 1) }
}

struct DottedRule: View {
    var body: some View {
        HLine()
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
            .frame(height: 1)
    }
}

/// Small downward triangle (Courier Prime has no ▾).
struct DownArrow: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 7, y: 0))
            p.addLine(to: CGPoint(x: 3.5, y: 4))
            p.closeSubpath()
        }
        .frame(width: 7, height: 4)
    }
}

/// ⌐ ¬ shaped bracket under a run of blocks.
struct Bracket: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 0.5, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + 0.5, y: r.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
        p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.minY))
        return p
    }
}

// MARK: - Buttons and toggles

/// Rounded push button. The default one gets the thick outer ring.
struct ClassicButtonStyle: ButtonStyle {
    var isDefault = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.font(13))
            .foregroundStyle(pressed ? Theme.paper : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(pressed ? Theme.ink : Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 1))
            .padding(isDefault ? 4 : 0)
            .overlay {
                if isDefault {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.ink, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
    }
}

/// Small square-ish button, used for < > and - +.
struct BoxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(pressed ? Theme.paper : Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(pressed ? Theme.ink : Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .underline()
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

/// Square checkbox with an X, like System 7.
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().strokeBorder(Theme.ink, lineWidth: 1).background(Theme.paper)
                    if configuration.isOn {
                        Path { p in
                            p.move(to: CGPoint(x: 2, y: 2)); p.addLine(to: CGPoint(x: 10, y: 10))
                            p.move(to: CGPoint(x: 10, y: 2)); p.addLine(to: CGPoint(x: 2, y: 10))
                        }
                        .stroke(Theme.ink, lineWidth: 1)
                    }
                }
                .frame(width: 12, height: 12)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menus

struct MenuPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 4)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            .background(Rectangle().fill(Theme.ink).offset(x: 2, y: 2))
    }
}

/// A menu item that inverts on hover.
struct MenuRow: View {
    let title: String
    var detail: String = ""
    var checked: Bool? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let checked {
                    Text(checked ? "✓" : " ").frame(width: 14, alignment: .leading)
                }
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 16)
                if !detail.isEmpty { Text(detail) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .foregroundStyle(hover ? Theme.paper : Theme.ink)
            .background(hover ? Theme.ink : Theme.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct MenuInfo: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuDivider: View {
    var body: some View { DottedRule().padding(.vertical, 4) }
}

// MARK: - Window plumbing

/// Lets non-view code (notifications, the Dock icon) open a SwiftUI window.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    private var action: OpenWindowAction?

    func register(_ action: OpenWindowAction) { self.action = action }

    func show(_ id: String) {
        NSApp.activate()
        action?.callAsFunction(id: id)
    }
}

/// Strips the system window chrome so ClassicWindow can draw its own.
struct WindowAccessor: NSViewRepresentable {
    var floats = false
    @AppStorage(Prefs.Key.alwaysOnTop) private var onTop = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(view.window) }
    }

    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        if floats { window.level = onTop ? .floating : .normal }
    }
}
