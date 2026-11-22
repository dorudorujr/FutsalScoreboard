import XCTest
@testable import FutsalScoreboard

final class MatchScoreTests: XCTestCase {
    func testAddAndSubtract() {
        var m = Match(periodDuration: 420)
        m.addScore(.home)
        m.addScore(.home)
        m.addScore(.away)
        m.subtractScore(.home)
        XCTAssertEqual(m.homeScore, 1)
        XCTAssertEqual(m.awayScore, 1)
    }

    func testScoreIsClamped() {
        var m = Match(periodDuration: 420)
        m.subtractScore(.home)
        XCTAssertEqual(m.homeScore, 0)

        for _ in 0..<120 { m.addScore(.away) }
        XCTAssertEqual(m.awayScore, Match.maxScore)
    }
}

final class MatchClockTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartPauseResumeKeepsRemaining() {
        var m = Match(periodDuration: 420)
        m.toggleClock(now: t0)
        XCTAssertEqual(m.remaining(at: t0 + 10), 410, accuracy: 0.001)

        m.toggleClock(now: t0 + 10) // 停止
        XCTAssertEqual(m.clock, .paused(remaining: 410))
        XCTAssertEqual(m.remaining(at: t0 + 100), 410, accuracy: 0.001, "停止中は減らない")

        m.toggleClock(now: t0 + 100) // 再開
        XCTAssertEqual(m.remaining(at: t0 + 110), 400, accuracy: 0.001)
    }

    func testWarningThenExpiry() {
        var m = Match(periodDuration: 120)
        m.toggleClock(now: t0)
        XCTAssertEqual(m.pendingWarningDate, t0 + 60)

        XCTAssertEqual(m.tick(now: t0 + 59), [])
        XCTAssertEqual(m.tick(now: t0 + 60.05), [ClockEvent(kind: .warning, date: t0 + 60)])
        XCTAssertEqual(m.tick(now: t0 + 61), [], "予告は 1 回だけ")
        XCTAssertNil(m.pendingWarningDate)

        XCTAssertEqual(m.tick(now: t0 + 120.1), [ClockEvent(kind: .expired, date: t0 + 120)])
        XCTAssertTrue(m.isExpired)
        XCTAssertEqual(m.remaining(at: t0 + 200), 0)
    }

    func testNoWarningWhenStartedUnderOneMinute() {
        var m = Match(periodDuration: 45)
        m.toggleClock(now: t0)
        XCTAssertNil(m.pendingWarningDate)
        XCTAssertEqual(m.tick(now: t0 + 50), [ClockEvent(kind: .expired, date: t0 + 45)])
    }

    func testResumeAfterPauseAboveOneMinuteStillWarns() {
        var m = Match(periodDuration: 120)
        m.toggleClock(now: t0)
        m.toggleClock(now: t0 + 50) // 残り 70 で停止
        m.toggleClock(now: t0 + 500) // 再開
        XCTAssertEqual(m.tick(now: t0 + 511), [ClockEvent(kind: .warning, date: t0 + 510)])
    }

    func testPausingCatchesMissedWarning() {
        var m = Match(periodDuration: 120)
        m.toggleClock(now: t0)
        // tick が走る前に残り 59 秒で停止
        let events = m.toggleClock(now: t0 + 61)
        XCTAssertEqual(events.map(\.kind), [.warning])
        XCTAssertEqual(m.clock, .paused(remaining: 59))
    }

    func testCustomWarningLead() {
        var m = Match(periodDuration: 300, warningLead: 120)
        m.toggleClock(now: t0)
        XCTAssertEqual(m.pendingWarningDate, t0 + 180)
        XCTAssertEqual(m.tick(now: t0 + 179), [])
        XCTAssertEqual(m.tick(now: t0 + 180), [ClockEvent(kind: .warning, date: t0 + 180)])
    }

    func testWarningOff() {
        var m = Match(periodDuration: 120, warningLead: 0)
        m.toggleClock(now: t0)
        XCTAssertNil(m.pendingWarningDate)
        XCTAssertEqual(m.tick(now: t0 + 200), [ClockEvent(kind: .expired, date: t0 + 120)])
    }

    func testChangingWarningLeadAppliesOnNextStart() {
        var m = Match(periodDuration: 300)
        m.setWarningLead(30)
        m.toggleClock(now: t0)
        XCTAssertEqual(m.pendingWarningDate, t0 + 270)
    }

    func testLegacyMatchWithoutWarningLeadDefaultsToOneMinute() throws {
        var m = Match(periodDuration: 120)
        m.toggleClock(now: t0)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as! [String: Any]
        json.removeValue(forKey: "warningLeadValue")
        let legacy = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.warningLead, 60)
    }

    func testCatchUpAfterBackgroundReturnsBothEventsWithOriginalDates() {
        var m = Match(periodDuration: 120)
        m.toggleClock(now: t0)
        let events = m.tick(now: t0 + 1000)
        XCTAssertEqual(events, [
            ClockEvent(kind: .warning, date: t0 + 60),
            ClockEvent(kind: .expired, date: t0 + 120),
        ])
    }
}

final class MatchFlowTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testResetClockAfterExpiryKeepsScore() {
        var m = Match(periodDuration: 60)
        m.addScore(.home)
        m.toggleClock(now: t0)
        _ = m.tick(now: t0 + 61)
        m.resetClock()
        XCTAssertEqual(m.homeScore, 1)
        XCTAssertEqual(m.clock, .ready(remaining: 60))
    }

    func testNewMatchResetsEverything() {
        var m = Match(periodDuration: 60)
        m.addScore(.home)
        m.addScore(.away)
        m.toggleClock(now: t0)
        m.startNewMatch()
        XCTAssertEqual(m.homeScore, 0)
        XCTAssertEqual(m.awayScore, 0)
        XCTAssertEqual(m.clock, .ready(remaining: 60))
    }

    func testDurationChangeAppliesImmediatelyOnlyWhenUntouched() {
        var m = Match(periodDuration: 420)
        m.setPeriodDuration(600)
        XCTAssertEqual(m.clock, .ready(remaining: 600))

        m.toggleClock(now: t0)
        m.toggleClock(now: t0 + 100)
        m.setPeriodDuration(300)
        XCTAssertEqual(m.clock, .paused(remaining: 500), "途中なら今の残り時間はそのまま")

        m.resetClock()
        XCTAssertEqual(m.clock, .ready(remaining: 300), "次にタイマーを戻したときから反映")
    }

    func testSetRemainingOnlyWhenStopped() {
        var m = Match(periodDuration: 420)
        m.toggleClock(now: t0)
        m.setRemaining(100)
        XCTAssertTrue(m.isRunning, "動作中は変えない")

        m.toggleClock(now: t0 + 20)
        m.setRemaining(95)
        XCTAssertEqual(m.clock, .paused(remaining: 95))
        XCTAssertFalse(m.isUntouched)

        m.setRemaining(0)
        XCTAssertEqual(m.clock, .paused(remaining: 95), "0 秒にはしない")
    }

    func testSetRemainingAfterExpiryAllowsResuming() {
        var m = Match(periodDuration: 60)
        m.toggleClock(now: t0)
        _ = m.tick(now: t0 + 61)
        m.setRemaining(30)
        m.toggleClock(now: t0 + 100)
        XCTAssertEqual(m.remaining(at: t0 + 110), 20, accuracy: 0.001)
    }

    func testCodableRoundTrip() throws {
        var m = Match(periodDuration: 420)
        m.addScore(.home)
        m.toggleClock(now: t0)
        let data = try JSONEncoder().encode(m)
        XCTAssertEqual(try JSONDecoder().decode(Match.self, from: data), m)
    }
}

final class MatchSettingsTests: XCTestCase {
    func testNormalized() {
        var s = MatchSettings()
        s.home.name = "  とても長いチームの名前です  "
        s.away.name = "   "
        s.periodSeconds = 99 * 60
        let n = s.normalized()
        XCTAssertEqual(n.home.name, "とても長いチーム")
        XCTAssertEqual(n.away.name, MatchSettings.defaultAwayName)
        XCTAssertEqual(n.periodSeconds, 40 * 60)

        s.periodSeconds = 0
        XCTAssertEqual(s.normalized().periodSeconds, 1)
    }

    func testWarningSecondsDefaultsAndRoundTrip() throws {
        XCTAssertEqual(MatchSettings().warningSeconds, 60)
        let legacy = #"{"periodSeconds":420}"#
        XCTAssertEqual(try JSONDecoder().decode(MatchSettings.self, from: Data(legacy.utf8)).warningSeconds, 60)

        var s = MatchSettings()
        s.warningSeconds = 0
        let decoded = try JSONDecoder().decode(MatchSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.warningSeconds, 0)
    }

    func testHalfWarning() throws {
        var s = MatchSettings()
        s.periodSeconds = 7 * 60
        s.warningSeconds = MatchSettings.halfWarning
        XCTAssertEqual(s.warningLeadSeconds, 210)
        XCTAssertEqual(s.normalized().warningSeconds, MatchSettings.halfWarning, "半分は正規化で消さない")
        XCTAssertEqual(s.warningNotificationTitle, "半分経過(残り3分30秒)")
        XCTAssertEqual(MatchSettings.warningChoiceLabel(MatchSettings.halfWarning), "半分")

        s.periodSeconds = 10 * 60
        XCTAssertEqual(s.warningLeadSeconds, 300, "試合時間を変えると半分も追従する")

        let decoded = try JSONDecoder().decode(MatchSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.warningSeconds, MatchSettings.halfWarning)
    }

    func testDecodesLegacyMinutes() throws {
        let legacy = #"{"home":{"name":"赤","color":"red"},"away":{"name":"青","color":"blue"},"periodMinutes":10}"#
        let s = try JSONDecoder().decode(MatchSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.periodSeconds, 600)
        XCTAssertEqual(s.home.name, "赤")
    }

    func testRoundTripKeepsSeconds() throws {
        var s = MatchSettings()
        s.periodSeconds = 7 * 60 + 30
        let decoded = try JSONDecoder().decode(MatchSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testLabel() {
        XCTAssertEqual(MatchSettings.label(seconds: 420), "7分")
        XCTAssertEqual(MatchSettings.label(seconds: 450), "7分30秒")
        XCTAssertEqual(MatchSettings.label(seconds: 45), "45秒")
    }
}
