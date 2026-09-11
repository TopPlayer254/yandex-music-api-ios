import CoreGraphics
import SwiftUI
import UIKit

struct WaveLaunchButton: View {
    let artwork: Artwork
    let mood: WaveMoodEnergy
    let isPlaying: Bool
    let isBuffering: Bool
    let action: () -> Void
    let settingsAction: () -> Void

    @State private var artworkImage: UIImage?
    @State private var usesDarkForeground = false

    var body: some View {
        ZStack {
            WaveArtworkSurface(image: artworkImage, mood: mood)

            Button(action: action) {
                HStack(spacing: 13) {
                    if isBuffering {
                        ProgressView()
                            .controlSize(.large)
                            .tint(foregroundColor)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text("Моя волна")
                }
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(foregroundColor)
                .shadow(color: oppositeColor.opacity(0.12), radius: 4, y: 1)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Пауза Моей волны" : "Запустить Мою волну")

            VStack {
                Spacer()
                Button(action: settingsAction) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(foregroundColor)
                        .frame(width: 46, height: 46)
                        .adaptiveGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Настроить Мою волну")
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 370)
        .task(id: artwork.url) {
            await loadArtwork()
        }
    }

    private var foregroundColor: Color {
        usesDarkForeground ? .black : .white
    }

    private var oppositeColor: Color {
        usesDarkForeground ? .white : .black
    }

    private func loadArtwork() async {
        guard let url = artwork.url else {
            artworkImage = nil
            usesDarkForeground = false
            return
        }
        let loaded: UIImage?
        if let cached = ArtworkImageCache.shared.cachedImage(for: url) {
            loaded = cached
        } else {
            loaded = await ArtworkImageCache.shared.image(for: url)
        }
        guard !Task.isCancelled, artwork.url == url else { return }
        artworkImage = loaded
        usesDarkForeground = loaded.map(Self.hasLightAverage) ?? false
    }

    private static func hasLightAverage(_ image: UIImage) -> Bool {
        guard let source = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.58
    }
}

private struct WaveArtworkSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    let image: UIImage?
    let mood: WaveMoodEnergy

    var body: some View {
        let palette = palette
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducesMotion)) { timeline in
              ZStack {
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.mapleWaveAura(
                            .float2(proxy.size.width, proxy.size.height),
                            .float(reducesMotion ? 0 : animationTime(timeline.date)),
                            .color(palette.primary),
                            .color(palette.secondary),
                            .color(palette.tertiary)
                        )
                    )
                if let image {
                        artwork(image, size: proxy.size)
                            .layerEffect(
                                ShaderLibrary.mapleWaveGlass(
                                    .float2(proxy.size.width, proxy.size.height),
                                    .float(reducesMotion ? 0 : animationTime(timeline.date)),
                                    .color(palette.primary),
                                    .color(palette.secondary),
                                    .color(palette.tertiary)
                                ),
                                maxSampleOffset: CGSize(width: 24, height: 24)
                            )
                } else {
                        Rectangle()
                            .fill(.white)
                            .colorEffect(
                                ShaderLibrary.mapleWaveMetaballs(
                                    .float2(proxy.size.width, proxy.size.height),
                                    .float(reducesMotion ? 0 : animationTime(timeline.date)),
                                    .color(palette.primary),
                                    .color(palette.secondary),
                                    .color(palette.tertiary)
                                )
                            )
                }
              }
              .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func artwork(_ image: UIImage, size: CGSize) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func animationTime(_ date: Date) -> TimeInterval {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120)
    }

    private var palette: (primary: Color, secondary: Color, tertiary: Color) {
        switch mood {
        case .all:
            (.purple, .pink, .indigo)
        case .fun:
            (.orange, .pink, .yellow)
        case .active:
            (.red, .orange, .purple)
        case .calm:
            (.cyan, .blue, .indigo)
        case .sad:
            (.indigo, .blue, Color(uiColor: .systemGray))
        }
    }
}
