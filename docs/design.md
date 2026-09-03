# SSTVEncoder-iOS design

Status: approved by the user for implementation

Date: 2026-09-03

## 1. Product boundary

SSTVEncoder-iOS is a standalone iOS 17.0+ application with a reusable
`SSTVKit` Swift package. It prepares a still image, creates an SSTV waveform,
plays that waveform locally, and exports it as WAV.

Version 1 includes Robot 36 Color, Robot 72 Color, Martin M1, and Scottie S1.
It does not receive or decode SSTV and does not contain PTT, CAT, rig control,
Radio Lite networking, microphone capture, background transmission, accounts,
analytics, or cloud storage. Playing an audio file near a radio is an operator
action outside the app; the app never keys a transmitter.

## 2. Platform and repository

- Independent GitHub repository: `Times1368/SSTVEncoder-iOS`.
- Minimum deployment target: iOS 17.0.
- Language mode: Swift 5.9.
- UI: SwiftUI, iPhone-first and iPad-compatible.
- Project generation: XcodeGen 2.38 or newer.
- Runtime dependencies: Apple frameworks only.
- Bundle identifier: `io.github.times1368.sstvencoder`.
- Initial version: `1.0.0 (1)`.

The Radio Lite repository is a pattern reference only. Its XcodeGen baseline,
device build, manual unsigned IPA packaging, and playback completion handling
are useful. None of its Opus, microphone, WebSocket, server, rig, PTT, digital
mode, or transmit-interlock code is imported.

## 3. Repository layout

```text
SSTVKit/
  Package.swift
  Sources/SSTVKit/
  Tests/SSTVKitTests/
SSTVEncoder/
  App/
  Core/
  Features/
  Resources/
  project.yml
SSTVEncoderTests/
scripts/
docs/
.github/workflows/ios.yml
```

`SSTVKit` imports Foundation only. It accepts an exact RGB raster and returns
PCM, so it can later be embedded in another app without SwiftUI or UIKit.
UIKit/CoreGraphics image preparation and AVFoundation playback live in the app
target.

## 4. Protocol model

All modes use a phase-continuous oscillator and a cumulative-time sample clock.
The latter rounds the total elapsed time to a sample index instead of rounding
each pixel independently, preventing line slant from accumulated rounding
error.

### 4.1 Calibration header and VIS

The common header is:

1. 300 ms at 1900 Hz
2. 10 ms at 1200 Hz
3. 300 ms at 1900 Hz
4. 30 ms at 1200 Hz (VIS start)
5. seven 30 ms data bits, least-significant bit first
6. one 30 ms even-parity bit
7. 30 ms at 1200 Hz (VIS stop)

A VIS one is 1100 Hz and zero is 1300 Hz. The header lasts 0.910 seconds.

### 4.2 Mode table

| Mode | VIS | Raster | Picture line sequence | Picture time |
|---|---:|---:|---|---:|
| Robot 36 Color | 8 | 320x240 | 9 ms sync, 3 ms porch, 88 ms Y, 4.5 ms alternating separator, 1.5 ms porch, 44 ms alternating R-Y/B-Y | 36.000 s |
| Robot 72 Color | 12 | 320x240 | 9 ms sync, 3 ms porch, 138 ms Y, 4.5/1.5 ms separator/porch, 69 ms R-Y, 4.5/1.5 ms separator/porch, 69 ms B-Y | 72.000 s |
| Martin M1 | 44 | 320x256 | 4.862 ms sync, 0.572 ms porch, then G/B/R scans of 146.432 ms, each followed by 0.572 ms separator | 114.290176 s |
| Scottie S1 | 60 | 320x256 | one initial 9 ms sync; each line is 1.5 ms separator + 138.240 ms G, 1.5 ms separator + 138.240 ms B, 9 ms sync, 1.5 ms porch, 138.240 ms R | 109.633320 s |

Robot 36 uses 1500 Hz before R-Y on even rows and 2300 Hz before B-Y on odd
rows. Chroma is averaged over each 2x2 pixel block, then repeated for the two
horizontal positions and shared by the two rows. Robot 72 averages chroma over
each horizontal pair and repeats the value for both positions. This implements
the Robot 4:2:0 and 4:2:2 sampling used by established encoders while retaining
the specified 320-position sweep.

For Martin and Scottie, R/G/B values map linearly from 0...255 to
1500...2300 Hz. Robot color components use the limited-range BT.601 equations
published in the Dayton proposal:

```text
Y  = 16  + (65.738 R + 129.057 G + 25.064 B) / 256
RY = 128 + (112.439 R - 94.154 G - 18.285 B) / 256
BY = 128 + (-37.945 R - 74.494 G + 112.439 B) / 256
frequency = 1500 + component * 800 / 255
```

Values are clamped to 0...255 before modulation.

Primary protocol reference: JL Barber N7CXI, [Proposal for SSTV Mode
Specifications](https://www.classicsstv.com/downloads/daytonpaper.pdf), Dayton
SSTV Forum, 20 May 2000. The Robot chroma storage pattern is cross-checked
against Olga Miller's Apache-2.0 SSTV Encoder 2; no source is copied.

## 5. SSTVKit components

### `RGBPixel` and `RGBImage`

Small sendable value types. `RGBImage` validates exact dimensions and stores
row-major 8-bit RGB pixels.

### `SSTVMode`

Owns immutable public metadata: display name, VIS code, raster dimensions,
line duration, picture duration, and total duration. Mode-specific line layout
is centralized in one internal strategy.

### `SSTVEncoder`

An asynchronous, deterministic encoder. It checks cancellation between scan
lines and reports monotonic line-based progress. Its configurable sample rate
defaults to and is constrained to a positive value; the app always uses 48 kHz.
The returned `PCMBuffer` contains mono floating-point samples plus sample-rate
metadata.

### `WAVEncoder`

Quantizes the encoded float samples to signed 16-bit PCM with saturation and
writes an ordinary little-endian RIFF/WAVE file. Playback and export consume
the same `PCMBuffer`; the signal is never synthesized twice.

## 6. Image preparation and crop UI

The selected `UIImage` is orientation-normalized and rendered into the active
mode's exact raster in sRGB. The crop editor has a fixed target aspect ratio,
pinch-to-zoom, drag-to-position, and reset. Blank area is prevented by clamping
the transform to the aspect-fill bounds.

The preview and RGB bytes come from the same prepared bitmap. Changing the
photo, mode, zoom, or crop position invalidates any prior encoding. Martin and
Scottie prepare 320x256; Robot modes prepare 320x240.

`PhotosPicker` loads user-selected data without requesting broad photo-library
access.

## 7. App state and user flow

The main screen is a single guided flow:

```text
Choose photo
  -> crop/scale exact-raster preview
  -> choose mode and inspect resolution/duration
  -> encode with cancellable progress
  -> play/stop locally
  -> export the same PCM as WAV
```

Encode is disabled without a valid image. Play and export are disabled until a
current encoding exists. An operation generation token prevents cancelled or
superseded work from publishing a stale result.

Playback uses an `AVAudioSession` in `.playback` mode and `AVAudioPlayer` over
WAV data made from the current buffer. Interruptions, route invalidation, and
media service reset stop playback and deactivate the session. No microphone
permission is present.

## 8. Tests and quality gates

Tests are written before their corresponding implementation.

`SSTVKitTests` cover:

- all mode dimensions, VIS codes, line times, and total sample counts;
- VIS LSB-first bit order and even parity;
- cumulative sample rounding and continuous oscillator phase;
- RGB and BT.601 component-to-frequency mapping;
- Martin and Scottie channel/line ordering;
- Robot 36 separator alternation and 2x2 chroma averaging;
- Robot 72 component order and horizontal chroma averaging;
- deterministic output and cooperative cancellation;
- RIFF fields, little-endian PCM, saturation, and payload length.

App tests cover crop geometry, invalidation on every input change, monotonic
progress, and rejection of stale task results. A source contract script checks
the iOS 17 target, Swift 5.9 setting, package boundary, WAV format, absence of
microphone/PTT/network entitlements and APIs, and workflow packaging gates.

CI on `macos-15`:

1. validate repository contracts;
2. run `swift test` for `SSTVKit`;
3. generate the Xcode project;
4. build and test the app on an available iPhone simulator;
5. only after tests pass, build for `generic/platform=iOS` with signing fully
   disabled;
6. package `Payload/SSTVEncoder.app` into an unsigned IPA;
7. verify plist metadata, arm64 Mach-O, ZIP paths/CRC, and absence of signing
   or provisioning data;
8. upload IPA, SHA-256, and a verification manifest with `upload-artifact@v4`;
9. download that artifact in a separate job and verify it again.

Windows cannot run Xcode or the Swift toolchain used here. Local validation is
limited to source/contract checks; the GitHub macOS jobs are the authoritative
compile, XCTest, device-build, and packaging evidence.

## 9. Completion criteria

Version 1 is complete only when:

- all four modes produce their exact expected 48 kHz sample counts;
- the app's prepared preview is the encoded raster;
- play and file export work from the same signal;
- the WAV is mono, 48 kHz, signed 16-bit PCM;
- SwiftPM tests, iOS simulator tests, contract checks, and unsigned device build
  all pass in GitHub Actions;
- the downloaded artifact independently passes ZIP, plist, architecture,
  minimum-iOS, and unsigned-state checks;
- the final repository URL, commit SHA, Actions run URL, job conclusions, and
  IPA name/hash/size are recorded for delivery.

