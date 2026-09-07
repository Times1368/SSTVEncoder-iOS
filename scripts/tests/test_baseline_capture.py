from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

from scripts.capture_baselines import (
    CASES,
    BaselineError,
    row_order_findings,
    run_bounded,
    summarize,
)


class BaselineCaptureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.output = Path(self.temporary.name)
        for mode_id, filename in CASES.items():
            with wave.open(str(self.output / filename), "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(48_000)
                audio.writeframes(b"\x00\x00\x01\x00" * 24)
            record = {
                "modeID": mode_id,
                "modeName": mode_id,
                "filename": filename,
                "fixtureID": "coordinate-rgb-v1",
                "width": 320,
                "height": 256,
                "sampleRate": 48_000,
                "amplitude": 0.8,
                "sampleCount": 48,
                "durationSeconds": 0.001,
            }
            (self.output / f"{mode_id}.json").write_text(json.dumps(record), encoding="utf-8")
            diagnostic = {
                "modeID": mode_id,
                "completedRows": 256,
                "expectedRows": 256,
                "isComplete": True,
                "detectedModeMatches": True,
                "measurement": {"status": "consistent"},
            }
            (self.output / f"{mode_id}-row-order.json").write_text(
                json.dumps(diagnostic), encoding="utf-8"
            )

    def test_summary_hashes_the_actual_wav_bytes_with_portable_filenames(self) -> None:
        report = summarize(self.output, commit="test-commit")
        self.assertEqual(report["commit"], "test-commit")
        self.assertEqual(len(report["records"]), 3)
        sums = (self.output / "SHA256SUMS").read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(sums), 3)
        for line, filename in zip(sums, CASES.values()):
            self.assertEqual(line, f"{hashlib.sha256((self.output / filename).read_bytes()).hexdigest()}  {filename}")

    def test_metadata_must_match_the_wav_sample_count(self) -> None:
        path = self.output / "pd120.json"
        record = json.loads(path.read_text(encoding="utf-8"))
        record["sampleCount"] += 1
        path.write_text(json.dumps(record), encoding="utf-8")
        with self.assertRaisesRegex(BaselineError, "sample count"):
            summarize(self.output)

    def test_missing_one_wav_cannot_be_reported_as_a_complete_baseline(self) -> None:
        (self.output / "PD-120.wav").unlink()
        with self.assertRaisesRegex(BaselineError, "PD-120.wav"):
            summarize(self.output)

    def test_stereo_audio_is_rejected(self) -> None:
        with wave.open(str(self.output / "PD-120.wav"), "wb") as audio:
            audio.setnchannels(2)
            audio.setsampwidth(2)
            audio.setframerate(48_000)
            audio.writeframes(b"\x00" * 192)
        with self.assertRaisesRegex(BaselineError, "48 kHz mono PCM16"):
            summarize(self.output)

    def test_orientation_diagnostic_does_not_block_wav_hash_capture(self) -> None:
        path = self.output / "pd120-row-order.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        report["measurement"]["status"] = "reversed"
        path.write_text(json.dumps(report), encoding="utf-8")
        summarize(self.output)
        self.assertTrue((self.output / "SHA256SUMS").is_file())
        self.assertIn("pd120", "\n".join(row_order_findings(self.output)))

    def test_incomplete_frame_is_a_nonblocking_diagnostic(self) -> None:
        path = self.output / "pd120-row-order.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        report["completedRows"] -= 2
        path.write_text(json.dumps(report), encoding="utf-8")
        self.assertIn("pd120", "\n".join(row_order_findings(self.output)))

    def test_missing_row_order_report_is_nonblocking(self) -> None:
        (self.output / "pd120-row-order.json").unlink()
        self.assertIn("pd120", "\n".join(row_order_findings(self.output)))

    def test_commands_cannot_read_stdin_and_have_an_explicit_timeout(self) -> None:
        with patch("scripts.capture_baselines.subprocess.Popen") as start:
            start.return_value.wait.return_value = 0
            run_bounded(["example", "argument"], timeout=115)
        self.assertEqual(start.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertFalse(start.call_args.kwargs["shell"])
        start.return_value.wait.assert_called_once_with(timeout=115)

    def test_timeout_aborts_the_command(self) -> None:
        with self.assertRaisesRegex(BaselineError, "timed out"):
            run_bounded([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.1)

    def test_timeout_over_120_seconds_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            run_bounded(["unused"], timeout=121)


if __name__ == "__main__":
    unittest.main()
