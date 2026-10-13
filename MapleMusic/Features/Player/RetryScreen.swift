import SwiftUI

struct DiagnosticResponseView: View {
    @ObservedObject private var log = DiagnosticLog.shared
    var body: some View {
        ScrollView {
            Text(log.lastResponse).font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Диагностика")
        .toolbar { Button("Очистить", role: .destructive) { log.clear() }.tint(.red) }
    }
}

struct RetryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var developer: DeveloperSettings
    let message: String
    let actionTitle: String
    let retry: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "arrow.clockwise.circle").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text("Попробуем ещё раз").font(.title.bold())
                    Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                    Button(actionTitle) { dismiss(); retry() }.adaptiveProminentButtonStyle()
                    if developer.showsLiteralCrashResponse {
                        NavigationLink("Ответ сервера") { DiagnosticResponseView() }
                    }
                }
                .padding(28)
            }
            .toolbar { Button("Закрыть") { dismiss() } }
        }
    }
}
