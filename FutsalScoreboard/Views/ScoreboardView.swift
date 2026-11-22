import Combine
import SwiftUI

struct ScoreboardView: View {
    let model: ScoreboardModel

    @State private var showSettings = false
    @State private var showTimeEditor = false
    @State private var confirm: ConfirmAction?
    @Environment(\.scenePhase) private var scenePhase

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    enum ConfirmAction: Identifiable {
        case resetClock, newMatch
        var id: Self { self }
        var title: String {
            switch self {
            case .resetClock: "タイマーを戻しますか？"
            case .newMatch: "オールリセットしますか？"
            }
        }
        var message: String {
            switch self {
            case .resetClock: "得点はそのままで、残り時間を試合時間に戻します。"
            case .newMatch: "両チームの得点を0にして、タイマーを試合時間に戻します。"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            // 縦画面: 上にボタンとタイマー、中央に左右のチーム、下に操作ボタン
            let w = geo.size.width
            let h = geo.size.height
            let clockSize = w * 0.2
            ZStack {
                HStack(spacing: 0) {
                    teamPanel(.home, config: model.settings.home, width: w / 2, height: h, clockSize: clockSize)
                    teamPanel(.away, config: model.settings.away, width: w / 2, height: h, clockSize: clockSize)
                }

                VStack(spacing: 10) {
                    HStack {
                        iconButton("gearshape.fill") { showSettings = true }
                            .disabled(model.match.isRunning)
                        Spacer()
                        resetButton
                    }
                    ClockPlate(remaining: model.remaining,
                               isExpired: model.match.isExpired, warningLead: model.match.warningLead,
                               timeFontSize: clockSize)
                        .contentShape(Rectangle())
                        .onTapGesture { if !model.match.isRunning { showTimeEditor = true } }
                        .accessibilityAddTraits(model.match.isRunning ? [] : .isButton)
                        .accessibilityHint(model.match.isRunning ? "" : "タップで時間を変更")
                    Spacer()
                    HStack(alignment: .bottom) {
                        minusButton(.home)
                        Spacer()
                        centerControls
                        Spacer()
                        minusButton(.away)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.tick()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onReceive(ticker) { model.tick($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                model.tick()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: model.settings) { model.updateSettings($0) }
        }
        .sheet(isPresented: $showTimeEditor) {
            timeEditSheet
        }
        .alert(confirm?.title ?? "", isPresented: Binding(
            get: { confirm != nil },
            set: { if !$0 { confirm = nil } }
        ), presenting: confirm) { action in
            Button("キャンセル", role: .cancel) {}
            Button(action == .newMatch ? "リセット" : "戻す", role: .destructive) {
                switch action {
                case .resetClock: model.resetClock()
                case .newMatch: model.startNewMatch()
                }
            }
        } message: { action in
            Text(action.message)
        }
    }

    // MARK: - パーツ

    /// 未開始なら試合時間そのもの、途中なら今の残り時間を変える
    private var timeEditSheet: some View {
        let untouched = model.match.isUntouched
        let current = model.match.isExpired
            ? model.settings.periodSeconds
            : Int(model.remaining.rounded(.up))
        return TimeEditSheet(
            initialSeconds: current,
            title: untouched ? "試合時間" : "残り時間",
            message: untouched
                ? "試合時間になります。次の試合でも使われます。"
                : "今の残り時間だけを変えます。試合時間の設定は変わりません。"
        ) { model.setClockTime(seconds: $0) }
    }

    private func teamPanel(_ team: Team, config: TeamConfig, width: CGFloat, height h: CGFloat,
                           clockSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            // 上のボタン行とタイマーの下から始める
            Color.clear.frame(height: 48 + 10 + clockSize * 1.25 + 16)
            Spacer(minLength: 0)
            Text(config.name)
                .font(.system(size: min(width * 0.13, 28), weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 10)
            Text("\(model.match.score(for: team))")
                .font(.system(size: min(width * 0.85, h * 0.3), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(.snappy, value: model.match.score(for: team))
                .padding(.horizontal, 6)
                // 2 桁で文字が縮んでも、左右のチーム名の高さがそろうように枠の高さを固定する
                .frame(height: min(width * 0.85, h * 0.3) * 1.1)
            Spacer(minLength: 0)
            // 下の操作ボタンの分を空ける
            Color.clear.frame(height: 80)
        }
        .foregroundStyle(config.color.foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(config.color.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { model.addScore(team) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(config.name) \(model.match.score(for: team))点")
        .accessibilityHint("タップで1点追加")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var centerControls: some View {
        if model.match.isExpired {
            // 得点を残してもう一度(後半など)か、得点も 0 に戻して新しい試合か
            VStack(spacing: 10) {
                pillButton("タイマーを戻す", systemImage: "timer") { model.resetClock() }
                pillButton("新しい試合", systemImage: "arrow.counterclockwise.circle.fill") { model.startNewMatch() }
            }
        } else {
            pillButton(model.match.isRunning ? "停止" : "開始",
                       systemImage: model.match.isRunning ? "pause.fill" : "play.fill",
                       prominent: true) { model.toggleClock() }
                .contextMenu {
                    Button("タイマーだけ戻す", systemImage: "timer") { confirm = .resetClock }
                }
        }
    }

    private func pillButton(_ title: String, systemImage: String, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: prominent ? 26 : 20, weight: .bold))
                .padding(.horizontal, prominent ? 36 : 20)
                .padding(.vertical, prominent ? 16 : 14)
                .frame(minWidth: prominent ? 180 : nil)
                .foregroundStyle(.white)
                .background(.black.opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func minusButton(_ team: Team) -> some View {
        Button { model.subtractScore(team) } label: {
            Image(systemName: "minus")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 56, height: 56)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.match.score(for: team) == 0)
        .opacity(model.match.score(for: team) == 0 ? 0.4 : 1)
        .accessibilityLabel("1点減らす")
    }

    /// 得点とタイマーをすべて初期状態に戻す
    private var resetButton: some View {
        Button { confirm = .newMatch } label: {
            Label("リセット", systemImage: "arrow.counterclockwise")
                .font(.system(size: 17, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("オールリセット")
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

/// 上部中央のタイマー表示
private struct ClockPlate: View {
    let remaining: TimeInterval
    let isExpired: Bool
    /// この秒数を切ったら文字をオレンジにする(0 ならしない)
    let warningLead: TimeInterval
    let timeFontSize: CGFloat

    private var displaySeconds: Int { Int(remaining.rounded(.up)) }

    private var text: String {
        String(format: "%02d:%02d", displaySeconds / 60, displaySeconds % 60)
    }

    private var color: Color {
        if isExpired { return .red }
        return warningLead > 0 && remaining < warningLead ? .orange : .white
    }

    var body: some View {
        Text(text)
            .font(.system(size: timeFontSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
