# Verification — 2026-09-09

## Executed locally (Windows)

- Parsed all current Swift source/test files with tree-sitter; no syntax errors after fixes.
- Parsed XcodeGen, xtool and GitHub Actions YAML, resource plists, asset JSON and PCM WAV metadata.
- Downloaded XcodeGen 2.46.0 and verified SHA256:
  `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`.
- Confirmed the upstream `actions/checkout@v7` and `actions/upload-artifact@v7` tags exist.
- Guest `GET https://api.music.yandex.net/account/status`: HTTP 200, JSON.
- Guest `GET https://api.music.yandex.net/search?text=Maple&type=track&page=0`: HTTP 451.
  This is not evidence that authenticated catalogue/playback works from this network.

## Executed in GitHub Actions

- [Workflow run #13](https://github.com/TopPlayer254/yandex-music-api-ios/actions/runs/34384010804)
  used Xcode 26.3 and generated the project with XcodeGen 2.46.0.
- `xcodebuild test` compiled and passed the XCTest suite on an available iPhone simulator.
  The workflow now discovers a registered simulator instead of assuming one fixed device; if a runner
  exposes only the Simulator SDK, it falls back to `build-for-testing` before the device archive.
- `xcodebuild archive` produced an unsigned arm64 device archive after compiling the bounded
  artwork backdrop, dynamic mini-player accessory, immediate playback selection path and the
  SwiftUI/Metal metaball Wave control. The IPA contains `default.metallib`.
- The archive was packaged as `dist/MapleMusic-unsigned.ipa`; local SHA-256:
  `584d4799eea2141573e63f7b472b29095d28790585dd3a6f3a7dbcae11ece55b`.
- The IPA structure contains `Payload/MapleMusic.app/Info.plist` and no
  `embedded.mobileprovision` or `_CodeSignature` entry.
- The packaged app reports bundle ID `com.hikeri.yamusic`, version `0.9.1`, build `13`,
  `UIFileSharingEnabled = true`, and `LSSupportsOpeningDocumentsInPlace = true`.
- Its iPhone orientation list contains only `UIInterfaceOrientationPortrait`; iPad retains
  portrait and landscape orientations.

## Not executed

No Swift/iOS SDK or macOS runtime is available locally. The cloud job performed Swift type checking,
XCTest execution on a concrete simulator, and a device archive.
Actual-device login, authenticated catalogue/playback/lossless requests, audio decoding, background
playback, applying Rotor settings against the live account, shader appearance and download/relaunch
UI checks still require manual testing with the user's account.

XCTest target includes mixed-type API IDs and Cyrillic metadata, LRC offset/multiple tags,
an AES-CTR known-answer vector, account isolation and offline metadata persistence,
bulk deletion that preserves untracked Files documents, download permission checks, PKCE and
demo-service checks, the standard-quality signing vector, and distinct Standard/Lossless choices.
The suite also verifies Genius HTML cleanup, album/artist parsing, legacy search-response compatibility,
and backward decoding of existing offline lyrics metadata.
These tests executed successfully.
The added test also checks the Rotor settings wire values (`active`, `discover`, `not-russian`).

## Protocol references

The adapter is a Swift implementation of the HTTP data formats, not an embedded Python runtime.

- [MarshalX/yandex-music-api](https://github.com/MarshalX/yandex-music-api), inspected commit
  `0fa54f2d32084a9e461bce41890d1c9ab70d91aa`: account/search/tracks/playlists/likes/lyrics/device auth
  and Rotor `settings3` values.
- [Stephanzion/YandexMusicBetaMod](https://github.com/Stephanzion/YandexMusicBetaMod), inspected commit
  `917a2f75f59bf78c7ff3ac61b4c26d45a0c65c58`: localized detection of the Rotor response that
  contains only the `Промокод Upgrade` placeholder.
- [File info discussion](https://github.com/MarshalX/yandex-music-api/issues/656): lossless response format.
- [llistochek/yandex-music-downloader](https://github.com/llistochek/yandex-music-downloader), inspected commit
  `9d33d6aaefae3cb882d02822e59cf0796c33a651`: encraw transport parameters, response key and AES-CTR counter.
- [GitHub macOS runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md):
  Xcode and simulator-runtime inventory for the `macos-15` image.

Public protocol signing constants and device-client parameters can change upstream.
They are not credentials for a user's account. Personal access tokens are obtained at runtime
and stored in the app container with iOS Data Protection, with a best-effort Keychain copy.
Lossless/download requests still require server authorization.
