import SwiftUI

struct WaveLaunchButton: View {
    let mood: WaveMoodEnergy
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            ZStack {
                WaveMetaballSurface(mood: mood)

                HStack(spacing: 14) {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.18), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Запустить Мою волну")
                            .font(.headline)
                        Text("Цвет настроения · \(mood.title)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "waveform")
                        .font(.title2.weight(.medium))
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
            }
            .frame(height: 76)
            .clipShape(shape)
            .contentShape(shape)
            .adaptiveGlass(in: shape, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Запустить Мою волну, настроение: \(mood.title)")
    }
}

private struct WaveMetaballSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    let mood: WaveMoodEnergy

    var body: some View {
        let palette = palette
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reducesMotion)) { timeline in
            GeometryReader { proxy in
                let time = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 120)
                Rectangle()
                    .fill(.white)
                    .colorEffect(
                        ShaderLibrary.mapleWaveMetaballs(
                            .float2(proxy.size.width, proxy.size.height),
                            .float(time),
                            .color(palette.primary),
                            .color(palette.secondary),
                            .color(palette.tertiary)
                        )
                    )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var palette: (primary: Color, secondary: Color, tertiary: Color) {
        switch mood {
        case .all:
            (.yellow, .pink, .blue)
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
