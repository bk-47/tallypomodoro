import SwiftUI
import AppKit

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        Window("tally", id: "timer") {
            TimerView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenWindowButton(title: "settings…", id: "settings", key: ",") }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowArrangement) {
                OpenWindowButton(title: "timer", id: "timer", key: "1")
                OpenWindowButton(title: "stats", id: "stats", key: "2")
            }
        }

        Window("tally stats", id: "stats") {
            StatsView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 660)

        Window("settings", id: "settings") {
            SettingsView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct OpenWindowButton: View {
    let title: String
    let id: String
    let key: KeyEquivalent
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: id) }
            .keyboardShortcut(key, modifiers: .command)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Prefs.bool(Prefs.Key.hideDock, false) {
            NSApp.setActivationPolicy(.accessory)
        }
        Notifier.shared.setup()
        SheetsSync.shared.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.shared.show("timer") }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TimerEngine.shared.prepareForQuit()
    }
}
