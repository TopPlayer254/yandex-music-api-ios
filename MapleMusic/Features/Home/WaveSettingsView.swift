import SwiftUI

struct WaveSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var settings: WaveSettings
    @State private var draft = WaveConfiguration()
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Настроение") {
                    Picker("Настроение", selection: $draft.moodEnergy) {
                        ForEach(WaveMoodEnergy.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Подбор треков") {
                    Picker("Разнообразие", selection: $draft.diversity) {
                        ForEach(WaveDiversity.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Язык") {
                    Picker("Язык песен", selection: $draft.language) {
                        ForEach(WaveLanguage.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Text("Параметры сохраняются в аккаунте Яндекс и применяются к следующей подборке «Моей волны».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Моя волна")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        settings.configuration = draft
                        isApplying = true
                        Task {
                            if await catalog.applyWaveSettings(draft) { dismiss() }
                            isApplying = false
                        }
                    }
                    .disabled(isApplying)
                }
            }
            .onAppear { draft = settings.configuration }
        }
    }
}
