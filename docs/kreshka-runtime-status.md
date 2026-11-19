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
5. Fix 4 reached a separate native startup query,
   `filterAvailableContentGroups:withOptions:`. Its original implementation
   creates MPMediaLibraryView and enters `_MediaLibrary_coreLibrary`, which
   cannot use our database-free provider. The reported crash is a NULL string
   passed to `std::string`, not a new entitlement failure. Content-group queries
   for the bridge provider now return an unsigned bitmask derived from the
   catalogue. Other providers retain the original implementation.
6. Fix 6 on a clean device installation (`Music-2026-11-20-003430.ips`)
   traps in MusicKitInternal about 0.18 seconds after launch. The return address
   `Music+0x1c070` resolves to the call of
   `MusicDownloadedSongCatalogStore.shared`; this is a separate failure from
   the earlier public MusicKit model conversion. The adapter log contains no
   backend-ready or catalogue requests before this crash. Fix 7 skips the pinned
   original executable's isolated metadata/shared/activate/release sequence at
   file offsets `0x1c060..<0x1c080`, branching to the existing continuation.
   Yandex downloads use the existing Maple OfflineStore instead. The packager
   checks the original executable SHA-256 and all 32 instruction bytes before
   patching, keeps the executable size and surrounding instructions, and does
   not patch arbitrary MusicKitInternal methods or Swift calling conventions.

Fix 7 reuses the exact framework from Fix 6 (source `8605e36`); it changes only
the launch sequence in the original Music executable. Regression checks cover
the branch destination, unchanged surrounding bytes, idempotence and rejection
of mismatched/truncated images. The original arm64e launch cannot be verified on
the Intel Simulator, so a device launch confirmation is still required. The log
supplied with this crash covers the early launch failure, not the reported empty
home/library behavior after successful startup.

The regression host calls that exact native selector before catalogue loading
with no databasePath, then checks populated filtering on a background queue.
It verifies requested group masks rather than returning every group or zero for
all requests. `_MediaLibrary_coreLibrary` is not hooked as an Objective-C object:
its ABI returns a C++ shared_ptr.

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

The subsequent device recording still showed empty native lists/home, failed
playlist creation, recurring onboarding and a queue crash. A later crash report
(`233616`) contains a Swift assertion in MusicKit while processing a collection;
its faulting stack is not a UIKit presentation stack. Model identifiers now use
concrete song/album/artist/playlist kinds. The public MusicKit conversion checks
pass, but this crash hypothesis still needs a device confirmation before the
reported failure is called fixed.

Native playlist-edit operations now delegate creation to the existing Yandex
service. The expanded regression test exercises the SDK operation and public
MusicLibraryRequest APIs, including item IDs. Earlier tests only checked the
MPModel response objects and missed this conversion boundary.

The clean simulator initially denied media-library permission; granting it then
revealed MusicKit's check for an installed com.apple.Music app. The user's device
does have the stock application. A separate simulator-only presence fixture
supplies the missing installed-app dependency; it has no Apple UI, catalogue or
playback implementation and is excluded from the device framework/IPA.

The Debug simulator run for source `8605e36` completed successfully:
[GitHub Actions run 44616015989](https://github.com/TopPlayer254/yandex-music-api-ios/actions/runs/44616015989).
The downloaded diagnostics artifact `14576592548` contains the ready flag,
settings screenshot and explicit passing markers for public MusicKit song,
artist, album and playlist IDs; native SDK playlist creation; MPC Play/Pause;
library content-group filtering; callback lifetime; toolbar preservation; and
onboarding/settings fixtures. The service is a local fixture, so native playlist
creation here verifies routing and callback ABI, not a write to Yandex.

Fix 6 device IPA SHA-256:
`35e16ca3e5b8a78aa756e90f8d588584618a01729cfcfbfab8ceb68490d3aa14`.
Its main executable retains 138 unique library dependencies, one bridge load,
the real arm64e framework, and the updated name in all 55 localized entries.
The simulator presence fixture is not packaged in the IPA.

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
