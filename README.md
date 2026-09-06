# SSTVEncoder-iOS

## 当前进度与协作入口

请先阅读 [项目交接与目标要求（中文）](PROJECT_HANDOFF.zh-CN.md)；
Claude 的精简入口是 [CLAUDE.md](CLAUDE.md)。交接说明区分已实现功能、未完成 UI、
真实接口、分支合并门槛和完整验收要求，优先于旧勘察记录中的进度表。

当前实现版本为 **1.1.3（5）**：设计系统、接收优先四 Tab、接收同步修复和漏 VIS 的
中途片段锁定已经实现。[实现提交 10cc147 的四项 CI 全部通过](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33956223017)。
图库和设置仍为骨架；连续多帧入库、完整发射/接收改版、瀑布和商业验收尚未完成。
CI 成功不代表弱信号、真实电台链路或真机中途接收已全部通过。

SSTVEncoder-iOS is an independent SwiftUI app that encodes photos to SSTV audio
and decodes SSTV recordings or live microphone input entirely on the iPhone or
iPad. Both directions are provided by the reusable, Foundation-only `SSTVKit`
Swift package.

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

The receiver provides:

- automatic VIS detection and progressive decoding for the same 15 modes;
- automatic late-entry candidates from repeated line syncs when VIS was missed,
  with partial-image labeling and no invented original row numbers;
- manual selection for damaged or missing VIS headers;
- audio import using every format supported by `AVAudioFile`, including WAV,
  MP3, M4A, AIFF, and CAF where available on the device;
- explicitly started live microphone reception, with no raw-audio retention;
- local PNG export of complete or partial decoded images; and
- a separate manual `Contrib / HF Fax` receiver for IOC 576 at 120 LPM. HF Fax
  has no VIS and produces an 1808-pixel-wide progressive grayscale image.

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

Run the portable encoder and decoder tests on macOS:

```sh
swift test --package-path SSTVKit --parallel
```

GitHub Actions also generates the Xcode project and runs the app tests on an
iOS 17 simulator with Xcode 15.0.1, repeats tests with Xcode 16.4, then builds
for `generic/platform=iOS`. Synthetic encode-to-decode, streaming chunk,
VIS/parity/frequency-offset, cancellation, partial-image, and HF Fax tests run
before packaging. Packaging is gated on both test jobs.

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

The app contains no radio control, CAT, PTT, remote server, network client,
Hamlib, FT8/FT4, or automatic transmission path. Playing generated audio into
radio equipment remains a separate operator action outside this project.

Microphone permission is requested only after the user taps **启动麦克风** on
the receive tab. Captured PCM is streamed directly to the in-memory decoder and
is neither saved nor uploaded. Switching modes or stopping reception cancels
the current decoder and releases the audio session.

`Contrib` is Robot36's category label rather than a modulation. The app exposes
the contributed HF Fax implementation as a separate manual IOC 576 / 120 LPM
profile because radiofax carries no VIS header and cannot be auto-selected.

CI verifies deterministic synthetic signals and simulator lifecycle behavior;
it does not prove reception quality from a particular radio, acoustic path, or
iPhone microphone. Those remain explicit real-device tests.

See [the design](docs/design.md) for protocol timing and architecture, and
[the implementation plan](docs/implementation-plan.md) for the TDD and release
gates. The primary mode reference is JL Barber N7CXI's
[Dayton SSTV specification](https://www.classicsstv.com/downloads/daytonpaper.pdf).
