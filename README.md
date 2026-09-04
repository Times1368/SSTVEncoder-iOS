# SSTVEncoder-iOS

SSTVEncoder-iOS is an independent SwiftUI app that turns a photo into
standards-compatible SSTV audio entirely on the iPhone or iPad. Its encoder is
also available as the reusable, Foundation-only `SSTVKit` Swift package.

The encoder supports 15 VIS modes:

- Robot 36 Color
- Robot 72 Color
- PD 50 / 90 / 120 / 160 / 180 / 240 / 290
- Martin M1 / M2
- Scottie S1 / S2 / DX
- Wraase SC2-180

The complete local flow is photo selection, interactive crop/scale, exact
encoded-raster preview, encoding with progress and cancellation, on-device
playback, and export of the same signal as a 48 kHz mono signed 16-bit PCM WAV.

## Requirements

- iOS 17.0 or newer
- Xcode 15.0.1 or newer (Swift 5.9 toolchain)
- XcodeGen 2.38 or newer
- Python 3 and Pillow 12.3.0 for build-time AppIcon generation

`SWIFT_VERSION: 5.0` in `project.yml` is Xcode's identifier for Swift 5
language mode; the compatibility workflow selects Xcode 15.0.1 and verifies
the Swift 5.9 compiler.

## Generate and open the app

```sh
brew install xcodegen
python3 -m pip install --disable-pip-version-check --no-input "Pillow==12.3.0"
python3 scripts/generate_app_icon.py
cd SSTVEncoder
xcodegen generate --spec project.yml
open SSTVEncoder.xcodeproj
```

The generated `.xcodeproj` is intentionally not committed. The app has no
third-party runtime dependencies.

The icon generator draws a deterministic 1024 px placeholder by default. To
use finished artwork, place an exact 1024 x 1024 PNG at
`SSTVEncoder/Resources/AppIconSource/AppIcon-1024.png`; the same command will
pick it up automatically. On Windows, where project generation is not needed,
run the script with `python` to inspect or prepare the asset catalog. Generated
assets are ignored by Git and recreated by CI.

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

The current app release only creates, plays, and exports audio. It contains no
radio control, CAT, PTT, remote server, network client, microphone capture,
Hamlib, FT8/FT4, or automatic transmission path. Playing the audio into radio
equipment is a separate operator action outside this project.

Automatic VIS decoding is the next phase. It will support imported audio and
an explicitly started microphone receiver for the same 15 modes. Robot36's
`Contrib` label is a category rather than a modulation; its current HF Fax
entry will be implemented as a separate, manually selected IOC 576 / 120 LPM
receiver because radiofax has no VIS header. No microphone permission is added
until that receive phase is implemented and tested.

See [the design](docs/design.md) for protocol timing and architecture, and
[the implementation plan](docs/implementation-plan.md) for the TDD and release
gates. The primary mode reference is JL Barber N7CXI's
[Dayton SSTV specification](https://www.classicsstv.com/downloads/daytonpaper.pdf).
