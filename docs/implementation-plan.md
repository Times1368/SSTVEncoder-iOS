# SSTVEncoder-iOS implementation plan

Status: accepted execution plan

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

