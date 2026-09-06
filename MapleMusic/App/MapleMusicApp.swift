import SwiftUI

@main
struct MapleMusicApp: App {
    @StateObject private var settings = ProviderSettings()
    @StateObject private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            ProviderRoot(configuration: settings.configuration)
                .id(settings.generation)
                .environmentObject(settings)
                .environmentObject(appearance)
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
                .task { await container.bootstrap() }
                .tint(appearance.tint)
                .onDisappear { container.player.stop() }
    }
}
