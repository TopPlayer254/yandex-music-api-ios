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
                    FallenIceCreamIcon().fill(.secondary).frame(width: 88, height: 88).accessibilityHidden(true)
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

struct MusicErrorBanner: View {
    let title: String
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    FallenIceCreamIcon().fill(.white).frame(width: 26, height: 26).accessibilityHidden(true)
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Открыть подробности ошибки и повторную попытку")
            Button(action: close) {
                Image(systemName: "xmark").font(.subheadline.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Скрыть ошибку")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(Color(red: 0.79, green: 0.16, blue: 0.12).ignoresSafeArea(edges: .top))
    }
}
