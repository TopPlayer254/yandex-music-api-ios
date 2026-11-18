# Kreshka: original Music UI experiment

Bundle ID of the modified app: `dev.hikeri.kreshka.music`.

This build keeps the iOS 26.5.1 Music executable/UI and injects
`KreshkaBridge.framework`. It is an experimental interoperability build, not a
completed backend port. The package report deliberately records
`apple_backend_fully_replaced: false` and `runtime_device_verified: false`.

Implemented boundaries:

- The existing Maple `AppContainer`, `MusicService`, Yandex/gateway clients,
  credential vault, offline store, downloads and `PlayerStore` live in the bridge.
- Runtime-checked `MPModelRequest` adapters create native song/album/artist/
  playlist model responses from our service. Unsupported signatures are logged.
- Apple Music catalogue HTTP requests from NSURLSession are adapted to our
  service. Unsupported Apple endpoints fail explicitly; their original online
  implementation is not used by this protocol handler.
- Compatible `MPCPlayerCommandRequest.performWithCompletion:` implementations
  are routed to PlayerStore. Other MPC/Swift MusicKit paths remain unverified;
  this is not complete coverage of the original player's command/data pipeline.
- A Yandex account sheet is offered at startup; native navigation screens get
  an account button. Runtime logs are saved to `Documents/Kreshka/bridge.log`.

The packager appends one library load without renumbering the original imports,
removes original code signatures/profiles, removes system extensions/XPC bundles,
preserves original UI resources, and emits an unsigned IPA for external signing.
Private UI frameworks remain, as requested. Library loading alone does not
replace privileged Apple XPC operations; those paths require device debugging.

Build:

1. GitHub Actions `Build original Music UI bridge IPA` builds the framework with
   Xcode 26.3 on `macos-15-intel`.
2. A pinned open-source extractor reads the original app from Apple's official
   IPSW through HTTP ranges. Apple binaries are not committed to the repository.
3. A separate simulator host loads the same bridge and initializes its backend;
   it must remain alive and write `bridge-smoke.ready`.
4. If the Simulator runtime includes its own native Music.app, the workflow also
   tries patching and launching that app. Otherwise the report explicitly marks
   that test unavailable. The iPhone arm64e binary is never relabelled as a
   Simulator binary.

An Intel Simulator smoke test is evidence about bridge startup, not evidence
that the iPhone Music.app or all native player routes work. Inspect
`simulator-status.json`, the package report, and runtime logs with the IPA.

APFS zlib resource-fork support in `Extract/resource-zlib.patch` is a local
addition to MIT-licensed `blacktop/go-apfs` v1.0.32. The extraction command uses
`blacktop/ipsw` commit `d53e699459d2c45799efc17ddf5b63b65b41ac7e`.
