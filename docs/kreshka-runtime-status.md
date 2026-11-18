# Kreshka original Music UI experiment

Bundle identifier: `dev.hikeri.kreshka.music`. Display name: `Крешка`.
The pinned original device application requires iOS 26.5 or later.

## Device crash regressions

1. A duplicate bridge load caused dyld to reject the executable. The packager now
   reuses the redirected CoreAnalytics load and rejects duplicate library paths,
   preserving the original import ordinals.
2. A generic arm64 framework could not load into the arm64e Music process. The
   framework is now compiled for arm64e; the packager rejects an arm64 substitute.
3. The app reached its UI, then failed with `EXC_ARM_PAC_FAIL` in the MusicKit
   library-request callback called by `KFinish`. Async request, command and artwork
   adapters now explicitly copy incoming Objective-C completion blocks before
   retaining them. This addresses a concrete stack-block lifetime bug. Confirmation
   that it resolves the reported device crash still requires a device run.

The simulator host exercises an asynchronous library request with a stack block
and a captured lifetime sentinel. Its ready flag is written only after that
callback succeeds. The host also opens the bridge's Yandex account sheet.

## Branding

The original `InfoPlist.loctable` overrides the root plist's application name.
Packaging now updates the display name, bundle name and alternate name in all
55 localized name entries as well as the root plist. The bundle executable remains
named `Music`; executable filenames do not determine the Home Screen label.

## Verification limits

The downloaded iPhone executable is arm64e and cannot run as an Intel Simulator
application. The available simulator runtime has no original Music.app. Simulator
screenshots therefore show the bridge account sheet, not the original Music UI.
No successful host check proves that the modified device IPA is crash free.

Backend routing remains experimental and incomplete. Conditional MPModel adapters
and selected HTTP endpoints are implemented; complete MPC playback and Swift
MusicKit coverage have not been established. The package report retains
`apple_backend_fully_replaced: false` and `runtime_device_verified: false`.
