#!/usr/bin/env python3
"""Capture real Swift WAVs in macOS CI; validate/hash them without third-party packages.

No Python SSTV encoder is provided. Windows may run only tests and validation.
Each child command has closed stdin and a 115-second deadline by default.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import signal
import subprocess
import sys
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "robot36Color": "Robot-36-Color.wav",
    "martinM1": "Martin-M1.wav",
    "pd120": "PD-120.wav",
}


class BaselineError(RuntimeError):
    pass


def run_bounded(command: list[str], *, timeout: float = 115, cwd: Path = ROOT) -> None:
    if not 0 < timeout <= 120:
        raise ValueError("Command timeout must be in (0, 120] seconds")
    environment = dict(os.environ, CI="1", GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        shell=False,
        env=environment,
        start_new_session=os.name == "posix",
    )
    try:
        return_code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        if os.name == "posix":
            # Include swift compiler children, not just the swift driver.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            process.kill()
        process.wait(timeout=2)
        raise BaselineError(f"Command timed out after {timeout}s and was stopped: {command[0]}") from exc
    if return_code != 0:
        raise subprocess.CalledProcessError(return_code, command)


def read_json(path: Path) -> dict:
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise BaselineError(f"Cannot read {path.name}: {exc}") from exc
    if not isinstance(result, dict):
        raise BaselineError(f"Expected a JSON object: {path.name}")
    return result


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def summarize(output: Path, *, commit: str = "") -> dict:
    records = []
    checksums = []
    for mode_id, filename in CASES.items():
        record = read_json(output / f"{mode_id}.json")
        if (record.get("modeID"), record.get("filename"), record.get("fixtureID")) != (
            mode_id, filename, "coordinate-rgb-v1"
        ):
            raise BaselineError(f"Unexpected baseline input identity: {mode_id}")
        try:
            wav = (output / filename).read_bytes()
            with wave.open(str(output / filename), "rb") as audio:
                if (audio.getframerate(), audio.getnchannels(), audio.getsampwidth(), audio.getcomptype()) != (
                    48_000, 1, 2, "NONE"
                ):
                    raise BaselineError(f"Expected 48 kHz mono PCM16: {filename}")
                count = audio.getnframes()
                if count <= 0 or len(audio.readframes(count)) != count * 2:
                    raise BaselineError(f"Truncated or empty PCM: {filename}")
        except (OSError, wave.Error, EOFError) as exc:
            raise BaselineError(f"Cannot read {filename}: {exc}") from exc
        if record.get("sampleCount") != count:
            raise BaselineError(f"WAV and metadata sample count differ: {filename}")
        if record.get("sampleRate") != 48_000 or record.get("amplitude") != 0.8:
            raise BaselineError(f"Unexpected encoding settings: {filename}")
        if not math.isclose(record.get("durationSeconds", -1), count / 48_000, rel_tol=0, abs_tol=1e-9):
            raise BaselineError(f"WAV and metadata duration differ: {filename}")
        digest = hashlib.sha256(wav).hexdigest()
        records.append(dict(record, sha256=digest, wavBytes=len(wav)))
        checksums.append(f"{digest}  {filename}")

    core = ROOT / "SSTVKit" / "Sources" / "SSTVKit"
    report = {
        "schemaVersion": 2,
        "commit": commit,
        "fixtureID": "coordinate-rgb-v1",
        "fixtureRule": "Formula evaluated directly at each mode's native (x,y); no IO or resizing",
        "coreSourcesSHA256": {
            path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(core.glob("*.swift"))
        },
        "records": records,
    }
    write_json(output / "baseline-metadata.json", report)
    (output / "SHA256SUMS").write_text("\n".join(checksums) + "\n", encoding="utf-8")
    return report


def require_consistent_row_order(output: Path) -> None:
    problems = []
    for mode_id in CASES:
        report = read_json(output / f"{mode_id}-row-order.json")
        measurement = report.get("measurement") or {}
        if not (
            report.get("modeID") == mode_id
            and report.get("isComplete") is True
            and report.get("detectedModeMatches") is True
            and isinstance(report.get("expectedRows"), int)
            and report["expectedRows"] > 0
            and report.get("completedRows") == report["expectedRows"]
            and measurement.get("status") == "consistent"
        ):
            problems.append(f"{mode_id}: {json.dumps(report, ensure_ascii=False)}")
    if problems:
        raise BaselineError("Separate row-order diagnostic needs review; WAV hashes remain valid:\n" + "\n".join(problems))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["build", "test-fixture", "capture", "summarize", "check-row-order"])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--mode", choices=CASES)
    args = parser.parse_args()
    if args.phase in ("build", "test-fixture", "capture") and sys.platform != "darwin":
        parser.error("Swift execution is macOS CI only; it is prohibited on this Windows workstation")
    if args.phase not in ("build", "test-fixture") and args.output is None:
        parser.error("--output is required")
    if args.phase == "build":
        run_bounded(["swift", "build", "--package-path", "SSTVKit", "-c", "release", "--product", "BaselineGenerator"])
    elif args.phase == "test-fixture":
        run_bounded(["swift", "test", "--package-path", "SSTVKit", "-c", "release", "--filter", "BaselineSupportTests"])
    elif args.phase == "capture":
        if args.mode is None:
            parser.error("capture requires --mode")
        binary = ROOT / "SSTVKit" / ".build" / "release" / "BaselineGenerator"
        run_bounded([str(binary), args.mode, str(args.output.resolve())])
    elif args.phase == "summarize":
        report = summarize(args.output, commit=os.environ.get("GITHUB_SHA", ""))
        summary = ["## 第 0 步：算法测试图编码基线", "", "| 模式 | SHA-256 | 实际秒数 | 样本数 |", "|---|---|---:|---:|"]
        for record in report["records"]:
            summary.append(f"| {record['modeName']} | `{record['sha256']}` | {record['durationSeconds']:.9f} | {record['sampleCount']} |")
        summary.extend(["", f"提交：`{report['commit']}`", "", "行序诊断见 artifact 的 *-row-order.json；不涉及 App 图片载入器。", ""])
        text = "\n".join(summary)
        print(text, flush=True)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
                stream.write(text)
    else:
        require_consistent_row_order(args.output)
        print("三个模式的编解码回环行序一致；不代表 App 图片载入器已验证。", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BaselineError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
