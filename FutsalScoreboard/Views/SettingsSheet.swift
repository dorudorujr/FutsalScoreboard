import SwiftUI

struct SettingsSheet: View {
    @State private var draft: MatchSettings
    private let onSave: (MatchSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    init(settings: MatchSettings, onSave: @escaping (MatchSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("試合時間", value: MatchSettings.label(seconds: draft.periodSeconds))
                    MinuteSecondPicker(totalSeconds: $draft.periodSeconds)
                } header: {
                    Text("試合時間")
                } footer: {
                    Text("タイマーが途中のときは、次にタイマーを戻したときから反映されます。")
                }
                Section {
                    Picker("予告", selection: $draft.warningSeconds) {
                        ForEach(MatchSettings.warningChoices, id: \.self) { seconds in
                            Text(MatchSettings.warningChoiceLabel(seconds)).tag(seconds)
                        }
                    }
                } header: {
                    Text("残り時間の予告")
                } footer: {
                    Text("設定した残り時間になったら、予告音とバイブで知らせます。タイマーの文字もオレンジになります。「半分」は試合時間の半分が過ぎたときです。")
                }
                teamSection("左のチーム", team: $draft.home)
                teamSection("右のチーム", team: $draft.away)
            }
            .navigationTitle("試合設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private func teamSection(_ title: String, team: Binding<TeamConfig>) -> some View {
        Section(title) {
            TextField("チーム名", text: team.name)
                .onChange(of: team.wrappedValue.name) { _, newValue in
                    if newValue.count > MatchSettings.nameLimit {
                        team.wrappedValue.name = String(newValue.prefix(MatchSettings.nameLimit))
                    }
                }
            HStack(spacing: 10) {
                ForEach(TeamColor.allCases) { color in
                    Button {
                        team.wrappedValue.color = color
                    } label: {
                        Circle()
                            .fill(color.background)
                            .overlay(Circle().stroke(.gray.opacity(0.5), lineWidth: 1))
                            .overlay {
                                if team.wrappedValue.color == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(color.foreground)
                                }
                            }
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.label)
                    .accessibilityAddTraits(team.wrappedValue.color == color ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}
