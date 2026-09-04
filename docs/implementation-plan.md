# SSTVEncoder-iOS implementation plan

Status: encoder expansion complete; receiver implemented locally, CI and real-device validation pending

## Encoder expansion - 15 VIS modes

### Commit A - Lock the expanded protocol design

- Record exact VIS codes, rasters, channel timing, radio-line counts, and
  cumulative 48 kHz durations for PD, Martin M2, Scottie S2/DX, and Wraase
  SC2-180.
- Define `Contrib` as a receive-mode category and keep HF Fax outside the
  fixed-frame `SSTVMode` model.

Gate: every number is traceable to the Dayton specification and reproduces
the published approximate transmission time.

### Commit B - Add failing expanded-encoder specifications

- Extend metadata and sample-count tests from 4 to 15 VIS modes.
- Specify Martin/Scottie timing variants, Wraase R/G/B order, and PD two-row
  Y/R-Y/B-Y/Y ordering with vertically averaged chroma.
- Specify PD progress in radio lines rather than raster rows.

Gate: tests describe all new behavior before production sources change. The
uncompiled red state remains local and is not pushed by itself.

### Commit C - Implement the expanded encoder and app selection

- Replace repeated mode switches with one immutable descriptor per mode.
- Add protocol-family metadata and a radio-line count distinct from raster
  height.
- Implement shared Martin, Scottie, PD, and Wraase line strategies.
- Group the mode selector by family while preserving crop invalidation,
  progress, playback, and 48 kHz mono Int16 WAV export.

Gate: local Python contract tests and `git diff --check` pass. Push once, then
return the Actions run URL without waiting, as required for this Windows host.

## Receiver phase - automatic SSTV plus Contrib / HF Fax

### Commit D - Add failing decoder-core specifications — complete

- Specify streaming PCM input, chunk-boundary invariance, VIS LSB/parity
  validation, frequency offset, cancellation, and progressive image updates.
- Add deterministic encoder-to-decoder round trips for every supported VIS
  family, plus noise and truncated-input cases.
- Specify that VIS-confirmed and timing-inferred detections are distinct.

### Commit E - Implement the reusable decoder core — complete locally

- Add Foundation-only FM demodulation, tone classification, header detection,
  line synchronization, per-family color reconstruction, and auto-mode state.
- Keep decoder state bounded and make input sample rate explicit.
- Add a manual IOC 576 / 120 LPM grayscale HF Fax profile outside
  `SSTVMode`; it cannot be VIS-auto-selected.

### Commit F - Add receive UI and audio adapters — complete locally

- Add imported-audio decoding and an explicitly started AVAudioEngine
  microphone session with progressive preview, stop/reset, and image export.
- Request microphone permission only on receive; add the required privacy
  string and an in-app explanation that raw audio is not retained.
- Do not add networking, PTT, CAT, or any automatic transmit path.

Gate status: Windows source privacy/security contracts pass. macOS SwiftPM,
iOS simulator compilation/tests, unsigned device build, and IPA verification
remain pending until the commit is pushed to Actions. Real-device microphone
and over-the-air reception are reported separately and never claimed from CI.

## Commit 1 - Lock design and boundaries

- Add the product design, protocol table, architecture, TDD gates, and explicit
  no-PTT/no-remote-control boundary.
- Record the independent-repository layout and CI delivery contract.

Gate: design is internally consistent and all four line durations reproduce
the published picture duration.

## Commit 2 - Add failing SSTVKit specifications

- Create the Swift package manifest and test target.
- Write mode, VIS, timing, color conversion, chroma subsampling, oscillator,
  cancellation, deterministic output, and WAV tests before source files exist.

Gate: test inventory maps one-to-one to the design. Failure is expected until
Commit 3; the red state is preserved in history rather than pushed alone.

## Commit 3 - Implement SSTVKit

- Add value types, mode descriptions, cumulative-time tone writer, common VIS
  header, four line strategies, encoder, progress/cancellation, and WAV writer.
- Keep the package Foundation-only and free of application code.

Gate: all Swift package tests pass on GitHub macOS.

## Commit 4 - Add failing application-state and crop tests

- Specify crop transform clamping and exact-raster behavior.
- Specify encoding invalidation and stale-result rejection.

Gate: tests express the user flow independently of visual styling.

## Commit 5 - Implement the SwiftUI application

- Add XcodeGen configuration and Info.plist.
- Add PhotosPicker, interactive crop preview, mode selection, encoding progress,
  local playback, stop, and WAV file export.
- Add error and accessibility labels.

Gate: generated project builds and simulator tests pass in Actions; no
microphone, network, PTT, or remote-control surface exists.

## Commit 6 - Add CI, packaging, and documentation

- Add deterministic contract checks and IPA verification scripts.
- Add macOS build/test, gated unsigned device build, upload-artifact, and a
  separate artifact re-verification job.
- Finish README usage, architecture, installation limitations, and safety note.

Gate: the full workflow succeeds from a clean checkout.

## Remote delivery

1. Create public `Times1368/SSTVEncoder-iOS` without importing another project.
2. Push `main` and dispatch/observe the resulting workflow.
3. Repair only evidence-backed build or test failures, committing each fix.
4. Download the final artifact rather than trusting the upload step alone.
5. Re-run the local artifact verifier and copy the verified IPA plus checksum
   and manifest into the delivery output directory.
6. Report repository, exact final SHA, run ID/URL, every required job result,
   test totals, IPA filename/size/SHA-256, and any validation that was not run.
