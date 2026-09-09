import Combine
import SwiftUI
import UIKit

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case yandexYellow
    case musicRed
    case orange
    case blue
    case violet
    case green
    case graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .yandexYellow: "Классический жёлтый"
        case .musicRed: "Музыка"
        case .orange: "Оранжевый"
        case .blue: "Синий"
        case .violet: "Фиолетовый"
        case .green: "Зелёный"
        case .graphite: "Графитовый"
        }
    }

    var color: Color {
        switch self {
        case .yandexYellow: Color(red: 1.00, green: 0.80, blue: 0.00)
        case .musicRed: Color(red: 0.94, green: 0.18, blue: 0.29)
        case .orange: .orange
        case .blue: .blue
        case .violet: .purple
        case .green: .green
        case .graphite: Color(uiColor: .systemGray)
        }
    }
}

enum InterfaceStyleChoice: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Авто"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var accent: AccentColorChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent-color") }
    }

    @Published var interfaceStyle: InterfaceStyleChoice {
        didSet { UserDefaults.standard.set(interfaceStyle.rawValue, forKey: "interface-style") }
    }

    init() {
        accent = AccentColorChoice(rawValue: UserDefaults.standard.string(forKey: "accent-color") ?? "") ?? .yandexYellow
        interfaceStyle = InterfaceStyleChoice(
            rawValue: UserDefaults.standard.string(forKey: "interface-style") ?? ""
        ) ?? .automatic
    }

    var tint: Color { accent.color }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let height: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    init(_ text: String, font: Font, color: Color, height: CGFloat) {
        self.text = text
        self.font = font
        self.color = color
        self.height = height
    }

    var body: some View {
        GeometryReader { proxy in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    GeometryReader { textProxy in
                        Color.clear.preference(key: MarqueeTextWidthKey.self, value: textProxy.size.width)
                    }
                }
                .offset(x: offset)
                .frame(maxHeight: .infinity, alignment: .center)
                .onAppear { containerWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in containerWidth = width }
        }
        .frame(height: height)
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
        .task(id: "\(text)|\(Int(textWidth))|\(Int(containerWidth))") {
            offset = 0
            let overflow = max(textWidth - containerWidth, 0)
            guard overflow > 8 else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: max(3.5, Double(overflow / 24))).repeatForever(autoreverses: true)) {
                offset = -overflow
            }
        }
        .accessibilityLabel(text)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        switch cleaned.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case 8:
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255
            )
        default:
            self = Color(uiColor: .secondarySystemBackground)
        }
    }
}

extension TimeInterval {
    var musicTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Int {
    var russianTrackCount: String {
        let mod100 = self % 100
        let mod10 = self % 10
        let noun: String
        if (11 ... 14).contains(mod100) {
            noun = "треков"
        } else if mod10 == 1 {
            noun = "трек"
        } else if (2 ... 4).contains(mod10) {
            noun = "трека"
        } else {
            noun = "треков"
        }
        return "\(self) \(noun)"
    }
}

private struct AdaptiveGlassModifier<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.5))
        }
    }
}

extension View {
    func adaptiveGlass<GlassShape: Shape>(in shape: GlassShape, interactive: Bool = false) -> some View {
        modifier(AdaptiveGlassModifier(shape: shape, interactive: interactive))
    }

    @ViewBuilder
    func adaptiveProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func adaptiveSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

struct ArtworkView: View {
    let artwork: Artwork
    var cornerRadius: CGFloat = 12
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var finishedURL: URL?

    var body: some View {
        let cachedImage = artwork.url.flatMap { ArtworkImageCache.shared.cachedImage(for: $0) }
        let displayedImage = loadedURL == artwork.url ? image ?? cachedImage : cachedImage
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let displayedImage {
                Image(uiImage: displayedImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = artwork.url, finishedURL != url {
                ProgressView().controlSize(.small)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: artwork.url) {
            guard let url = artwork.url else {
                image = nil
                loadedURL = nil
                finishedURL = nil
                return
            }
            if let cached = ArtworkImageCache.shared.cachedImage(for: url) {
                image = cached
                loadedURL = url
                finishedURL = url
                return
            }
            image = nil
            loadedURL = nil
            finishedURL = nil
            let loaded = await ArtworkImageCache.shared.image(for: url)
            guard !Task.isCancelled, artwork.url == url else { return }
            image = loaded
            loadedURL = url
            finishedURL = url
        }
    }

    private var placeholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

struct TrackRow: View {
    @EnvironmentObject private var appearance: AppearanceSettings
    let track: Track
    let isDownloaded: Bool
    let isDownloading: Bool
    let play: () -> Void
    let toggleDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ArtworkView(artwork: track.artwork, cornerRadius: 7)
                        .frame(width: 52, height: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(track.title).lineLimit(1)
                            if track.isExplicit {
                                Image(systemName: "e.square.fill").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .font(.body)
                        Text("\(track.artist.name) · \(track.albumTitle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isDownloading {
                ProgressView().controlSize(.small)
            } else {
                Button(action: toggleDownload) {
                    Image(systemName: isDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(isDownloaded ? appearance.tint : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!track.downloadAllowed)
                .accessibilityLabel(isDownloaded ? "Удалить загрузку" : "Загрузить")
            }
        }
        .contentShape(Rectangle())
        .contextMenu { TrackActions(track: track) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Воспроизвести", play)
    }
}

struct TrackActions: View {
    @EnvironmentObject private var catalog: CatalogStore
    let track: Track

    var body: some View {
        Button {
            Task { await catalog.toggleFavorite(track) }
        } label: {
            Label(catalog.isFavorite(track) ? "Убрать из любимого" : "Добавить в любимое", systemImage: "heart")
        }
        Menu("Добавить в плейлист") {
            ForEach((catalog.library?.playlists ?? []).filter(\.isEditable)) { playlist in
                Button(playlist.name) { Task { await catalog.add(track, to: playlist) } }
            }
        }
    }
}

struct AccountToolbarButton: View {
    @EnvironmentObject private var auth: AuthStore
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            ZStack {
                Circle()
                    .fill(.quaternary)
                switch auth.state {
                case let .signedIn(profile):
                    AsyncImage(url: profile.avatarURL) { phase in
                        if case let .success(image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                        }
                    }
                default:
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel("Учётная запись")
    }
}
