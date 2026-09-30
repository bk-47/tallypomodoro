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
    @AppStorage(Prefs.Key.menuStyle) private var menuStyle = MenuStyle.plain.rawValue
    @AppStorage(Prefs.Key.keepCounting) private var keepCounting = true
    @AppStorage(Prefs.Key.miniStyle) private var miniStyle = "strip"

    @ObservedObject private var sync = SheetsSync.shared

    var body: some View {
        ClassicWindow(title: "settings", id: "settings") {
            ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("timer") {
                    stepRow("work", $work, 1...180, "min")
                    stepRow("short break", $shortBreak, 1...60, "min")
                    stepRow("long break", $longBreak, 1...90, "min")
                    stepRow("long break after", $longEvery, 2...12, "blocks")
                    stepRow("extend adds", $extend, 1...30, "min")
                }
                section("mini timer") {
                    HStack(spacing: 12) {
                        ClassicSegmented(options: ["strip", "dial"], selection: $miniStyle)
                        Text("the small timer that floats over your work. open it with the box at the top right of the timer, or ⌘3.")
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("menu bar") {
                    ClassicSegmented(options: MenuStyle.allCases.map(\.rawValue), selection: $menuStyle)
                    Toggle("show seconds", isOn: $menuSeconds).toggleStyle(CheckboxStyle())
                }
                section("behaviour") {
                    Toggle("keep the timer window on top", isOn: $onTop).toggleStyle(CheckboxStyle())
                    Toggle("hide dock icon", isOn: $hideDock).toggleStyle(CheckboxStyle())
                    Toggle("play a sound when a block ends", isOn: $sound).toggleStyle(CheckboxStyle())
                    Toggle("pop-up when a block ends (off: notification only)", isOn: $popup).toggleStyle(CheckboxStyle())
                    Toggle("keep counting when a work block ends until i respond", isOn: $keepCounting).toggleStyle(CheckboxStyle())
                    Text("stops counting after 5 minutes away from the keyboard and mouse, or if the mac sleeps.")
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 20)
                }
                section("log") {
                    Toggle("include breaks in exports and sheets", isOn: $includeBreaks).toggleStyle(CheckboxStyle())
                    Button("show log file in finder") { LogStore.shared.revealInFinder() }
                        .buttonStyle(LinkButtonStyle())
                }
                section("google sheets") {
                    step(1, "make a sheet") {
                        if let template = SheetsSetup.template {
                            Text("opens your own copy of the tally sheet, with the script and dashboard already in it. click make a copy.")
                                .modifier(Note())
                            HStack(spacing: 10) {
                                Button("make my sheet") { NSWorkspace.shared.open(template) }
                                    .buttonStyle(ClassicButtonStyle(isDefault: true))
                                Button("or use my own sheet: copy the script") { copyScript() }
                                    .buttonStyle(LinkButtonStyle())
                                    .font(Theme.font(11))
                            }
                        } else {
                            Text("make a new google sheet. go to extensions → apps script, delete what's there, paste the script and save.")
                                .modifier(Note())
                            Button("copy the script") { copyScript() }
                                .buttonStyle(ClassicButtonStyle())
                        }
                    }
                    step(2, "deploy it") {
                        Text("in the sheet: extensions → apps script. then deploy → new deployment → gear → web app. execute as: me. who has access: anyone. deploy, then allow it (advanced → go to … → allow). copy the web app url.")
                            .modifier(Note())
                    }
                    step(3, "paste the web app url") {
                        HStack(spacing: 10) {
                            TextField("", text: $sheetsURL, prompt: Text("https://script.google.com/macros/s/…/exec"))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 6)
                                .frame(height: 28)
                                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
                            Button("test") { sync.test() }
                                .buttonStyle(ClassicButtonStyle())
                                .disabled(sheetsURL.trimmed.isEmpty || sync.busy)
                        }
                    }
                    step(4, "dashboard") {
                        Text("builds itself when the first block arrives. rebuild it here any time.")
                            .modifier(Note())
                        HStack(spacing: 10) {
                            Button("build dashboard") { sync.buildDashboard() }
                                .buttonStyle(ClassicButtonStyle())
                                .disabled(sheetsURL.trimmed.isEmpty || sync.busy)
                            Button("send full history") { sync.sendAll() }
                                .buttonStyle(ClassicButtonStyle())
                                .disabled(sheetsURL.trimmed.isEmpty || sync.busy)
                            if let link = sync.sheetLink {
                                Button("open sheet") { NSWorkspace.shared.open(link) }
                                    .buttonStyle(LinkButtonStyle())
                            }
                        }
                    }
                    if !sync.status.isEmpty {
                        Text(sync.status)
                            .font(Theme.font(11))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    Text("leave the url empty to keep everything on this mac.")
                        .modifier(Note())
                }
                Text(Self.versionLine)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
            }
            .padding(22)
            }
            .frame(height: 700)
        }
        .frame(width: 500)
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

    private func step<C: View>(_ n: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(Theme.font(11, bold: true))
                .frame(width: 18, height: 18)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.font(13, bold: true))
                content()
            }
        }
        .padding(.vertical, 2)
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

    /// "tally 2.0 (build 2)", read from the app itself.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "tally \(version) (build \(build))"
    }

    private func copyScript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppsScript.source, forType: .string)
        sync.note("script copied. paste it into extensions → apps script on your sheet.")
    }
}

/// Small grey explanatory text.
private struct Note: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.font(11))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
