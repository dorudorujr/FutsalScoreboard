import SwiftUI

/// 分と秒のホイールで秒数を選ぶ(1 秒〜40 分)
struct MinuteSecondPicker: View {
    @Binding var totalSeconds: Int

    private var minutes: Binding<Int> {
        Binding(
            get: { totalSeconds / 60 },
            set: { totalSeconds = MatchSettings.clampSeconds($0 * 60 + totalSeconds % 60) }
        )
    }

    private var seconds: Binding<Int> {
        Binding(
            get: { totalSeconds % 60 },
            set: { totalSeconds = MatchSettings.clampSeconds((totalSeconds / 60) * 60 + $0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("分", selection: minutes) {
                ForEach(0...40, id: \.self) { Text("\($0)分").tag($0) }
            }
            .pickerStyle(.wheel)
            Picker("秒", selection: seconds) {
                ForEach(0..<60, id: \.self) { Text("\($0)秒").tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .frame(height: 160)
    }
}

/// タイマー表示をタップしたときに出す時間設定シート
struct TimeEditSheet: View {
    let title: String
    let message: String
    let onSave: (Int) -> Void

    @State private var seconds: Int
    @Environment(\.dismiss) private var dismiss

    init(initialSeconds: Int, title: String, message: String, onSave: @escaping (Int) -> Void) {
        _seconds = State(initialValue: MatchSettings.clampSeconds(initialSeconds))
        self.title = title
        self.message = message
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                MinuteSecondPicker(totalSeconds: $seconds)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        onSave(seconds)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
