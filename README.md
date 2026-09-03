# SSTVEncoder-iOS

An independent iOS 17 app and reusable Swift package for turning a prepared
image into standards-compatible SSTV audio.

Version 1 supports:

- Robot 36 Color
- Robot 72 Color
- Martin M1
- Scottie S1

The output path is deliberately local-only: select a photo, crop and scale it,
encode it, play the resulting audio on the device, or export the same signal as
a 48 kHz mono 16-bit PCM WAV file. The project contains no radio control, CAT,
PTT, remote server, microphone, or transmit integration.

The implementation is specified in [docs/design.md](docs/design.md) and staged
in [docs/implementation-plan.md](docs/implementation-plan.md).

