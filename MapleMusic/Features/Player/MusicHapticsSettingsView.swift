import SwiftUI

struct MusicHapticsSettingsView: View {
    @ObservedObject var controller: MusicHapticsController

    var body: some View {
        Form {
            Section {
                Toggle("Music Haptics", isOn: $controller.enabled)
                Picker("Режим", selection: $controller.systemMode) {
                    Text("Локальный расчёт").tag(false)
                    Text("Системный Apple").tag(true)
                }
                .disabled(!controller.enabled)
            } footer: {
                Text(controller.systemMode
                    ? "Нужны iOS 18, Music Haptics в универсальном доступе и доступная дорожка Apple. Системную силу регулирует iOS."
                    : "Хаптики рассчитываются на устройстве по аудио и сохраняются для повторного воспроизведения. При первом запуске подготовка может занять время.")
            }
            if !controller.systemMode {
                Section("Сила") {
                    Slider(value: $controller.strength, in: 0...1, step: 0.05)
                        .accessibilityLabel("Сила хаптиков")
                        .accessibilityValue("\(Int(controller.strength * 100)) процентов")
                    LabeledContent("Интенсивность", value: "\(Int(controller.strength * 100)) %")
                }.disabled(!controller.enabled || !controller.supported)
            }
            Section { Text(controller.status).foregroundStyle(.secondary) }
        }
        .navigationTitle("Music Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { NavigationStack { MusicHapticsSettingsView(controller: MusicHapticsController()) } }
