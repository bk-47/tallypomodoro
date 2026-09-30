import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage(Prefs.Key.work) private var work = 25
    @AppStorage(Prefs.Key.shortBreak) private var shortBreak = 5
    @AppStorage(Prefs.Key.longBreak) private var longBreak = 15
    @AppStorage(Prefs.Key.longEvery) private var longEvery = 4
    @AppStorage(Prefs.Key.extend) private var extend = 5
    @AppStorage(Prefs.Key.menuSeconds) private var menuSeconds = true
    @AppStorage(Prefs.Key.alwaysOnTop) private var onTop = false
    @AppStorage(Prefs.Key.hideDock) private var hideDock = false
    @AppStorage(Prefs.Key.sound) private var sound = true
    @AppStorage(Prefs.Key.includeBreaks) private var includeBreaks = false
    @AppStorage(Prefs.Key.sheetsURL) private var sheetsURL = ""
    @AppStorage(Prefs.Key.popup) private var popup = true
    @AppStorage(Prefs.Key.redMenuBar) private var redMenuBar = false

    @ObservedObject private var sync = SheetsSync.shared

    var body: some View {
        ClassicWindow(title: "settings", id: "settings") {
            VStack(alignment: .leading, spacing: 22) {
                section("timer") {
                    stepRow("work", $work, 1...180, "min")
                    stepRow("short break", $shortBreak, 1...60, "min")
                    stepRow("long break", $longBreak, 1...90, "min")
                    stepRow("long break after", $longEvery, 2...12, "blocks")
                    stepRow("extend adds", $extend, 1...30, "min")
                }
                section("behaviour") {
                    Toggle("show seconds in the menu bar", isOn: $menuSeconds).toggleStyle(CheckboxStyle())
                    Toggle("keep the timer window on top", isOn: $onTop).toggleStyle(CheckboxStyle())
                    Toggle("hide dock icon", isOn: $hideDock).toggleStyle(CheckboxStyle())
                    Toggle("play a sound when a block ends", isOn: $sound).toggleStyle(CheckboxStyle())
                    Toggle("pop-up when a block ends (off: notification only)", isOn: $popup).toggleStyle(CheckboxStyle())
                    Toggle("red in the menu bar while working", isOn: $redMenuBar).toggleStyle(CheckboxStyle())
                }
                section("log") {
                    Toggle("include breaks in exports and sheets", isOn: $includeBreaks).toggleStyle(CheckboxStyle())
                    Button("show log file in finder") { LogStore.shared.revealInFinder() }
                        .buttonStyle(LinkButtonStyle())
                }
                section("google sheets") {
                    TextField("", text: $sheetsURL, prompt: Text("web app url"))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                    HStack(spacing: 10) {
                        Button("copy apps script") { copyScript() }
                            .buttonStyle(ClassicButtonStyle())
                        Button("test") { sync.test() }
                            .buttonStyle(ClassicButtonStyle())
                            .disabled(sheetsURL.trimmed.isEmpty)
                        Button("send full history") { sync.sendAll() }
                            .buttonStyle(ClassicButtonStyle())
                            .disabled(sheetsURL.trimmed.isEmpty)
                    }
                    if !sync.status.isEmpty {
                        Text(sync.status).font(Theme.font(11))
                    }
                    Text("leave empty to keep everything local. once set, every finished block is added to the sheet.")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
        .frame(width: 480)
        .background(WindowAccessor())
        .onChange(of: hideDock) {
            NSApp.setActivationPolicy(hideDock ? .accessory : .regular)
            DispatchQueue.main.async { NSApp.activate() }
        }
        .onChange(of: sheetsURL) { sync.flush() }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(13, bold: true))
            Rule()
            content()
        }
    }

    private func stepRow(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ unit: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
            DottedRule().frame(minWidth: 12)
            Button("-") { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }
                .buttonStyle(BoxButtonStyle())
            Text("\(value.wrappedValue) \(unit)")
                .frame(width: 84)
            Button("+") { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }
                .buttonStyle(BoxButtonStyle())
        }
    }

    private func copyScript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppsScript.source, forType: .string)
        sync.note("script copied. paste it into extensions → apps script on your sheet.")
    }
}
