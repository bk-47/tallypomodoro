import Foundation
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static let startNext = "START_NEXT"
    static let extend = "EXTEND"
    static let skip = "SKIP"
    static let stop = "STOP"

    private static let workDone = "WORK_DONE"
    private static let breakDone = "BREAK_DONE"
    private static let requestID = "tally.finished"

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let extendTitle = "+\(Prefs.extendBy) min"
        let workDone = UNNotificationCategory(
            identifier: Self.workDone,
            actions: [
                UNNotificationAction(identifier: Self.startNext, title: "start break"),
                UNNotificationAction(identifier: Self.extend, title: extendTitle),
                UNNotificationAction(identifier: Self.skip, title: "skip break"),
                UNNotificationAction(identifier: Self.stop, title: "stop"),
            ],
            intentIdentifiers: []
        )
        let breakDone = UNNotificationCategory(
            identifier: Self.breakDone,
            actions: [
                UNNotificationAction(identifier: Self.startNext, title: "start work"),
                UNNotificationAction(identifier: Self.extend, title: extendTitle),
                UNNotificationAction(identifier: Self.stop, title: "done"),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([workDone, breakDone])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func blockFinished(phase: Phase, label: String) {
        let content = UNMutableNotificationContent()
        if phase == .work {
            content.title = "block done"
            content.body = label.isEmpty ? "time for a break." : "\(label). time for a break."
            content.categoryIdentifier = Self.workDone
        } else {
            content.title = "break over"
            content.body = label.isEmpty ? "start the next block when you're ready." : "back to \(label)?"
            content.categoryIdentifier = Self.breakDone
        }
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            TimerEngine.shared.handleNotificationAction(action)
        }
        completionHandler()
    }
}
