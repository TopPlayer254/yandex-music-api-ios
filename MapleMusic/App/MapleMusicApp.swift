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
    @State private var showsWelcome: Bool
    init(configuration: ProviderConfiguration) {
        _container = StateObject(wrappedValue: AppContainer(configuration: configuration))
        _showsWelcome = State(initialValue:
            UserDefaults.standard.object(forKey: "has-seen-welcome") == nil
                && UserDefaults.standard.data(forKey: "provider-configuration") == nil
        )
    }
    var body: some View {
        Group {
            if showsWelcome {
                WelcomeView {
                    UserDefaults.standard.set(true, forKey: "has-seen-welcome")
                    showsWelcome = false
                }
            } else {
                RootView()
                    .task { await container.bootstrap() }
            }
        }
        .environmentObject(container)
        .environmentObject(container.auth)
        .environmentObject(container.catalog)
        .environmentObject(container.player)
        .environmentObject(container.downloads)
        .environmentObject(container.lyricsSettings)
        .environmentObject(container.downloadPreferences)
        .environmentObject(container.waveSettings)
        .tint(appearance.tint)
        .preferredColorScheme(appearance.interfaceStyle.colorScheme)
        .onDisappear { container.player.stop() }
    }
}
