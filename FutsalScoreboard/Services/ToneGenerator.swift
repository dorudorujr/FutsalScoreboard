import Foundation

/// 音源ファイルを同梱せず、予告音と終了音の WAV をコードで生成する(すべてオリジナルの音)
enum ToneGenerator {
    /// 1 つの音。開始時刻をずらして重ねられる
    struct Note {
        var start: TimeInterval
        var frequency: Double
        var duration: TimeInterval
        /// 基音に対する 2 倍音の強さ。0 で純音(柔らかい)、上げると芯のある音になる
        var octave: Double = 0.15
        /// 0 なら鳴り続ける音。正の値なら、その秒数で約 1/e に減衰するベル風の音
        var decay: TimeInterval = 0
        var gain: Double = 1
    }

    static let sampleRate = 44_100

    // MARK: - 音の定義(キラキラ系のベル)

    /// 残り 1 分の予告: ド・ミ・ソ・ドを素早く駆け上がるベル(約 0.9 秒)
    static let warning: [Note] = arpeggio(at: 0)

    /// 終了: 駆け上がりを 2 回のあと、和音が響いて消える(約 3 秒)
    static let end: [Note] = arpeggio(at: 0) + arpeggio(at: 0.75) + chord.map {
        Note(start: 1.5, frequency: $0, duration: 1.5, octave: 0.05, decay: 0.55, gain: 0.6)
    }

    /// C6・E6・G6・C7
    private static let chord: [Double] = [1_046.5, 1_318.5, 1_568.0, 2_093.0]

    private static func arpeggio(at t: TimeInterval) -> [Note] {
        chord.enumerated().map { i, f in
            Note(start: t + Double(i) * 0.08, frequency: f, duration: 0.65, octave: 0.05, decay: 0.18)
        }
    }

    // MARK: - WAV 生成

    /// 16bit モノラル PCM の WAV データ。重なった音は最大音量に合わせて正規化する
    static func wav(_ notes: [Note], volume: Double = 0.8) -> Data {
        let total = notes.map { $0.start + $0.duration }.max() ?? 0
        var buffer = [Double](repeating: 0, count: Int(total * Double(sampleRate)) + 1)
        let fade = Int(Double(sampleRate) * 0.008) // クリックノイズ防止
        for note in notes where note.frequency > 0 {
            let offset = Int(note.start * Double(sampleRate))
            let count = Int(note.duration * Double(sampleRate))
            for i in 0..<count where offset + i < buffer.count {
                let t = Double(i) / Double(sampleRate)
                let w = 2 * Double.pi * note.frequency * t
                let v = (sin(w) + note.octave * sin(2 * w)) / (1 + note.octave)
                var envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
                if note.decay > 0 { envelope *= exp(-t / note.decay) }
                buffer[offset + i] += v * envelope * note.gain
            }
        }
        let peak = max(buffer.map(abs).max() ?? 1, 1e-9)
        let samples = buffer.map { Int16($0 / peak * volume * Double(Int16.max)) }
        return header(sampleCount: samples.count) + samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func header(sampleCount: Int) -> Data {
        let dataSize = UInt32(sampleCount * 2)
        var d = Data()
        func append<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36) + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)) // byte rate
        append(UInt16(2)) // block align
        append(UInt16(16)) // bits per sample
        d.append(contentsOf: Array("data".utf8)); append(dataSize)
        return d
    }
}
