import UserNotifications

/// アプリがバックグラウンドにあるときのための「予告」「終了」通知
@MainActor
final class NotificationScheduler {
    private static let warningID = "fsb.warning"
    private static let endID = "fsb.end"

    private struct Plan: Equatable {
        let warningAt: Date?
        let warningTitle: String
        let endAt: Date
    }

    private let center = UNUserNotificationCenter.current()
    private var plan: Plan?
    private var authorizationRequested = false

    /// タイマーの状態が変わるたびに呼ぶ。endAt が nil なら予約をすべて取り消す
    func update(warningAt: Date?, warningTitle: String, endAt: Date?) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.warningID, Self.endID])
        guard let endAt else { plan = nil; return }
        let newPlan = Plan(warningAt: warningAt, warningTitle: warningTitle, endAt: endAt)
        plan = newPlan
        Task {
            await requestAuthorizationIfNeeded()
            // 許可ダイアログの間にタイマーが止められていたら予約しない
            guard plan == newPlan else { return }
            schedule(newPlan)
        }
    }

    private func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func schedule(_ plan: Plan) {
        if let warningAt = plan.warningAt {
            add(id: Self.warningID, at: warningAt, title: plan.warningTitle, sound: AlertPlayer.warningFileName)
        }
        add(id: Self.endID, at: plan.endAt, title: "試合終了", sound: AlertPlayer.endFileName)
    }

    private func add(id: String, at date: Date, title: String, sound: String) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0.5 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
