import Foundation
import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var settings: ProviderSettings

    var body: some View {
        NavigationStack {
            List {
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
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var settings: ProviderSettings
    @StateObject private var deviceLogin = YandexDeviceLogin()
    @State private var token = ""
    @State private var isChecking = false

    var body: some View {
        Form {
            if settings.configuration.kind == .demo {
                Section {
                    Label("Локальная демоверсия", systemImage: "iphone.and.arrow.forward")
                    Text("Демо-режим не требует учётной записи и использует только встроенные аудиофайлы.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if case let .signedIn(profile) = auth.state {
                Section {
                    Label(profile.displayName, systemImage: "person.crop.circle.fill")
                }
                Section {
                    Button("Выйти", role: .destructive) {
                        Task {
                            player.stop()
                            await auth.signOut()
                            if auth.state == .signedOut { settings.reloadSession() }
                        }
                    }
                }
            } else {
                if settings.configuration.kind == .yandex {
                    Section("Яндекс ID") {
                        Button("Войти через Яндекс") {
                            deviceLogin.start { value in
                                if await auth.importToken(value) { settings.reloadSession() }
                            }
                        }
                        .disabled(deviceLogin.isRunning)

                        if let code = deviceLogin.userCode {
                            LabeledContent("Код") {
                                Text(code).font(.headline.monospaced()).textSelection(.enabled)
                            }
                            if let url = deviceLogin.verificationURL {
                                Link("Открыть страницу входа", destination: url)
                            }
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Ожидание подтверждения…")
                            }
                            Button("Отменить вход", role: .cancel) { deviceLogin.cancel() }
                        }
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
                            if await auth.importToken(value) { settings.reloadSession() }
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
            Section("Качество звука") {
                Picker("Качество", selection: $player.preferredQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            } footer: {
                Text(player.preferredQuality.subtitle)
            }

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
            } footer: {
                Text("Автоматический режим сначала использует совместимый MP3-поток, а затем File info. Lossless запрашивается через File info, если он доступен треку и аккаунту.")
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
            }

            Section {
                Text("Файлы, тексты песен и манифест загрузок хранятся отдельно для каждого источника и аккаунта.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Хранилище")
        .navigationBarTitleDisplayMode(.inline)
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
                Label("Токены хранятся в Связке ключей", systemImage: "key.fill")
                Text("Офлайн-файлы защищены механизмом Data Protection в iOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
