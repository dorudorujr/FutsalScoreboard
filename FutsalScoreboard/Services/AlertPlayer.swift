import AVFoundation
import AudioToolbox

/// アプリ表示中のブザーとバイブ
@MainActor
final class AlertPlayer {
    static let warningFileName = "fsb_warning.wav"
    static let endFileName = "fsb_end.wav"

    private var warningPlayer: AVAudioPlayer?
    private var endPlayer: AVAudioPlayer?

    init() {
        // マナーモードでも鳴らすため再生用カテゴリにする。他アプリの音楽は止めない
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let warning = ToneGenerator.wav(ToneGenerator.warning)
        let end = ToneGenerator.wav(ToneGenerator.end)
        warningPlayer = try? AVAudioPlayer(data: warning)
        endPlayer = try? AVAudioPlayer(data: end)
        warningPlayer?.prepareToPlay()
        endPlayer?.prepareToPlay()

        Self.installNotificationSounds(warning: warning, end: end)
    }

    func playWarning() {
        play(warningPlayer)
        vibrate(times: 1)
    }

    func playEnd() {
        play(endPlayer)
        vibrate(times: 3)
    }

    private func play(_ player: AVAudioPlayer?) {
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.currentTime = 0
        player?.play()
    }

    private func vibrate(times: Int) {
        for i in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.0) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }

    /// ローカル通知のカスタム音は Library/Sounds に置く必要がある
    private static func installNotificationSounds(warning: Data, end: Data) {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = library.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? warning.write(to: dir.appendingPathComponent(warningFileName), options: .atomic)
        try? end.write(to: dir.appendingPathComponent(endFileName), options: .atomic)
    }
}
