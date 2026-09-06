import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: AppearanceSettings
    @EnvironmentObject private var settings: ProviderSettings
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore
    @StateObject private var deviceLogin = YandexDeviceLogin()
    @State private var draft = ProviderConfiguration()
    @State private var token = ""
    @State private var message: String?
    @State private var isChecking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Музыкальный сервис") {
                    Picker("Провайдер", selection: $draft.kind) {
                        ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: draft.kind) { _, kind in
                        if kind == .yandex { draft.endpoint = "https://api.music.yandex.net" }
                        if kind == .gateway { draft.endpoint = "" }
                    }

                    if draft.kind != .demo {
                        TextField("HTTPS-адрес API", text: $draft.endpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    if draft.kind == .yandex {
                        Picker("API воспроизведения", selection: $draft.streamAPI) {
                            ForEach(YandexMusicService.StreamAPI.allCases) { Text($0.title).tag($0) }
                        }
                    }

                    Button("Применить настройки провайдера") {
                        do {
                            if draft.kind != .demo { _ = try draft.validatedURL() }
                            player.stop()
                            try settings.apply(draft)
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    .disabled(draft == settings.configuration)

                    Text("Токены хранятся отдельно для каждого адреса API. Автоматический режим сначала использует File info, а при совместимой ошибке переключается на legacy MP3.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if settings.configuration.kind != .demo {
                    Section("Учётная запись") {
                        if case let .signedIn(profile) = auth.state {
                            Label(profile.displayName, systemImage: "person.crop.circle.fill")
                            Button("Выйти", role: .destructive) {
                                Task {
                                    player.stop()
                                    await auth.signOut()
                                    if auth.state == .signedOut { settings.reloadSession() }
                                }
                            }
                        } else {
                            if settings.configuration.kind == .yandex {
                                Button("Войти через Яндекс") {
                                    deviceLogin.start { value in
                                        if await auth.importToken(value) { settings.reloadSession() }
                                    }
                                }
                                .disabled(deviceLogin.isRunning)

                                if let code = deviceLogin.userCode {
                                    Text(code)
                                        .font(.title2.monospaced().bold())
                                        .textSelection(.enabled)
                                    if let url = deviceLogin.verificationURL {
                                        Link("Открыть Яндекс и ввести код", destination: url)
                                    }
                                    HStack {
                                        ProgressView()
                                        Text("Ожидание подтверждения…")
                                    }
                                    Button("Отменить вход") { deviceLogin.cancel() }
                                }
                            }

                            DisclosureGroup("Войти с помощью токена доступа") {
                                SecureField("Токен доступа", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                Button("Проверить и войти") {
                                    isChecking = true
                                    Task {
                                        let value = token
                                        token = ""
                                        if await auth.importToken(value) { settings.reloadSession() }
                                        isChecking = false
                                    }
                                }
                                .disabled(isChecking || token.isEmpty)
                            }
                        }

                        if let error = auth.errorMessage ?? deviceLogin.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }

                Section("Звук") {
                    Picker("Качество", selection: $player.preferredQuality) {
                        ForEach(AudioQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Text("Lossless запрашивается только у выбранного провайдера. Реальная доступность зависит от трека и прав аккаунта.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Оформление") {
                    Picker("Акцентный цвет", selection: $appearance.accent) {
                        ForEach(AccentColorChoice.allCases) { option in
                            HStack {
                                Image(systemName: "circle.fill").foregroundStyle(option.color)
                                Text(option.title)
                            }
                            .tag(option)
                        }
                    }
                    HStack(spacing: 10) {
                        Circle().fill(appearance.tint).frame(width: 22, height: 22)
                        Text("Акцент применяется к кнопкам, индикаторам и выбранным разделам.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Конфиденциальность") {
                    Label("Без аналитики и рекламных SDK", systemImage: "hand.raised.fill")
                    Label("Токены хранятся в Связке ключей", systemImage: "key.fill")
                    Text("Загрузки и тексты песен разделены по провайдеру и аккаунту и защищены механизмом Data Protection в iOS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear { draft = settings.configuration }
            .onDisappear {
                deviceLogin.cancel()
                token = ""
            }
            .alert("Настройки", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("ОК", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }
}
