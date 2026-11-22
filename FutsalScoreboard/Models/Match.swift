import Foundation

enum Team: String, Codable, CaseIterable {
    case home, away
}

enum Clock: Codable, Equatable {
    case ready(remaining: TimeInterval)
    case running(endDate: Date)
    case paused(remaining: TimeInterval)
    case expired
}

struct ClockEvent: Equatable {
    enum Kind: Equatable { case warning, expired }
    let kind: Kind
    /// イベントが本来起きた時刻(バックグラウンド復帰時に古い音を鳴らさない判定に使う)
    let date: Date
}

/// 1 試合の状態と操作。時刻は引数で受け取り、副作用(音・通知・保存)は持たない。
struct Match: Codable, Equatable {
    static let maxScore = 99
    static let defaultWarningLead: TimeInterval = 60

    private(set) var homeScore = 0
    private(set) var awayScore = 0
    private(set) var clock: Clock
    private(set) var periodDuration: TimeInterval
    private(set) var warningFired = false
    /// 終了の何秒前に予告するか。0 なら予告しない。nil は旧データ(既定の 60 秒)
    private var warningLeadValue: TimeInterval?

    var warningLead: TimeInterval { warningLeadValue ?? Self.defaultWarningLead }

    init(periodDuration: TimeInterval, warningLead: TimeInterval = Match.defaultWarningLead) {
        self.periodDuration = periodDuration
        self.warningLeadValue = warningLead
        self.clock = .ready(remaining: periodDuration)
    }

    // MARK: - 参照

    func score(for team: Team) -> Int {
        team == .home ? homeScore : awayScore
    }

    func remaining(at now: Date) -> TimeInterval {
        switch clock {
        case .ready(let r), .paused(let r): r
        case .running(let end): max(0, end.timeIntervalSince(now))
        case .expired: 0
        }
    }

    var isRunning: Bool {
        if case .running = clock { return true }
        return false
    }

    var isExpired: Bool { clock == .expired }

    /// まだ一度も開始していない(試合時間いっぱいの)状態か
    var isUntouched: Bool { clock == .ready(remaining: periodDuration) }

    /// 予約すべき「残り 1 分」通知の時刻。鳴らす必要がなければ nil
    var pendingWarningDate: Date? {
        guard case .running(let end) = clock, !warningFired, warningLead > 0 else { return nil }
        return end.addingTimeInterval(-warningLead)
    }

    // MARK: - 得点

    mutating func addScore(_ team: Team) {
        setScore(team, score(for: team) + 1)
    }

    mutating func subtractScore(_ team: Team) {
        setScore(team, score(for: team) - 1)
    }

    private mutating func setScore(_ team: Team, _ value: Int) {
        let clamped = min(max(value, 0), Self.maxScore)
        switch team {
        case .home: homeScore = clamped
        case .away: awayScore = clamped
        }
    }

    // MARK: - タイマー

    /// 開始と停止を切り替える。停止前に tick して、取りこぼしたイベントを返す
    @discardableResult
    mutating func toggleClock(now: Date) -> [ClockEvent] {
        switch clock {
        case .ready(let r), .paused(let r):
            guard r > 0 else { clock = .expired; return [] }
            // 予告なしの設定か、予告の時間を切ってから開始したときは予告しない
            warningFired = warningLead <= 0 || r <= warningLead
            clock = .running(endDate: now.addingTimeInterval(r))
            return []
        case .running:
            let events = tick(now: now)
            if case .running(let end) = clock {
                clock = .paused(remaining: end.timeIntervalSince(now))
            }
            return events
        case .expired:
            return []
        }
    }

    /// 時間経過を反映し、起きたイベントを返す
    mutating func tick(now: Date) -> [ClockEvent] {
        guard case .running(let end) = clock else { return [] }
        var events: [ClockEvent] = []
        let warningDate = end.addingTimeInterval(-warningLead)
        if !warningFired, now >= warningDate {
            warningFired = true
            events.append(ClockEvent(kind: .warning, date: warningDate))
        }
        if now >= end {
            clock = .expired
            events.append(ClockEvent(kind: .expired, date: end))
        }
        return events
    }

    /// 止まっているタイマーの残り時間を手で変える(動作中は何もしない)
    mutating func setRemaining(_ remaining: TimeInterval) {
        guard !isRunning, remaining > 0 else { return }
        clock = .paused(remaining: remaining)
    }

    /// 予告のタイミングを変える。次に開始したときから反映する
    mutating func setWarningLead(_ lead: TimeInterval) {
        warningLeadValue = max(0, lead)
    }

    mutating func resetClock() {
        clock = .ready(remaining: periodDuration)
        warningFired = false
    }

    mutating func startNewMatch() {
        homeScore = 0
        awayScore = 0
        resetClock()
    }

    /// 試合時間の変更。未開始(満タン)ならすぐ反映し、途中なら次にタイマーを戻したときから反映する
    mutating func setPeriodDuration(_ duration: TimeInterval) {
        let wasUntouched = isUntouched
        periodDuration = duration
        if wasUntouched {
            clock = .ready(remaining: duration)
        }
    }
}
