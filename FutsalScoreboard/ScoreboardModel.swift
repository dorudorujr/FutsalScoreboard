import Foundation
import Observation

/// 画面とつなぐ層。Match の操作に、保存・音・通知・連打防止を足す
@MainActor
@Observable
final class ScoreboardModel {
    private static let settingsKey = "settings.v1"
    private static let matchKey = "match.v1"
    /// 0.3 秒以内の連打は誤タップとみなす
    private static let tapDebounce: TimeInterval = 0.3
    /// これより古いイベント(バックグラウンド中に起きたもの)は鳴らさない。通知側で鳴っている
    private static let staleEventLimit: TimeInterval = 2

    private(set) var settings: MatchSettings
    private(set) var match: Match
    private(set) var now = Date()

    @ObservationIgnored private var lastTap: [Team: Date] = [:]
    @ObservationIgnored private let alerts = AlertPlayer()
    @ObservationIgnored private let notifications = NotificationScheduler()
    @ObservationIgnored private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        let settings = Self.load(MatchSettings.self, key: Self.settingsKey, from: store) ?? MatchSettings()
        self.settings = settings
        var match = Self.load(Match.self, key: Self.matchKey, from: store) ?? Match(periodDuration: settings.periodDuration)
        match.setWarningLead(TimeInterval(settings.warningLeadSeconds))
        self.match = match
        tick()
    }

    var remaining: TimeInterval { match.remaining(at: now) }

    // MARK: - 得点

    func addScore(_ team: Team) {
        let t = Date()
        if let last = lastTap[team], t.timeIntervalSince(last) < Self.tapDebounce { return }
        lastTap[team] = t
        match.addScore(team)
        saveMatch()
    }

    func subtractScore(_ team: Team) {
        match.subtractScore(team)
        saveMatch()
    }

    // MARK: - タイマー

    func toggleClock() {
        let t = Date()
        now = t
        handle(match.toggleClock(now: t), at: t)
        clockChanged()
    }

    func tick(_ date: Date = Date()) {
        // 止まっている間は残り時間が変わらないので、画面を描き直さない
        // (0.1 秒ごとの再描画がシートのホイール操作を邪魔するのを防ぐ)
        guard match.isRunning else { return }
        now = date
        let events = match.tick(now: date)
        guard !events.isEmpty else { return }
        handle(events, at: date)
        saveMatch()
    }

    /// タイマー表示から時間を変える。未開始なら試合時間そのものを変え、途中なら今の残り時間だけ変える
    func setClockTime(seconds: Int) {
        guard !match.isRunning else { return }
        let value = MatchSettings.clampSeconds(seconds)
        if match.isUntouched {
            var newSettings = settings
            newSettings.periodSeconds = value
            updateSettings(newSettings)
        } else {
            match.setRemaining(TimeInterval(value))
            clockChanged()
        }
    }

    func resetClock() {
        match.resetClock()
        clockChanged()
    }

    func startNewMatch() {
        match.startNewMatch()
        clockChanged()
    }

    // MARK: - 設定

    func updateSettings(_ newValue: MatchSettings) {
        settings = newValue.normalized()
        match.setPeriodDuration(settings.periodDuration)
        match.setWarningLead(TimeInterval(settings.warningLeadSeconds))
        save(settings, key: Self.settingsKey)
        saveMatch()
    }

    // MARK: - private

    private func handle(_ events: [ClockEvent], at date: Date) {
        let fresh = events.filter { date.timeIntervalSince($0.date) < Self.staleEventLimit }
        if fresh.contains(where: { $0.kind == .expired }) {
            alerts.playEnd()
        } else if fresh.contains(where: { $0.kind == .warning }) {
            alerts.playWarning()
        }
    }

    private func clockChanged() {
        if case .running(let end) = match.clock {
            notifications.update(warningAt: match.pendingWarningDate,
                                 warningTitle: settings.warningNotificationTitle,
                                 endAt: end)
        } else {
            notifications.update(warningAt: nil, warningTitle: "", endAt: nil)
        }
        saveMatch()
    }

    private func saveMatch() {
        save(match, key: Self.matchKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            store.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from store: UserDefaults) -> T? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
