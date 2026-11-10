# Music Haptics

Settings → Music Haptics offers an opt-in local mode and Apple's system mode.
Local mode decodes the actual audio file to mono 22.05 kHz PCM, processes every sample
into 10 ms bins, and combines RMS, low-pass bass energy (180 Hz) and positive energy
changes. Silence stays silent. Features are content-hash cached independently of audio,
artwork and lyrics. No audio is uploaded. Versioned cache directories invalidate changed
algorithms. The first calculation is asynchronous and may finish after playback starts.

Core Haptics runs continuous events with intensity/sharpness curves in four-second
segments. The playback clock corrects drift and restarts segments after seeks; pause,
buffering, stop, track/account changes stop local haptics. Strength modifies playback,
not cached features. Hardware, engine interruption and OS background restrictions apply.
This is signal analysis, not source separation or Apple's proprietary haptic mastering.
HLS without a local audio file cannot use this analyzer.

The public Apple SDK exposes system activation/status and track availability by ISRC;
it does not expose its generator or per-app strength. System mode supplies ISRC to Now
Playing only when the in-app toggle is enabled. It also needs the system accessibility
setting enabled and an Apple haptic track for that ISRC. Missing ISRC is reported rather
than guessed from a title. No private APIs or Apple Music credentials are used.

Storage clears downloaded audio for the active account separately from cached lyrics.
Artwork and hash-only haptic features have global caches. Visible artwork and a running
track may remain in memory; clearing lyrics/haptics also drops their active player copy.

References:
- https://developer.apple.com/documentation/mediaaccessibility/music-haptics
- https://developer.apple.com/documentation/corehaptics/chhapticparametercurve
- https://developer.apple.com/documentation/corehaptics/chhapticengine

Device QA required: Taptic Engine feel, strength, wired/Bluetooth routes, lock screen,
interruption recovery, seek/pause/resume, exact timing against audible transients and
Apple system haptic availability. Simulator builds cannot validate physical vibration.
