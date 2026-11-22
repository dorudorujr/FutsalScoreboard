import SwiftUI

enum TeamColor: String, Codable, CaseIterable, Identifiable {
    case red, blue, yellow, green, orange, white, black, pink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: "赤"
        case .blue: "青"
        case .yellow: "黄"
        case .green: "緑"
        case .orange: "オレンジ"
        case .white: "白"
        case .black: "黒"
        case .pink: "ピンク"
        }
    }

    var background: Color {
        switch self {
        case .red: Color(red: 0.85, green: 0.15, blue: 0.20)
        case .blue: Color(red: 0.10, green: 0.35, blue: 0.85)
        case .yellow: Color(red: 1.00, green: 0.85, blue: 0.10)
        case .green: Color(red: 0.10, green: 0.62, blue: 0.30)
        case .orange: Color(red: 1.00, green: 0.50, blue: 0.05)
        case .white: Color(red: 0.95, green: 0.95, blue: 0.95)
        case .black: Color(red: 0.12, green: 0.12, blue: 0.12)
        case .pink: Color(red: 1.00, green: 0.42, blue: 0.66)
        }
    }

    /// 背景色の上で読みやすい文字色
    var foreground: Color {
        switch self {
        case .yellow, .white: .black
        default: .white
        }
    }
}

struct TeamConfig: Codable, Equatable {
    var name: String
    var color: TeamColor
}

struct MatchSettings: Codable, Equatable {
    static let nameLimit = 8
    /// 試合時間(1 ハーフ)の範囲。1 秒〜40 分
    static let secondsRange = 1...(40 * 60)
    static let defaultHomeName = "チームA"
    static let defaultAwayName = "チームB"

    var home = TeamConfig(name: defaultHomeName, color: .blue)
    var away = TeamConfig(name: defaultAwayName, color: .red)
    var periodSeconds = 7 * 60
    /// 終了の何秒前に予告音を鳴らすか。0 なら鳴らさない。halfWarning なら試合時間の半分
    var warningSeconds = 60

    /// 「半分」を表す特別な値
    static let halfWarning = -1
    /// 予告のタイミングの選択肢(秒)。0 は「なし」、halfWarning は「半分」
    static let warningChoices = [0, halfWarning, 10, 15, 30, 45, 60, 90, 120, 180, 300]

    /// 実際に何秒前に予告するか
    var warningLeadSeconds: Int {
        warningSeconds == Self.halfWarning ? periodSeconds / 2 : max(0, warningSeconds)
    }

    /// 設定画面の選択肢の表示
    static func warningChoiceLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: "なし"
        case halfWarning: "半分"
        default: "残り\(label(seconds: seconds))"
        }
    }

    /// 予告の通知のタイトル
    var warningNotificationTitle: String {
        warningSeconds == Self.halfWarning
            ? "半分経過(残り\(Self.label(seconds: warningLeadSeconds)))"
            : "残り\(Self.label(seconds: warningLeadSeconds))"
    }

    var periodDuration: TimeInterval { TimeInterval(periodSeconds) }

    init() {}

    /// 保存前に入力値を仕様の範囲に収める
    func normalized() -> MatchSettings {
        var s = self
        s.home.name = Self.clean(s.home.name, fallback: Self.defaultHomeName)
        s.away.name = Self.clean(s.away.name, fallback: Self.defaultAwayName)
        s.periodSeconds = Self.clampSeconds(s.periodSeconds)
        if s.warningSeconds != Self.halfWarning { s.warningSeconds = max(0, s.warningSeconds) }
        return s
    }

    static func clampSeconds(_ seconds: Int) -> Int {
        min(max(seconds, secondsRange.lowerBound), secondsRange.upperBound)
    }

    /// 「7分」「7分30秒」「45秒」の形にする
    static func label(seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        switch (m, s) {
        case (0, _): return "\(s)秒"
        case (_, 0): return "\(m)分"
        default: return "\(m)分\(s)秒"
        }
    }

    // MARK: - Codable(分単位で保存していた旧データも読めるようにする)

    private enum CodingKeys: String, CodingKey {
        case home, away, periodSeconds, periodMinutes, warningSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        home = try c.decodeIfPresent(TeamConfig.self, forKey: .home) ?? home
        away = try c.decodeIfPresent(TeamConfig.self, forKey: .away) ?? away
        if let seconds = try c.decodeIfPresent(Int.self, forKey: .periodSeconds) {
            periodSeconds = seconds
        } else if let minutes = try c.decodeIfPresent(Int.self, forKey: .periodMinutes) {
            periodSeconds = minutes * 60
        }
        warningSeconds = try c.decodeIfPresent(Int.self, forKey: .warningSeconds) ?? warningSeconds
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(home, forKey: .home)
        try c.encode(away, forKey: .away)
        try c.encode(periodSeconds, forKey: .periodSeconds)
        try c.encode(warningSeconds, forKey: .warningSeconds)
    }

    private static func clean(_ name: String, fallback: String) -> String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return trimmed.isEmpty ? fallback : trimmed
    }
}
