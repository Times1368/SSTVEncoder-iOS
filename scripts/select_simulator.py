#!/usr/bin/env python3
"""Select a deterministic available iPhone from `simctl --json` output."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence


@dataclass(frozen=True)
class Candidate:
    runtime: str
    runtime_version: tuple[int, ...]
    name: str
    udid: str
    state: str


def runtime_version(identifier: str) -> tuple[int, ...] | None:
    match = re.search(r"(?:^|\.)iOS-([0-9]+(?:-[0-9]+)*)$", identifier)
    if not match:
        return None
    return tuple(int(component) for component in match.group(1).split("-"))


def preferred_device_rank(name: str) -> tuple[int, str]:
    preferred = (
        "iPhone 16 Pro",
        "iPhone 16",
        "iPhone 15 Pro",
        "iPhone 15",
        "iPhone 14 Pro",
        "iPhone 14",
        "iPhone SE (3rd generation)",
    )
    try:
        return preferred.index(name), name
    except ValueError:
        return len(preferred), name


def candidates_from_document(document: Any, required_major: int | None) -> list[Candidate]:
    if not isinstance(document, dict) or not isinstance(document.get("devices"), dict):
        raise ValueError("simctl JSON must contain a devices object")

    candidates: list[Candidate] = []
    for runtime, raw_devices in document["devices"].items():
        version = runtime_version(runtime)
        if version is None or (required_major is not None and version[0] != required_major):
            continue
        if not isinstance(raw_devices, list):
            continue
        for device in raw_devices:
            if not isinstance(device, dict):
                continue
            name = device.get("name")
            udid = device.get("udid")
            state = device.get("state")
            is_available = device.get("isAvailable", False)
            if (
                is_available is True
                and isinstance(name, str)
                and name.startswith("iPhone")
                and isinstance(udid, str)
                and re.fullmatch(r"[0-9A-Fa-f-]{36}", udid)
                and isinstance(state, str)
            ):
                candidates.append(
                    Candidate(
                        runtime=runtime,
                        runtime_version=version,
                        name=name,
                        udid=udid.upper(),
                        state=state,
                    )
                )
    return candidates


def choose(candidates: Sequence[Candidate]) -> Candidate:
    if not candidates:
        raise ValueError("no matching available iPhone simulator was found")
    newest_runtime = max(candidate.runtime_version for candidate in candidates)
    newest = [candidate for candidate in candidates if candidate.runtime_version == newest_runtime]
    return min(
        newest,
        key=lambda candidate: (
            0 if candidate.state.casefold() == "booted" else 1,
            preferred_device_rank(candidate.name),
            candidate.udid,
        ),
    )


def github_output_value(value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError("GitHub output value contains a newline")
    return value


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json_file", type=Path, help="file produced by simctl list ... --json")
    parser.add_argument(
        "--runtime-major",
        type=int,
        help="require this iOS runtime major version (for example, 17)",
    )
    parser.add_argument(
        "--github-output",
        type=Path,
        help="append udid/name/runtime keys to this GitHub Actions output file",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        document = json.loads(args.json_file.read_text(encoding="utf-8"))
        selected = choose(candidates_from_document(document, args.runtime_major))
        if args.github_output:
            with args.github_output.open("a", encoding="utf-8", newline="\n") as stream:
                stream.write(f"udid={github_output_value(selected.udid)}\n")
                stream.write(f"name={github_output_value(selected.name)}\n")
                stream.write(f"runtime={github_output_value(selected.runtime)}\n")
        print(
            json.dumps(
                {
                    "name": selected.name,
                    "runtime": selected.runtime,
                    "state": selected.state,
                    "udid": selected.udid,
                },
                sort_keys=True,
            )
        )
        return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"Simulator selection failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
