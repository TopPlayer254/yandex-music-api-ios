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
   retaining them. The next device run reported successful startup without that
   crash.
4. A later device run after changing the iPhone language aborted with
   `ML3ExceptionDatabaseDoesNotExist` while initializing `MPMediaLibrary`. The
   cloned app has no Apple Music ML3 database in its sandbox. The bridge now
   initializes MPMediaLibrary with its own metadata provider and namespace.

The simulator host exercises an asynchronous library request with a stack block
and a captured lifetime sentinel. Its ready flag is written only after that
callback succeeds. The expanded host uses an explicit local fixture provider to
check successful MPModel catalogue conversion and MPC change requests, then opens
the complete Maple settings sheet. This does not validate a live Yandex account.

## Native routing

Playback is intercepted at `MPCPlayerChangeRequest`, which actually performs the
commands. `MPCPlayerCommandRequest` only describes a command; the previous hook on
that class did not intercept execution. Numeric command types select Play, Pause,
Next and Previous independently of localized labels. Extended completions return
real MPCPlayerCommandStatus objects; regular completions receive NSError.

The native system-music path is redirected to the current bundle's session.
The backend waits for credential restoration before serving initial catalogue
requests and announces changes after the library finishes loading. Library model
identifiers retain a stable persistent ID and database namespace across copies.

Original Apple onboarding presentations are filtered by controller identity.
The existing native profile button opens Maple settings; the adapter does not
replace navigation bar items used for sorting or folders. The developer settings
include export of the credential-free adapter routing log.

## Branding

The original `InfoPlist.loctable` overrides the root plist's application name.
Packaging now updates the display name, bundle name and alternate name in all
55 localized name entries as well as the root plist. The bundle executable remains
named `Music`; executable filenames do not determine the Home Screen label.

## Verification limits

The downloaded iPhone executable is arm64e and cannot run as an Intel Simulator
application. The available simulator runtime has no original Music.app. Simulator
screenshots therefore show the bridge settings sheet, not the original Music UI.
No successful host check proves that the modified device IPA is crash free.

Backend routing remains experimental and incomplete. Conditional MPModel adapters
and selected HTTP endpoints are implemented; complete MPC playback and Swift
MusicKit coverage have not been established. Legacy MPMediaQuery result-set
enumeration is not ported; catalogue content is supplied through MPModel request
adapters. The local media-library provider supplies identity, metadata and counts,
not an Apple SQLite database. The package report retains
`apple_backend_fully_replaced: false` and `runtime_device_verified: false`.
