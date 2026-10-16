import SwiftUI

/// Only the active, word-timed line subscribes to the playback clock.
struct LyricLineView: View {
    let line: LyricsLine
    let active: Bool
    let playing: Bool
    let clock: PlaybackClock

    var body: some View {
        Group {
            if active, let words = line.words, !words.isEmpty,
               words.map(\.text).joined() == line.text {
                TimedWordsView(words: words, playing: playing, clock: clock)
            } else {
                Text(line.text).foregroundStyle(.white.opacity(active ? 1 : 0.38))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.text)
    }
}

private struct TimedWordsView: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.scenePhase) private var scenePhase
    let words: [LyricsWord]
    let playing: Bool
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        if #available(iOS 18.0, *) {
            let text = words.enumerated().reduce(Text("")) { result, pair in
                result + Text(pair.element.text).customAttribute(LyricWordAttribute(index: pair.offset, word: pair.element))
            }
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing || reducesMotion || scenePhase != .active)) { timeline in
                text
                .foregroundStyle(.white)
                .textRenderer(LyricWordRenderer(time: clock.displayTime(at: timeline.date, playing: playing), reducesMotion: reducesMotion))
            }
        } else {
            words.reduce(Text("")) { result, word in
                result + Text(word.text).foregroundColor(.white.opacity(word.progress(at: clock.time) > 0 ? 1 : 0.38))
            }
        }
    }
}

@available(iOS 18.0, *)
private struct LyricWordAttribute: TextAttribute {
    let index: Int
    let word: LyricsWord
}

@available(iOS 18.0, *)
private struct LyricWordRenderer: TextRenderer {
    var time: TimeInterval
    let reducesMotion: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // One word can span several runs/lines (font fallback, wrapping, emoji).
        // Accumulate its advance so the highlight does not restart on each run.
        var widths: [Int: CGFloat] = [:]
        for line in layout {
            for run in line {
                if let attribute = run[LyricWordAttribute.self] {
                    widths[attribute.index, default: 0] += run.reduce(CGFloat.zero) { $0 + $1.typographicBounds.rect.width }
                }
            }
        }
        var advances: [Int: CGFloat] = [:]
        for line in layout {
            for run in line {
                guard let attribute = run[LyricWordAttribute.self] else { context.draw(run); continue }
                let progress = attribute.word.progress(at: time)
                for glyph in run {
                    let width = glyph.typographicBounds.rect.width
                    let advance = advances[attribute.index, default: 0]
                    advances[attribute.index] = advance + width
                    let phase = LyricGlyphMotion.phase(wordProgress: progress, center: Double(advance + width / 2),
                                                       wordWidth: Double(widths[attribute.index, default: 0]))
                    let lift = reducesMotion ? 0 : sin(phase * .pi)
                    var letter = context
                    letter.opacity *= 0.38 + 0.62 * phase
                    letter.translateBy(x: 0, y: -2 * lift)
                    if lift > 0 {
                        var glow = letter
                        glow.opacity *= 0.2 * lift
                        glow.addFilter(.blur(radius: 3))
                        glow.draw(glyph)
                    }
                    letter.draw(glyph)
                }
            }
        }
    }
}

#Preview("Пословная строка — пауза") {
    let clock = PlaybackClock()
    let _ = { clock.time = 1.35 }()
    LyricLineView(
        line: LyricsLine(time: 0, text: "Моя волна с тобой", words: [
            LyricsWord(text: "Моя ", start: 0, end: 0.8),
            LyricsWord(text: "волна ", start: 0.8, end: 2),
            LyricsWord(text: "с тобой", start: 2, end: 3.5)
        ]),
        active: true, playing: false, clock: clock
    )
    .font(.title2.bold())
    .padding(28)
    .background(.black)
}
