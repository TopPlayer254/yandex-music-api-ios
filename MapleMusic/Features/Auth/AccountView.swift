import Foundation
import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var settings: ProviderSettings
    @EnvironmentObject private var lyricsSettings: LyricsSettings

    var body: some View {
        NavigationStack {
            List {
                if settings.configuration.kind == .demo {
                    Section {
                        Button {
                            switchToYandex()
                        } label: {
                            Label("Перейти к Яндекс Музыке", systemImage: "person.crop.circle.badge.plus")
                        }
                    } footer: {
                        Text("Демо-режим можно отключить в любой момент. После переключения откроется обычный вход в аккаунт.")
                    }
                }

                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Оформление",
                            subtitle: "Акцентный цвет и внешний вид",
                            systemImage: "paintpalette.fill",
                            color: .purple
                        )
                    }

                    NavigationLink {
                        AccountSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Учётная запись",
                            subtitle: accountSubtitle,
                            systemImage: "person.crop.circle.fill",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        AudioProviderSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Звук и источник",
                            subtitle: settings.configuration.kind.title,
                            systemImage: "waveform",
                            color: .pink
                        )
                    }

                    NavigationLink {
                        LyricsSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Тексты песен",
                            subtitle: lyricsSettings.hasGeniusToken ? "Яндекс + Genius" : "Яндекс",
                            systemImage: "quote.bubble.fill",
                            color: .orange
                        )
                    }

                    NavigationLink {
                        StorageSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Хранилище",
                            subtitle: downloads.entries.count.russianTrackCount,
                            systemImage: "externaldrive.fill",
                            color: .green
                        )
                    }
                }

                Section {
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "О приложении",
                            subtitle: "Версия и конфиденциальность",
                            systemImage: "info.circle.fill",
                            color: .gray
                        )
                    }
                }

                Section {
                    NavigationLink {
                        DeveloperSettingsView()
                    } label: {
                        SettingsDestinationLabel(
                            title: "Разработчик",
                            subtitle: "Экспериментальные функции",
                            systemImage: "hammer.fill",
                            color: .gray
                        )
                    }
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var accountSubtitle: String {
        switch auth.state {
        case let .signedIn(profile): profile.displayName
        case .restoring, .signingIn: "Проверка входа…"
        case .signedOut: settings.configuration.kind == .demo ? "Не требуется" : "Не выполнен"
        }
    }

    private func switchToYandex() {
        player.stop()
        try? settings.apply(ProviderConfiguration())
    }
}

private struct DeveloperSettingsView: View {
    @EnvironmentObject private var developerSettings: DeveloperSettings

    var body: some View {
        List {
            Section {
                Toggle(
                    "Use new shader-based wave toggle",
                    isOn: $developerSettings.usesNewShaderBasedWave
                )
            } footer: {
                Text("Включает на главной экспериментальную кнопку «Моей волны» с анимированными metaballs и палитрой выбранного настроения.")
            }
        }
        .navigationTitle("Разработчик")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsDestinationLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.vertical, 2)
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: AppearanceSettings

    var body: some View {
        List {
            Section("Тема") {
                Picker("Тема", selection: $appearance.interfaceStyle) {
                    ForEach(InterfaceStyleChoice.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Акцентный цвет") {
                ForEach(AccentColorChoice.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appearance.accent = option
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(.primary.opacity(0.12), lineWidth: 0.5))
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if appearance.accent == option {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(appearance.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Text("Выбранный цвет применяется сразу к системным кнопкам, активным вкладкам и индикаторам.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountSettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var settings: ProviderSettings
    @StateObject private var deviceLogin = YandexDeviceLogin()
    @State private var token = ""
    @State private var isChecking = false
    @State private var showsClearSessionConfirmation = false

    var body: some View {
        Form {
            if settings.configuration.kind == .demo {
                Section {
                    Label("Локальная демоверсия", systemImage: "iphone.and.arrow.forward")
                    Text("Демо-режим не требует учётной записи и использует только встроенные аудиофайлы.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Перейти к Яндекс Музыке") {
                        player.stop()
                        try? settings.apply(ProviderConfiguration())
                    }
                }
            } else if case let .signedIn(profile) = auth.state {
                Section {
                    Label(profile.displayName, systemImage: "person.crop.circle.fill")
                }
                Section {
                    Button("Очистить сессию и выйти", role: .destructive) {
                        showsClearSessionConfirmation = true
                    }
                } footer: {
                    Text("Локальный токен, кэш профиля, cookies и сетевой кэш будут удалены. Сохранённые треки останутся в хранилище.")
                }
            } else {
                if settings.configuration.kind == .yandex {
                    Section {
                        Button("Войти через Яндекс") {
                            deviceLogin.start { value in
                                if await auth.importToken(value) { await container.loadCurrentAccount() }
                            }
                        }
                        .disabled(deviceLogin.isRunning)

                        if let code = deviceLogin.userCode {
                            LabeledContent("Код") {
                                Text(code).font(.headline.monospaced()).textSelection(.enabled)
                            }
                            if deviceLogin.verificationURL != nil {
                                Button("Открыть временное окно входа") {
                                    deviceLogin.openVerificationPage()
                                }
                            }
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Ожидание подтверждения…")
                            }
                            Button("Прекратить ожидание", role: .cancel) { deviceLogin.cancel() }
                        }
                    } header: {
                        Text("Яндекс ID")
                    } footer: {
                        Text("Приложение покажет одноразовый код и откроет защищённую страницу Яндекс ID.")
                    }
                }

                Section("Токен доступа") {
                    SecureField("OAuth-токен", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Проверить и войти") {
                        isChecking = true
                        Task {
                            let value = token
                            token = ""
                            if await auth.importToken(value) { await container.loadCurrentAccount() }
                            isChecking = false
                        }
                    }
                    .disabled(isChecking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = auth.errorMessage ?? deviceLogin.error {
                Section("Ошибка входа") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Учётная запись")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            deviceLogin.cancel()
            token = ""
        }
        .confirmationDialog(
            "Очистить сессию?",
            isPresented: $showsClearSessionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Очистить сессию и выйти", role: .destructive) {
                Task {
                    player.stop()
                    await auth.clearSession()
                    if auth.state == .signedOut { settings.reloadSession() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Для следующего подключения потребуется снова войти в аккаунт.")
        }
    }
}

private struct LyricsSettingsView: View {
    @EnvironmentObject private var settings: LyricsSettings
    @State private var token = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Toggle("Использовать Genius как резерв", isOn: $settings.usesGeniusFallback)
                    .disabled(!settings.hasGeniusToken)
            } footer: {
                Text("Сначала приложение запрашивает синхронизированный текст у музыкального сервиса. Genius используется только если основной текст недоступен.")
            }

            Section("Genius API") {
                SecureField("Client Access Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(settings.hasGeniusToken ? "Заменить API-ключ" : "Сохранить API-ключ") {
                    let value = token
                    token = ""
                    isSaving = true
                    Task {
                        _ = await settings.saveToken(value)
                        isSaving = false
                    }
                }
                .disabled(isSaving || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if settings.hasGeniusToken {
                    Button("Удалить API-ключ", role: .destructive) {
                        Task { await settings.clearToken() }
                    }
                }

                Link("Открыть страницу API-клиентов Genius", destination: URL(string: "https://genius.com/api-clients")!)
            }

            Section {
                Text("Ключ хранится только на устройстве. Когда резерв включён, название трека и исполнитель отправляются Genius для поиска страницы песни; служебные подписи в квадратных скобках удаляются. Текст Genius не синхронизирован по времени.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = settings.errorMessage {
                Section("Ошибка") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Тексты песен")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AudioProviderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var settings: ProviderSettings
    @State private var draft = ProviderConfiguration()
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("Качество", selection: $player.preferredQuality) {
                    ForEach(AudioQuality.selectableCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            } header: {
                Text("Качество звука")
            } footer: {
                Text(player.preferredQuality.subtitle)
            }

            Section {
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
            } header: {
                Text("Музыкальный сервис")
            } footer: {
                Text("Веб-стандарт запрашивает обычный поток как веб-плеер и не требует Плюса. MP3 используется как резерв. Lossless запрашивается отдельно и требует соответствующего доступа аккаунта.")
            }

            Section {
                Button("Применить") {
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
            }
        }
        .navigationTitle("Звук и источник")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = settings.configuration }
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

private struct StorageSettingsView: View {
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var downloadPreferences: DownloadPreferences
    @EnvironmentObject private var player: PlayerStore
    @State private var showsClearDownloadsConfirmation = false

    var body: some View {
        List {
            Section("Офлайн-медиатека") {
                LabeledContent("Загружено", value: downloads.entries.count.russianTrackCount)
                LabeledContent("Размер", value: ByteCountFormatter.string(
                    fromByteCount: downloads.entries.reduce(0) { $0 + $1.byteCount },
                    countStyle: .file
                ))
                NavigationLink("Загруженные треки") {
                    DownloadsView(allTracks: downloads.entries.compactMap(\.track))
                }
                Label("Доступно в «Файлы» → «На iPhone» → Maple Music", systemImage: "folder.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Автоскачивание при воспроизведении",
                    isOn: $downloadPreferences.automaticallyDownloadsPlayedTracks
                )
            } footer: {
                Text("После успешного запуска трек автоматически сохраняется в выбранном качестве. Уже загруженные треки пропускаются.")
            }

            Section {
                Button("Удалить все сохранённые треки", role: .destructive) {
                    showsClearDownloadsConfirmation = true
                }
                .disabled(downloads.entries.isEmpty)
            }

            Section {
                Text("Файлы, тексты песен и манифест загрузок хранятся отдельно для каждого источника и аккаунта.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Хранилище")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить все сохранённые треки?",
            isPresented: $showsClearDownloadsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить все треки", role: .destructive) {
                Task {
                    if let track = player.currentTrack, downloads.isDownloaded(track) {
                        player.stop()
                    }
                    await downloads.removeAll()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Треки и сохранённые тексты песен будут удалены с устройства.")
        }
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Версия", value: version)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "com.hikeri.yamusic")
            }

            Section("Конфиденциальность") {
                Label("Без аналитики и рекламных SDK", systemImage: "hand.raised.fill")
                Label("Сессия защищена Keychain и Data Protection", systemImage: "key.fill")
                Text("Офлайн-файлы защищены механизмом Data Protection в iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
