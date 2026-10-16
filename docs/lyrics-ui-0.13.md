# Lyrics and appearance — 0.13

This is an independent SwiftUI implementation, not extracted Apple Music code.
The GitHub search found Apple-Music-style recreations (AMLL and
HuangRunHua/Apple-Music-Lyric-Animation), not a verified IPA animation disassembly.
No code from these projects is incorporated. Exact visual parity is unverified.

- Native TextRenderer on iOS 18+: timed word fill, subtle lift/glow, native text wrapping.
- iOS 17: discrete word highlighting. Untimed lyrics remain line-based on every OS.
- Only the active word-timed line observes playback ticks. Interpolation stops on
  pause and is bounded to 300 ms when samples stop; Reduce Motion disables lift/glow.
- Enhanced LRC and gateway JSON words preserve timing in offline Codable lyrics.
- Player album header centers short labels, retaining marquee for overflow.
- Primary glass actions receive explicit fill tint; standalone tint and button labels
  are contrast-adjusted separately using sRGB relative luminance (4.5:1 on the nominal
  black/white surface or solid button fill). Actual glass/background appearance still
  requires device validation.
- Recoverable errors over existing content use a red top-safe-area banner. Tap for
  details; dismiss does not clear other error categories. Empty screens respect the
  Developer retry-screen option. The fallen-ice-cream symbol is a vector interpretation
  of the user's reference, not a fatal-crash interception mechanism.

Sources consulted:
- https://developer.apple.com/videos/play/wwdc2024/10151/
- https://developer.apple.com/documentation/swiftui/textrenderer
- https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle
- https://github.com/amll-dev/applemusic-like-lyrics
- https://github.com/HuangRunHua/Apple-Music-Lyric-Animation

Manual QA after installing the IPA: yellow/blue/custom/album colors in light and dark
mode, short/long album headers, paused/playing/seek/backward word highlighting, opening
lyrics mid-song, large Dynamic Type, Reduce Motion, red banner during playback and while
browsing, close/details/retry, failure without cached content. No pixel-exact Apple Music
comparison or actual-device visual pass has been performed on Windows.
