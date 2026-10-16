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
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reducesMotion || scenePhase != .active)) { timeline in
            let time = clock.displayTime(at: timeline.date, playing: playing)
            if #available(iOS 18.0, *) {
                words.enumerated().reduce(Text("")) { result, pair in
                    result + Text(pair.element.text).customAttribute(LyricWordAttribute(index: pair.offset, word: pair.element))
                }
                .foregroundStyle(.white)
                .textRenderer(LyricWordRenderer(time: time, reducesMotion: reducesMotion))
            } else {
                words.reduce(Text("")) { result, word in
                    result + Text(word.text).foregroundColor(.white.opacity(word.progress(at: time) > 0 ? 1 : 0.38))
                }
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
                    widths[attribute.index, default: 0] += run.typographicBounds.rect.width
                }
            }
        }
        var advances: [Int: CGFloat] = [:]
        for line in layout {
            for run in line {
                guard let attribute = run[LyricWordAttribute.self] else { context.draw(run); continue }
                let progress = attribute.word.progress(at: time)
                let bounds = run.typographicBounds.rect
                let advance = advances[attribute.index, default: 0]
                advances[attribute.index] = advance + bounds.width
                let reveal = min(max(CGFloat(progress) * widths[attribute.index, default: 0] - advance, 0), bounds.width)
                var base = context
                // Lift during the word, return without moving neighbouring text.
                if !reducesMotion { base.translateBy(x: 0, y: -1.5 * sin(progress * .pi)) }
                var dim = base
                dim.opacity *= 0.38
                dim.draw(run)
                guard reveal > 0 else { continue }
                var lit = base
                lit.clip(to: Path(CGRect(x: bounds.minX, y: bounds.minY - 3, width: reveal, height: bounds.height + 6)))
                if !reducesMotion, progress > 0, progress < 1 {
                    var glow = lit
                    glow.opacity *= 0.4
                    glow.addFilter(.blur(radius: 3))
                    glow.draw(run)
                }
                lit.draw(run)
            }
        }
    }
}
