# SSTVEncoder-iOS

SSTVEncoder-iOS is an independent SwiftUI app that turns a photo into
standards-compatible SSTV audio entirely on the iPhone or iPad. Its encoder is
also available as the reusable, Foundation-only `SSTVKit` Swift package.

Version 1 supports:

- Robot 36 Color
- Robot 72 Color
- Martin M1
- Scottie S1

The complete local flow is photo selection, interactive crop/scale, exact
encoded-raster preview, encoding with progress and cancellation, on-device
playback, and export of the same signal as a 48 kHz mono signed 16-bit PCM WAV.

## Requirements

- iOS 17.0 or newer
- Xcode 15.0.1 or newer (Swift 5.9 toolchain)
- XcodeGen 2.38 or newer

`SWIFT_VERSION: 5.0` in `project.yml` is Xcode's identifier for Swift 5
language mode; the compatibility workflow selects Xcode 15.0.1 and verifies
the Swift 5.9 compiler.

## Generate and open the app

```sh
brew install xcodegen
cd SSTVEncoder
xcodegen generate --spec project.yml
open SSTVEncoder.xcodeproj
```

The generated `.xcodeproj` is intentionally not committed. The app has no
third-party runtime dependencies.

## Tests

Run the portable encoder tests on macOS:

```sh
swift test --package-path SSTVKit --parallel
```

GitHub Actions also generates the Xcode project and runs the app tests on an
iOS 17 simulator with Xcode 15.0.1, repeats tests with Xcode 16.4, then builds
for `generic/platform=iOS`. Packaging is gated on both test jobs.

## Unsigned IPA artifact

A successful workflow manually packages `Payload/SSTVEncoder.app` and uploads
`SSTVEncoder.ipa`, its SHA-256 file, and a verification manifest. A separate
job downloads the artifact and rechecks ZIP safety and CRC, bundle metadata,
arm64-only Mach-O architecture, iOS 17 minimum version, and the absence of a
code signature or provisioning profile.

The artifact is deliberately unsigned. It cannot be installed through Apple's
normal distribution channels without being signed by the person installing or
distributing it.

## Safety and scope

The app only creates, plays, and exports audio. It contains no radio control,
CAT, PTT, remote server, network client, microphone capture, Hamlib, FT8/FT4,
or automatic transmission path. Playing the audio into radio equipment is a
separate operator action outside this project.

See [the design](docs/design.md) for protocol timing and architecture, and
[the implementation plan](docs/implementation-plan.md) for the TDD and release
gates. The primary mode reference is JL Barber N7CXI's
[Dayton SSTV specification](https://www.classicsstv.com/downloads/daytonpaper.pdf).
