#!/usr/bin/env python3
"""Verify the independently packaged SSTVEncoder unsigned IPA.

Only the Python standard library is used. Archive members are inspected in
place (never extracted), making the same verifier suitable for local use, the
packaging job, and a downstream artifact-verification job.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import stat
import struct
import sys
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Sequence


DEFAULT_BUNDLE_ID = "io.github.times1368.sstvencoder"
DEFAULT_MARKETING_VERSION = "1.0.0"
DEFAULT_BUILD_VERSION = "1"
DEFAULT_MINIMUM_OS = "17.0"
DEFAULT_APP_NAME = "SSTVEncoder"

MAX_ENTRIES = 20_000
MAX_TOTAL_UNCOMPRESSED_SIZE = 2 * 1024 * 1024 * 1024
MAX_SINGLE_FILE_SIZE = 1024 * 1024 * 1024
MAX_PLIST_SIZE = 16 * 1024 * 1024
MAX_EXECUTABLE_SIZE = 1024 * 1024 * 1024

CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 0x2
LC_CODE_SIGNATURE = 0x1D
LC_VERSION_MIN_IPHONEOS = 0x25
LC_BUILD_VERSION = 0x32
PLATFORM_IOS = 2


class VerificationError(RuntimeError):
    """An IPA invariant was violated."""


@dataclass(frozen=True)
class Expectations:
    app_name: str
    bundle_id: str
    marketing_version: str
    build_version: str
    minimum_os: str

    @property
    def app_prefix(self) -> str:
        return f"Payload/{self.app_name}.app/"


@dataclass(frozen=True)
class MachOSlice:
    cpu_type: int
    cpu_subtype: int
    has_code_signature: bool
    platform: int | None
    minimum_os: tuple[int, int, int] | None


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_member_key(name: str) -> str:
    return unicodedata.normalize("NFC", name.rstrip("/")).casefold()


def validate_member_name(name: str) -> tuple[str, ...]:
    require(bool(name), "ZIP contains an empty member name")
    require(len(name) <= 4096, "ZIP member name exceeds the safety limit")
    require("\x00" not in name, f"ZIP member contains NUL: {name!r}")
    require("\\" not in name, f"ZIP member uses a backslash: {name!r}")
    require(not name.startswith("/"), f"ZIP member is absolute: {name!r}")
    require(not re.match(r"^[A-Za-z]:", name), f"ZIP member uses a drive path: {name!r}")

    without_trailing_slash = name[:-1] if name.endswith("/") else name
    require(bool(without_trailing_slash), f"invalid ZIP member path: {name!r}")
    raw_parts = without_trailing_slash.split("/")
    require(all(part not in {"", ".", ".."} for part in raw_parts), f"unsafe ZIP member path: {name!r}")

    parsed = PurePosixPath(without_trailing_slash)
    require(not parsed.is_absolute(), f"ZIP member is absolute: {name!r}")
    require(tuple(parsed.parts) == tuple(raw_parts), f"ZIP member is not canonical: {name!r}")
    require(raw_parts[0] == "Payload", f"ZIP member is outside Payload/: {name!r}")
    return tuple(raw_parts)


def validate_zip_structure(
    archive: zipfile.ZipFile, expectations: Expectations
) -> tuple[list[zipfile.ZipInfo], zipfile.ZipInfo, zipfile.ZipInfo]:
    infos = archive.infolist()
    require(infos, "IPA ZIP is empty")
    require(len(infos) <= MAX_ENTRIES, f"IPA has too many entries ({len(infos)})")

    exact_names: set[str] = set()
    normalized_names: set[str] = set()
    app_roots: set[str] = set()
    total_uncompressed = 0
    info_plist: zipfile.ZipInfo | None = None
    executable: zipfile.ZipInfo | None = None

    expected_plist = expectations.app_prefix + "Info.plist"
    expected_executable = expectations.app_prefix + expectations.app_name

    for info in infos:
        name = info.filename
        parts = validate_member_name(name)

        require(name not in exact_names, f"duplicate ZIP member: {name!r}")
        exact_names.add(name)
        normalized = normalized_member_key(name)
        require(
            normalized not in normalized_names,
            f"case/Unicode-colliding ZIP member: {name!r}",
        )
        normalized_names.add(normalized)

        require(not (info.flag_bits & 0x1), f"encrypted ZIP member is not allowed: {name!r}")
        require(
            info.compress_type in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED},
            f"unsupported ZIP compression method for {name!r}",
        )
        require(info.file_size <= MAX_SINGLE_FILE_SIZE, f"ZIP member is implausibly large: {name!r}")
        total_uncompressed += info.file_size
        require(
            total_uncompressed <= MAX_TOTAL_UNCOMPRESSED_SIZE,
            "IPA uncompressed size exceeds the safety limit",
        )

        unix_mode = (info.external_attr >> 16) & 0xFFFF
        file_kind = stat.S_IFMT(unix_mode)
        require(not stat.S_ISLNK(unix_mode), f"symbolic link is not allowed in IPA: {name!r}")
        if file_kind:
            require(
                stat.S_ISREG(unix_mode) or stat.S_ISDIR(unix_mode),
                f"special filesystem entry is not allowed in IPA: {name!r}",
            )
            require(
                info.is_dir() == stat.S_ISDIR(unix_mode),
                f"ZIP name/type mismatch for {name!r}",
            )

        for index, part in enumerate(parts):
            if part.casefold().endswith(".app"):
                app_roots.add("/".join(parts[: index + 1]))

        lower_parts = tuple(part.casefold() for part in parts)
        require("__macosx" not in lower_parts, f"AppleDouble metadata is not allowed: {name!r}")
        require(".ds_store" not in lower_parts, f"Finder metadata is not allowed: {name!r}")
        require("_codesignature" not in lower_parts, f"code-signature directory found: {name!r}")
        require("sc_info" not in lower_parts, f"FairPlay/signing directory found: {name!r}")
        require(
            not any(
                part == "embedded.mobileprovision"
                or part.endswith(".mobileprovision")
                or part.endswith(".provisionprofile")
                for part in lower_parts
            ),
            f"provisioning profile found: {name!r}",
        )
        require(
            not name.casefold().endswith((".xcent", ".entitlements")),
            f"entitlements file found: {name!r}",
        )

        app_relative_parts = parts[2:] if len(parts) >= 2 and parts[1] == f"{expectations.app_name}.app" else ()
        app_relative_lower = tuple(part.casefold() for part in app_relative_parts)
        require(
            "frameworks" not in app_relative_lower
            and not any(part.endswith(".framework") for part in app_relative_lower)
            and not any(part.endswith(".dylib") for part in app_relative_lower),
            f"bundled framework/dylib is not allowed: {name!r}",
        )

        if name == expected_plist:
            info_plist = info
        if name == expected_executable:
            executable = info

    expected_app_root = f"Payload/{expectations.app_name}.app"
    require(
        app_roots == {expected_app_root},
        f"IPA must contain exactly {expected_app_root}; found {sorted(app_roots)!r}",
    )
    require(info_plist is not None, f"missing {expected_plist}")
    require(executable is not None, f"missing {expected_executable}")
    require(not info_plist.is_dir(), "Info.plist is unexpectedly a directory")
    require(not executable.is_dir(), "app executable is unexpectedly a directory")
    require(info_plist.file_size <= MAX_PLIST_SIZE, "Info.plist exceeds the safety limit")
    require(executable.file_size <= MAX_EXECUTABLE_SIZE, "app executable exceeds the safety limit")
    require(executable.file_size > 0, "app executable is empty")

    executable_mode = (executable.external_attr >> 16) & 0xFFFF
    require(
        bool(executable_mode & 0o111),
        "app executable has no executable permission bits in the ZIP metadata",
    )

    try:
        corrupt_member = archive.testzip()
    except (RuntimeError, OSError, zipfile.BadZipFile) as exc:
        raise VerificationError(f"could not complete ZIP CRC validation: {exc}") from exc
    require(corrupt_member is None, f"ZIP CRC check failed for {corrupt_member!r}")

    return infos, info_plist, executable


def read_limited_member(
    archive: zipfile.ZipFile, info: zipfile.ZipInfo, limit: int
) -> bytes:
    require(info.file_size <= limit, f"{info.filename!r} exceeds the read safety limit")
    try:
        with archive.open(info, "r") as stream:
            data = stream.read(limit + 1)
    except (RuntimeError, OSError, zipfile.BadZipFile) as exc:
        raise VerificationError(f"could not read {info.filename!r}: {exc}") from exc
    require(len(data) <= limit, f"{info.filename!r} exceeds the read safety limit")
    require(len(data) == info.file_size, f"short read for {info.filename!r}")
    return data


def plist_string(plist: dict[str, Any], key: str) -> str:
    value = plist.get(key)
    require(isinstance(value, (str, int)), f"Info.plist {key} is missing or not scalar")
    return str(value)


def validate_plist(data: bytes, expectations: Expectations) -> dict[str, Any]:
    try:
        loaded = plistlib.loads(data)
    except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError) as exc:
        raise VerificationError(f"Info.plist is invalid: {exc}") from exc
    require(isinstance(loaded, dict), "Info.plist root must be a dictionary")

    exact = {
        "CFBundleIdentifier": expectations.bundle_id,
        "CFBundleShortVersionString": expectations.marketing_version,
        "CFBundleVersion": expectations.build_version,
        "MinimumOSVersion": expectations.minimum_os,
        "CFBundleExecutable": expectations.app_name,
        "CFBundlePackageType": "APPL",
    }
    for key, expected in exact.items():
        actual = plist_string(loaded, key)
        require(actual == expected, f"Info.plist {key}: expected {expected!r}, found {actual!r}")

    platforms = loaded.get("CFBundleSupportedPlatforms")
    require(
        platforms == ["iPhoneOS"],
        f"CFBundleSupportedPlatforms must be ['iPhoneOS'], found {platforms!r}",
    )
    platform_name = loaded.get("DTPlatformName")
    if platform_name is not None:
        require(platform_name == "iphoneos", f"DTPlatformName must be 'iphoneos', found {platform_name!r}")

    forbidden_keys = {
        "SignerIdentity",
        "ApplicationIdentifier",
        "TeamIdentifier",
        "ProvisioningProfile",
    }
    present = sorted(forbidden_keys.intersection(loaded))
    require(not present, f"Info.plist contains signing/provisioning keys: {present!r}")
    return loaded


def cpu_name(cpu_type: int) -> str:
    if cpu_type == CPU_TYPE_ARM64:
        return "arm64"
    known = {
        7: "i386",
        12: "arm",
        0x01000007: "x86_64",
    }
    return known.get(cpu_type, f"cpu-0x{cpu_type:08x}")


def decode_macho_version(encoded: int) -> tuple[int, int, int]:
    return encoded >> 16, (encoded >> 8) & 0xFF, encoded & 0xFF


def normalized_version_tuple(value: str) -> tuple[int, int, int]:
    require(
        re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value) is not None,
        f"invalid expected OS version {value!r}",
    )
    components = tuple(int(component) for component in value.split("."))
    return (components + (0, 0, 0))[:3]


def parse_thin_macho(data: bytes, base: int, size: int) -> MachOSlice:
    require(size >= 28 and base >= 0 and base + size <= len(data), "invalid Mach-O slice bounds")
    magic = data[base : base + 4]
    thin_formats = {
        b"\xcf\xfa\xed\xfe": ("<", True),
        b"\xfe\xed\xfa\xcf": (">", True),
        b"\xce\xfa\xed\xfe": ("<", False),
        b"\xfe\xed\xfa\xce": (">", False),
    }
    require(magic in thin_formats, f"unrecognized Mach-O slice magic {magic.hex()}")
    endian, is_64_bit = thin_formats[magic]
    header_size = 32 if is_64_bit else 28
    require(size >= header_size, "truncated Mach-O header")

    cpu_type_signed, cpu_subtype, file_type, command_count, commands_size = struct.unpack_from(
        f"{endian}iiIII", data, base + 4
    )
    cpu_type = cpu_type_signed & 0xFFFFFFFF
    require(file_type == MH_EXECUTE, f"Mach-O file type is {file_type}, not MH_EXECUTE")
    require(command_count <= 100_000, "implausible Mach-O load-command count")
    commands_start = base + header_size
    commands_end = commands_start + commands_size
    require(commands_end <= base + size, "Mach-O load commands exceed slice bounds")

    cursor = commands_start
    has_code_signature = False
    build_platform: int | None = None
    minimum_os: tuple[int, int, int] | None = None
    for _ in range(command_count):
        require(cursor + 8 <= commands_end, "truncated Mach-O load command")
        command, command_size = struct.unpack_from(f"{endian}II", data, cursor)
        require(command_size >= 8, "Mach-O load command has an invalid size")
        require(cursor + command_size <= commands_end, "Mach-O load command exceeds declared table")
        if command == LC_CODE_SIGNATURE:
            has_code_signature = True
        elif command == LC_BUILD_VERSION:
            require(command_size >= 24, "truncated LC_BUILD_VERSION command")
            platform, encoded_minimum = struct.unpack_from(f"{endian}II", data, cursor + 8)
            decoded_minimum = decode_macho_version(encoded_minimum)
            require(
                build_platform in {None, platform} and minimum_os in {None, decoded_minimum},
                "conflicting Mach-O build-version commands",
            )
            build_platform = platform
            minimum_os = decoded_minimum
        elif command == LC_VERSION_MIN_IPHONEOS:
            require(command_size >= 16, "truncated LC_VERSION_MIN_IPHONEOS command")
            encoded_minimum = struct.unpack_from(f"{endian}I", data, cursor + 8)[0]
            decoded_minimum = decode_macho_version(encoded_minimum)
            require(
                build_platform in {None, PLATFORM_IOS} and minimum_os in {None, decoded_minimum},
                "conflicting Mach-O minimum-iOS commands",
            )
            build_platform = PLATFORM_IOS
            minimum_os = decoded_minimum
        cursor += command_size
    require(cursor == commands_end, "Mach-O load-command sizes do not match sizeofcmds")

    return MachOSlice(
        cpu_type=cpu_type,
        cpu_subtype=cpu_subtype & 0xFFFFFFFF,
        has_code_signature=has_code_signature,
        platform=build_platform,
        minimum_os=minimum_os,
    )


def parse_macho(data: bytes) -> list[MachOSlice]:
    require(len(data) >= 4, "app executable is too small to be Mach-O")
    magic = data[:4]
    thin_magics = {
        b"\xcf\xfa\xed\xfe",
        b"\xfe\xed\xfa\xcf",
        b"\xce\xfa\xed\xfe",
        b"\xfe\xed\xfa\xce",
    }
    if magic in thin_magics:
        return [parse_thin_macho(data, 0, len(data))]

    fat_formats = {
        b"\xca\xfe\xba\xbe": (">", False),
        b"\xbe\xba\xfe\xca": ("<", False),
        b"\xca\xfe\xba\xbf": (">", True),
        b"\xbf\xba\xfe\xca": ("<", True),
    }
    require(magic in fat_formats, f"app executable is not Mach-O (magic {magic.hex()})")
    endian, is_64_bit = fat_formats[magic]
    require(len(data) >= 8, "truncated fat Mach-O header")
    architecture_count = struct.unpack_from(f"{endian}I", data, 4)[0]
    require(1 <= architecture_count <= 32, f"invalid fat Mach-O architecture count {architecture_count}")

    entry_size = 32 if is_64_bit else 20
    table_end = 8 + architecture_count * entry_size
    require(table_end <= len(data), "truncated fat Mach-O architecture table")

    slices: list[MachOSlice] = []
    ranges: list[tuple[int, int]] = []
    for index in range(architecture_count):
        cursor = 8 + index * entry_size
        if is_64_bit:
            cpu_type_signed, _cpu_subtype, offset, size, _alignment, _reserved = struct.unpack_from(
                f"{endian}iiQQII", data, cursor
            )
        else:
            cpu_type_signed, _cpu_subtype, offset, size, _alignment = struct.unpack_from(
                f"{endian}iiIII", data, cursor
            )
        require(size > 0 and offset >= table_end, "invalid fat Mach-O slice range")
        require(offset + size <= len(data), "fat Mach-O slice exceeds executable bounds")
        ranges.append((offset, offset + size))
        parsed = parse_thin_macho(data, offset, size)
        require(
            parsed.cpu_type == (cpu_type_signed & 0xFFFFFFFF),
            "fat Mach-O architecture table disagrees with slice header",
        )
        slices.append(parsed)

    ordered = sorted(ranges)
    for previous, current in zip(ordered, ordered[1:]):
        require(previous[1] <= current[0], "fat Mach-O slices overlap")
    return slices


def read_expected_sha256(path: Path, expected_filename: str) -> str:
    try:
        lines = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, UnicodeDecodeError) as exc:
        raise VerificationError(f"could not read expected SHA-256 file {path}: {exc}") from exc
    require(len(lines) == 1, "SHA-256 file must contain exactly one non-empty line")
    match = re.fullmatch(r"([0-9a-fA-F]{64})(?:\s+\*?(.+))?", lines[0])
    require(match is not None, "SHA-256 file is not in sha256sum format")
    listed_name = match.group(2)
    if listed_name is not None:
        require(
            Path(listed_name).name == expected_filename,
            f"SHA-256 file names {listed_name!r}, expected {expected_filename!r}",
        )
    return match.group(1).lower()


def load_expected_manifest(path: Path) -> dict[str, Any]:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise VerificationError(f"could not read expected manifest {path}: {exc}") from exc
    require(isinstance(loaded, dict), "expected manifest root must be a JSON object")
    return loaded


def write_text_file(path: Path, contents: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(contents, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def verify_ipa(path: Path, expectations: Expectations) -> dict[str, Any]:
    require(path.is_file(), f"IPA does not exist or is not a file: {path}")
    file_size = path.stat().st_size
    require(file_size > 0, "IPA file is empty")
    digest = sha256_file(path)

    try:
        with zipfile.ZipFile(path, "r") as archive:
            infos, plist_info, executable_info = validate_zip_structure(archive, expectations)
            plist_data = read_limited_member(archive, plist_info, MAX_PLIST_SIZE)
            plist = validate_plist(plist_data, expectations)
            executable_data = read_limited_member(archive, executable_info, MAX_EXECUTABLE_SIZE)
            slices = parse_macho(executable_data)
    except zipfile.BadZipFile as exc:
        raise VerificationError(f"IPA is not a valid ZIP archive: {exc}") from exc

    architectures = sorted({cpu_name(slice_.cpu_type) for slice_ in slices})
    require(architectures == ["arm64"], f"expected arm64-only device executable, found {architectures!r}")
    require(len(slices) == 1, f"expected exactly one arm64 Mach-O slice, found {len(slices)}")
    require(
        all(not slice_.has_code_signature for slice_ in slices),
        "Mach-O contains an LC_CODE_SIGNATURE load command",
    )
    expected_minimum_os = normalized_version_tuple(expectations.minimum_os)
    require(
        all(slice_.platform == PLATFORM_IOS for slice_ in slices),
        "Mach-O does not declare the iOS device platform",
    )
    require(
        all(slice_.minimum_os == expected_minimum_os for slice_ in slices),
        f"Mach-O minimum OS is not {expectations.minimum_os}",
    )

    return {
        "schemaVersion": 1,
        "artifact": {
            "fileName": path.name,
            "sha256": digest,
            "sizeBytes": file_size,
        },
        "application": {
            "path": f"Payload/{expectations.app_name}.app",
            "bundleIdentifier": plist_string(plist, "CFBundleIdentifier"),
            "shortVersion": plist_string(plist, "CFBundleShortVersionString"),
            "buildVersion": plist_string(plist, "CFBundleVersion"),
            "minimumOSVersion": plist_string(plist, "MinimumOSVersion"),
            "executable": plist_string(plist, "CFBundleExecutable"),
            "supportedPlatforms": plist["CFBundleSupportedPlatforms"],
        },
        "archive": {
            "entryCount": len(infos),
            "compressedPayloadBytes": sum(info.compress_size for info in infos),
            "uncompressedPayloadBytes": sum(info.file_size for info in infos),
            "crcValidated": True,
            "pathsSafe": True,
        },
        "binary": {
            "architectures": architectures,
            "sliceCount": len(slices),
            "platform": "iOS",
            "minimumOSVersion": expectations.minimum_os,
            "codeSignatureLoadCommand": False,
        },
        "security": {
            "codeSignatureDirectory": False,
            "embeddedProvisioningProfile": False,
            "bundledFrameworksOrDylibs": [],
            "unsigned": True,
        },
    }


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path, help="IPA to verify")
    parser.add_argument("--app-name", default=DEFAULT_APP_NAME)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--marketing-version", default=DEFAULT_MARKETING_VERSION)
    parser.add_argument("--build-version", default=DEFAULT_BUILD_VERSION)
    parser.add_argument("--minimum-os", default=DEFAULT_MINIMUM_OS)
    parser.add_argument("--manifest", type=Path, help="write a deterministic verification manifest")
    parser.add_argument("--sha256-file", type=Path, help="write a sha256sum-compatible checksum file")
    parser.add_argument("--expected-manifest", type=Path, help="require exact equality with this manifest")
    parser.add_argument("--expected-sha256-file", type=Path, help="require the checksum in this file")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    expectations = Expectations(
        app_name=args.app_name,
        bundle_id=args.bundle_id,
        marketing_version=args.marketing_version,
        build_version=args.build_version,
        minimum_os=args.minimum_os,
    )

    try:
        manifest = verify_ipa(args.ipa.resolve(), expectations)
        actual_sha256 = manifest["artifact"]["sha256"]

        if args.expected_sha256_file:
            expected_sha256 = read_expected_sha256(
                args.expected_sha256_file.resolve(), manifest["artifact"]["fileName"]
            )
            require(
                actual_sha256 == expected_sha256,
                f"SHA-256 mismatch: expected {expected_sha256}, found {actual_sha256}",
            )

        if args.expected_manifest:
            expected_manifest = load_expected_manifest(args.expected_manifest.resolve())
            require(
                manifest == expected_manifest,
                "fresh IPA verification does not exactly match the published manifest",
            )

        serialized = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
        if args.manifest:
            write_text_file(args.manifest.resolve(), serialized)
        if args.sha256_file:
            checksum_line = f"{actual_sha256}  {manifest['artifact']['fileName']}\n"
            write_text_file(args.sha256_file.resolve(), checksum_line)

        print(serialized, end="")
        print(
            f"Verified unsigned arm64 IPA: {manifest['artifact']['fileName']} "
            f"({manifest['artifact']['sizeBytes']} bytes, sha256 {actual_sha256})",
            file=sys.stderr,
        )
        return 0
    except (VerificationError, OSError) as exc:
        print(f"IPA verification failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
