import Combine
import MusicKit
import SwiftUI
import UIKit

/// Native MusicKit screens may only be constructed after the real authorization
/// request initializes MusicKit's library storage. Spoofing MPMediaLibrary's
/// status leaves that storage nil and traps in MusicKitInternal.
@MainActor
@objc(KreshkaLibraryAuthorization)
final class LibraryAuthorization: NSObject {
    @objc private(set) static var isReady = false
    private static var sessions: [ObjectIdentifier: LibraryAuthorizationSession] = [:]

    @objc(connectScene:completion:)
    static func connect(scene: UIWindowScene, completion: @escaping () -> Void) {
        let key = ObjectIdentifier(scene)
        guard sessions[key] == nil else { return }
        let window = UIWindow(windowScene: scene)
        let session = LibraryAuthorizationSession {
            // The original scene delegate now creates its ordinary Music UI.
            // Keep the temporary window alive until that delegate has returned.
            completion()
            window.isHidden = true
            window.rootViewController = nil
            sessions.removeValue(forKey: key)
        }
        sessions[key] = session
        session.window = window
        window.rootViewController = UIHostingController(rootView: LibraryAuthorizationView(session: session))
        window.makeKeyAndVisible()
    }

    fileprivate static func authorized() { isReady = true }
}

@MainActor
private final class LibraryAuthorizationSession: ObservableObject {
    @Published var denied = false
    @Published var requesting = false
    var window: UIWindow?
    private var finished = false
    private let completion: () -> Void

    init(completion: @escaping () -> Void) { self.completion = completion }

    func request() {
        guard !requesting, !finished else { return }
        requesting = true
        NotificationCenter.default.post(name: .init("KreshkaLibraryAuthorizationChanged"), object: "requesting")
        Task { @MainActor in
            // Always use the SDK request, including on subsequent launches with
            // permission already granted. It also initializes MusicKit storage.
            let status = await MusicAuthorization.request()
            requesting = false
            let allowed = status == .authorized
            NotificationCenter.default.post(name: .init("KreshkaLibraryAuthorizationChanged"), object: allowed ? "authorized" : "denied")
            guard allowed else { denied = true; return }
            _ = MusicLibrary.shared
            LibraryAuthorization.authorized()
            finished = true
            completion()
        }
    }
}

private struct LibraryAuthorizationView: View {
    @ObservedObject var session: LibraryAuthorizationSession

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(session.denied ? "Разрешите доступ к медиатеке" : "Подготовка медиатеки")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if session.denied {
                Text("Разрешение нужно для музыкального интерфейса приложения. Вход в Яндекс выполняется отдельно.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Повторить", action: session.request)
                    .disabled(session.requesting)
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .onAppear(perform: session.request)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            session.request()
        }
    }
}
