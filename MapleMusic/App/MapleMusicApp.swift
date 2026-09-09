import SwiftUI

@main
struct MapleMusicApp: App {
    @StateObject private var settings = ProviderSettings()
    @StateObject private var appearance = AppearanceSettings()
    @StateObject private var developerSettings = DeveloperSettings()

    var body: some Scene {
        WindowGroup {
            ProviderRoot(configuration: settings.configuration)
                .id(settings.generation)
                .environmentObject(settings)
                .environmentObject(appearance)
                .environmentObject(developerSettings)
        }
    }
}

private struct ProviderRoot: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    @StateObject private var container: AppContainer
    init(configuration: ProviderConfiguration) {
        _container = StateObject(wrappedValue: AppContainer(configuration: configuration))
    }
    var body: some View {
            RootView()
                .environmentObject(container)
                .environmentObject(container.auth)
                .environmentObject(container.catalog)
                .environmentObject(container.player)
                .environmentObject(container.downloads)
                .environmentObject(container.lyricsSettings)
                .environmentObject(container.downloadPreferences)
                .environmentObject(container.waveSettings)
                .task { await container.bootstrap() }
                .tint(appearance.tint)
                .preferredColorScheme(appearance.interfaceStyle.colorScheme)
                .onDisappear { container.player.stop() }
    }
}
