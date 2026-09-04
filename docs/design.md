# SSTVEncoder-iOS design

Status: version 1 shipped; expanded encoding and receiving roadmap approved

Date: 2026-09-04

## 1. Product boundary

SSTVEncoder-iOS is a standalone iOS 17.0+ application with a reusable
`SSTVKit` Swift package. It prepares a still image, creates an SSTV waveform,
plays that waveform locally, and exports it as WAV.

Version 1 includes Robot 36 Color, Robot 72 Color, Martin M1, and Scottie S1.
The expanded encoder adds PD 50/90/120/160/180/240/290, Martin M2, Scottie
S2/DX, and Wraase SC2-180. These are the 15 VIS-identified color modes exposed
by the first encoder expansion.

Receiving is a separate phase. It will add automatic VIS detection and
progressive decoding for the same 15 modes, with both imported audio and an
explicitly started live microphone input. The microphone is never used by the
encoder and will only be requested when the user starts receiving. Raw input
audio is processed in memory rather than retained. The receiver will also
offer a manually selected `Contrib / HF Fax` profile. `Contrib` is a category
label used by Robot36, not an SSTV mode; HF Fax has no VIS header and therefore
cannot be selected by VIS auto-detection.

No phase contains PTT, CAT, rig control, Radio Lite networking, background
transmission, accounts, analytics, or cloud storage. Playing generated audio
near a radio is an operator action outside the app; the app never keys a
transmitter.

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

### 4.2 RGB mode table

| Mode | VIS | Raster | Channel scan | Radio lines | Picture time |
|---|---:|---:|---:|---:|---:|
| Robot 36 Color | 8 | 320x240 | 88 ms Y + 44 ms alternating chroma | 240 | 36.000000 s |
| Robot 72 Color | 12 | 320x240 | 138 ms Y + 69 ms R-Y + 69 ms B-Y | 240 | 72.000000 s |
| Martin M1 | 44 | 320x256 | 146.432 ms per G/B/R channel | 256 | 114.290176 s |
| Martin M2 | 40 | 320x256 | 73.216 ms per G/B/R channel | 256 | 58.060288 s |
| Scottie S1 | 60 | 320x256 | 138.240 ms per G/B/R channel | 256 | 109.633320 s |
| Scottie S2 | 56 | 320x256 | 88.064 ms per G/B/R channel | 256 | 71.098152 s |
| Scottie DX | 76 | 320x256 | 345.600 ms per G/B/R channel | 256 | 268.885800 s |
| Wraase SC2-180 | 55 | 320x256 | 235.000 ms per R/G/B channel | 256 | 182.021760 s |

Martin modes use a 4.862 ms sync, a 0.572 ms porch, G/B/R scans, and a
0.572 ms separator after every scan. Scottie modes use one initial 9 ms sync;
each regular line is a 1.5 ms separator and Green scan, a 1.5 ms separator and
Blue scan, a 9 ms sync, a 1.5 ms porch, then the Red scan. Wraase SC2-180 uses
a 5.5225 ms sync, a 0.5 ms porch, then contiguous Red, Green, and Blue scans.

### 4.3 PD mode table

One PD radio line carries two raster rows. It contains a 20 ms sync, a 2.08 ms
porch, the first luminance row, vertically averaged R-Y, vertically averaged
B-Y, and the second luminance row. Chroma has one sample per horizontal pixel;
only the two raster rows are averaged.

| Mode | VIS | Raster | Channel scan | Radio-line time | Picture time |
|---|---:|---:|---:|---:|---:|
| PD 50 | 93 | 320x256 | 91.520 ms | 388.160 ms | 49.684480 s |
| PD 90 | 99 | 320x256 | 170.240 ms | 703.040 ms | 89.989120 s |
| PD 120 | 95 | 640x496 | 121.600 ms | 508.480 ms | 126.103040 s |
| PD 160 | 98 | 512x400 | 195.584 ms | 804.416 ms | 160.883200 s |
| PD 180 | 96 | 640x496 | 183.040 ms | 754.240 ms | 187.051520 s |
| PD 240 | 97 | 640x496 | 244.480 ms | 1000.000 ms | 248.000000 s |
| PD 290 | 94 | 800x616 | 228.800 ms | 937.280 ms | 288.682240 s |

Robot 36 uses 1500 Hz before R-Y on even rows and 2300 Hz before B-Y on odd
rows. Chroma is averaged over each 2x2 pixel block, then repeated for the two
horizontal positions and shared by the two rows. Robot 72 averages chroma over
each horizontal pair and repeats the value for both positions. This implements
the Robot 4:2:0 and 4:2:2 sampling used by established encoders while retaining
the specified 320-position sweep.

For Martin, Scottie, and Wraase, R/G/B values map linearly from 0...255 to
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

### 4.4 Receiver and HF Fax boundary

The receive core will remain in Foundation-only `SSTVKit`. It accepts mono
floating-point PCM chunks and owns demodulation, VIS recognition, line timing,
mode selection, and progressive raster assembly. AVFoundation capture and
audio-file conversion remain app adapters. Synthetic encode-to-decode tests
must pass before microphone UI is enabled.

Automatic mode selection applies to valid VIS modes. A fallback may suggest a
mode from repeated 5/9/20 ms sync pulses and measured line duration, but it
must identify that result as timing-derived rather than VIS-confirmed.

The contributed HF Fax receiver profile is IOC 576 at 120 lines per minute:
one grayscale radio line every 500 ms and a final display width of 1808
samples. It has no VIS code. It is selected manually and kept outside
`SSTVMode` so fixed-height SSTV assumptions do not leak into radiofax.

## 5. SSTVKit components

### `RGBPixel` and `RGBImage`

Small sendable value types. `RGBImage` validates exact dimensions and stores
row-major 8-bit RGB pixels.

### `SSTVMode`

Owns immutable public metadata: family, display name, VIS code, raster
dimensions, radio-line count, line duration, picture duration, and total
duration. PD modes explicitly expose half as many radio lines as raster rows.
Mode-specific line layout is centralized in one internal strategy.

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
photo, mode, zoom, or crop position invalidates any prior encoding. Martin,
Scottie, and Wraase prepare 320x256; Robot modes prepare 320x240. PD modes
prepare their published 320x256, 512x400, 640x496, or 800x616 raster.

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

- all mode dimensions, VIS codes, radio-line counts, line times, and total
  sample counts;
- VIS LSB-first bit order and even parity;
- cumulative sample rounding and continuous oscillator phase;
- RGB and BT.601 component-to-frequency mapping;
- Martin, Scottie, and Wraase channel/line ordering;
- PD two-row ordering and vertical chroma averaging;
- Robot 36 separator alternation and 2x2 chroma averaging;
- Robot 72 component order and horizontal chroma averaging;
- deterministic output and cooperative cancellation;
- RIFF fields, little-endian PCM, saturation, and payload length.

App tests cover crop geometry, invalidation on every input change, monotonic
progress, and rejection of stale task results. A source contract script checks
the iOS 17 target, Swift 5.9 setting, package boundary, WAV format, absence of
microphone/PTT/network entitlements and APIs, and workflow packaging gates.

CI on `macos-14` and `macos-15`:

1. validate repository contracts and their regression tests;
2. run `swift test` for `SSTVKit` with Xcode 15.0.1 / Swift 5.9;
3. generate the Xcode project and test the app on an iOS 17 simulator;
4. repeat package and app tests with Xcode 16.4 on `macos-15`;
5. only after both test jobs pass, build for `generic/platform=iOS` with
   signing fully disabled;
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

The encoder expansion is complete when all 15 VIS modes reproduce the mode
tables' exact line layout and 48 kHz cumulative sample count in CI. The receive
phase is complete only after deterministic chunk-boundary, noisy-header,
frequency-offset, mode-switch, encode/decode round-trip, cancellation, audio
file, microphone lifecycle, privacy-string, and HF Fax tests pass. Actual RF
reception remains a separate real-device validation and is never inferred from
simulator or synthetic CI results.
