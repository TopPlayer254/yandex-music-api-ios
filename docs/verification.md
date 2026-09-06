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

- Xcode 16.4 generated the project with XcodeGen 2.46.0.
- `xcodebuild build-for-testing` compiled the app and XCTest target for generic iOS Simulator.
- `xcodebuild archive` produced an unsigned arm64 device archive.
- The archive was packaged as `dist/MapleMusic-unsigned.ipa`; local SHA-256:
  `d920faa5e7e64df0f2e656d7e223b2b6ba713ef9cef27411d71059a0df856f79`.
- The IPA structure contains `Payload/MapleMusic.app/Info.plist` and no
  `embedded.mobileprovision` or `_CodeSignature` entry.

## Not executed

No Swift/iOS SDK or macOS runtime is available locally. The cloud job performed Swift type checking
and a device archive, but XCTest execution requires a concrete simulator runtime and was not run.
Actual-device login, authenticated catalogue/playback/lossless requests, audio decoding, background
playback and download/relaunch UI checks still require manual testing with the user's account.

XCTest target includes mixed-type API IDs and Cyrillic metadata, LRC offset/multiple tags,
an AES-CTR known-answer vector, account isolation and offline metadata persistence,
download permission checks, PKCE and demo-service checks. These compiled successfully, but are not
reported as executed or passed.

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
