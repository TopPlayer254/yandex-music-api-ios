# Maple Music 0.15

- Player, lyrics and queue share playback controls. The cover animates between its
  expanded and compact positions. The lyrics viewport fades and blurs near its
  lower edge; nearby lines rise with staggered spring motion. Scroll by hand
  to temporarily suspend following. Timed words still use their actual timestamps.
- Long labels cycle through two identical copies with edge fades. Fitting labels
  never start a marquee, and changing the text replaces the previous animation.
- The queue and Wave visualizer use time-indexed four-band PCM analysis of the
  playback file. Until decoded audio is available (for example, HLS-only streams),
  bars remain still. MediaPlayer and Live Activity use actual AVPlayer rate and
  refresh on pause, buffering transitions, and background/foreground changes.
- Local Core Haptics can stop when iOS suspends the engine. When Music Haptics
  is enabled in iOS, the background path publishes the recording's ISRC so
  Apple can play its system track where available.
- Yandex MP3 import obtains a signed loader target using the active account,
  uploads to the selected editable playlist, and confirms the ID by reading
  the playlist. No automatic re-upload after an ambiguous result. Previously
  imported files can be uploaded from their context menu; the device copy is kept.
  Playlist parsing retains full uploaded-track metadata embedded in the response.
- Accounts use separate Keychain slots. Existing offline partitions retain their
  provider/account identifiers. Suggest Less is a reversible filter for in-app
  recommendations and subsequent My Wave batches, without changing favorites.

Protocol references:
- https://yandex.ru/support/music/ru/collection/playlists-and-uploading
- https://github.com/Kay0k1/yandex-music-uploader/blob/main/src/utils/async_uploader.py
- https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfopropertyelapsedplaybacktime

Device verification: upload an owned test MP3 and confirm it appears in the web
playlist; play an older uploaded track; check hardware haptics, Dynamic Island
after pause/background, and gesture and lyric motion against the provided video.
