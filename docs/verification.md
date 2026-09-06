# Verification — 2026-09-06

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

- [Workflow run #5](https://github.com/TopPlayer254/yandex-music-api-ios/actions/runs/34031465286)
  used Xcode 26.3 and generated the project with XcodeGen 2.46.0.
- `xcodebuild test` compiled and passed the XCTest suite on iPhone 16 Pro / iOS 26.2.
- `xcodebuild archive` produced an unsigned arm64 device archive.
- The archive was packaged as `dist/MapleMusic-unsigned.ipa`; local SHA-256:
  `a46bd79a279f4aad04669e586c28e789c7f12b17ee9337c39e91a130bc9b9179`.
- The IPA structure contains `Payload/MapleMusic.app/Info.plist` and no
  `embedded.mobileprovision` or `_CodeSignature` entry.
- The packaged app reports bundle ID `com.hikeri.yamusic`, version `0.4.0`, build `5`,
  `UIFileSharingEnabled = true`, and `LSSupportsOpeningDocumentsInPlace = true`.

## Not executed

No Swift/iOS SDK or macOS runtime is available locally. The cloud job performed Swift type checking,
XCTest execution on a concrete simulator, and a device archive.
Actual-device login, authenticated catalogue/playback/lossless requests, audio decoding, background
playback and download/relaunch UI checks still require manual testing with the user's account.

XCTest target includes mixed-type API IDs and Cyrillic metadata, LRC offset/multiple tags,
an AES-CTR known-answer vector, account isolation and offline metadata persistence,
bulk deletion that preserves untracked Files documents, download permission checks, PKCE and
demo-service checks. These tests executed successfully.

## Protocol references

The adapter is a Swift implementation of the HTTP data formats, not an embedded Python runtime.

- [MarshalX/yandex-music-api](https://github.com/MarshalX/yandex-music-api), inspected commit
  `0fa54f2d32084a9e461bce41890d1c9ab70d91aa`: account/search/tracks/playlists/likes/lyrics/device auth.
- [File info discussion](https://github.com/MarshalX/yandex-music-api/issues/656): lossless response format.
- [llistochek/yandex-music-downloader](https://github.com/llistochek/yandex-music-downloader), inspected commit
  `9d33d6aaefae3cb882d02822e59cf0796c33a651`: encraw transport parameters, response key and AES-CTR counter.
- [GitHub macOS runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md):
  Xcode and simulator-runtime inventory for the `macos-15` image.

Public protocol signing constants and device-client parameters can change upstream.
They are not credentials for a user's account. Personal access tokens are obtained at runtime
and stored only in the device Keychain. Lossless/download requests still require server authorization.
