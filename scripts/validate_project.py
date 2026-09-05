#!/usr/bin/env python3
"""Validate the repository's security, build, and packaging contracts.

The script intentionally uses only the Python standard library so it can be
run on Windows before a push and on a clean GitHub macOS runner. It is a source
contract check, not a replacement for SwiftPM/XCTest or the IPA verifier.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, Sequence


EXPECTED_BUNDLE_ID = "io.github.times1368.sstvencoder"
EXPECTED_MARKETING_VERSION = "1.1.2"
EXPECTED_BUILD_VERSION = "4"
EXPECTED_IOS_VERSION = "17.0"
EXPECTED_SWIFT_TOOLS_VERSION = "5.9"


class ContractValidator:
    def __init__(self, root: Path) -> None:
        self.root = root.resolve()
        self.errors: list[str] = []

    def fail(self, message: str) -> None:
        self.errors.append(message)

    def relative(self, path: Path) -> str:
        try:
            return path.resolve().relative_to(self.root).as_posix()
        except ValueError:
            return str(path)

    def require_file(self, relative_path: str) -> Path | None:
        path = self.root / relative_path
        if not path.is_file():
            self.fail(f"missing required file: {relative_path}")
            return None
        return path

    def read_text(self, relative_path: str) -> str:
        path = self.require_file(relative_path)
        if path is None:
            return ""
        try:
            return path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            self.fail(f"required text file is not UTF-8: {relative_path}")
            return ""
        except OSError as exc:
            self.fail(f"could not read {relative_path}: {exc}")
            return ""

    def require_regex(
        self,
        text: str,
        pattern: str,
        message: str,
        *,
        flags: int = re.MULTILINE,
    ) -> None:
        if not re.search(pattern, text, flags):
            self.fail(message)

    def reject_regex(
        self,
        text: str,
        pattern: str,
        message: str,
        *,
        flags: int = re.MULTILINE,
    ) -> None:
        match = re.search(pattern, text, flags)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            self.fail(f"{message} (line {line})")

    def validate_package(self) -> None:
        package = self.read_text("SSTVKit/Package.swift")
        if not package:
            return

        self.require_regex(
            package,
            rf"^\s*//\s*swift-tools-version:\s*{re.escape(EXPECTED_SWIFT_TOOLS_VERSION)}\s*$",
            "SSTVKit must use swift-tools-version 5.9",
        )
        self.require_regex(
            package,
            r"\.iOS\s*\(\s*\.v17\s*\)",
            "SSTVKit must declare iOS 17 support",
        )
        self.require_regex(
            package,
            r"name\s*:\s*[\"']SSTVKit[\"']",
            "Swift package must be named SSTVKit",
        )
        self.require_regex(
            package,
            r"\.library\s*\(\s*name\s*:\s*[\"']SSTVKit[\"']",
            "SSTVKit must expose a library product",
        )
        self.require_regex(
            package,
            r"\.testTarget\s*\(\s*name\s*:\s*[\"']SSTVKitTests[\"']",
            "SSTVKitTests test target is required",
        )
        self.reject_regex(
            package,
            r"\.package\s*\(",
            "third-party Swift package dependencies are not allowed",
        )
        self.reject_regex(
            package,
            r"\burl\s*:",
            "remote Swift package URLs are not allowed",
        )
        self.reject_regex(
            package,
            r"\.(?:binaryTarget|systemLibrary|plugin)\s*\(",
            "binary, system-library, and plugin package targets are not allowed",
        )

        source_root = self.root / "SSTVKit" / "Sources"
        source_files = sorted(source_root.rglob("*.swift")) if source_root.is_dir() else []
        if not source_files:
            self.fail("SSTVKit/Sources must contain Swift source files")
            return

        all_source = ""
        import_re = re.compile(
            r"^\s*(?:@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?://.*)?$",
            re.MULTILINE,
        )
        for path in source_files:
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as exc:
                self.fail(f"could not read {self.relative(path)}: {exc}")
                continue
            all_source += "\n" + text
            for imported in import_re.findall(text):
                if imported != "Foundation":
                    self.fail(
                        f"{self.relative(path)} imports {imported}; "
                        "SSTVKit sources may import Foundation only"
                    )

        for marker in ("RIFF", "WAVE", "fmt ", "data"):
            if marker not in all_source:
                self.fail(f"SSTVKit WAV writer is missing the {marker!r} marker")
        if "Int16" not in all_source:
            self.fail("SSTVKit WAV output must explicitly quantize to signed Int16 PCM")

    def validate_asset_catalog_sources(self, project: str) -> None:
        # Check this repository's explicit, two-space-indented XcodeGen spec.
        # A path mentioned elsewhere (especially under the ignored target-level
        # resources key or in the test target) does not add it to the app.
        self.reject_regex(
            project,
            r"^ {4}resources[ \t]*:",
            "XcodeGen ignores target-level resources; use sources with buildPhase: resources",
        )
        app_target = re.search(
            r"^  SSTVEncoder:[ \t]*\n(?P<body>.*?)(?=^  \S|\Z)",
            project,
            re.MULTILINE | re.DOTALL,
        )
        if app_target is None:
            return
        sources = re.search(
            r"^    sources:[ \t]*\n(?P<body>.*?)(?=^    \S|\Z)",
            app_target.group("body"),
            re.MULTILINE | re.DOTALL,
        )
        source_text = sources.group("body") if sources else ""
        for name, path in (
            ("AppIcon", "Resources/Generated/Assets.xcassets"),
            ("Theme", "Resources/Theme.xcassets"),
        ):
            entry = re.search(
                rf"^      - path:[ \t]*[\"']?{re.escape(path)}[\"']?[ \t]*"
                r"(?:\n(?P<body>.*?)(?=^      -|\Z)|\Z)",
                source_text,
                re.MULTILINE | re.DOTALL,
            )
            if entry is None:
                self.fail(f"{name} catalog must be in SSTVEncoder target sources: {path}")
                continue
            self.require_regex(
                entry.group("body") or "",
                r"^        buildPhase:[ \t]*resources[ \t]*$",
                f"{name} catalog must explicitly set buildPhase: resources",
            )

    def validate_xcodegen_project(self) -> None:
        project = self.read_text("SSTVEncoder/project.yml")
        if not project:
            return

        exact_checks = (
            (r"^name:\s*[\"']?SSTVEncoder[\"']?\s*$", "XcodeGen project name must be SSTVEncoder"),
            (
                rf"(?:^\s*(?:IPHONEOS_DEPLOYMENT_TARGET|deploymentTarget):\s*[\"']?{re.escape(EXPECTED_IOS_VERSION)}[\"']?\s*$|"
                rf"^\s*deploymentTarget:\s*\n\s+iOS:\s*[\"']?{re.escape(EXPECTED_IOS_VERSION)}[\"']?\s*$)",
                "XcodeGen must set the iOS deployment target to 17.0",
            ),
            (
                r"^\s*SWIFT_VERSION:\s*[\"']?5\.0[\"']?\s*$",
                "XcodeGen must set SWIFT_VERSION to Xcode's Swift 5 language-mode value, 5.0",
            ),
            (
                rf"^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*[\"']?{re.escape(EXPECTED_BUNDLE_ID)}[\"']?\s*$",
                f"app bundle identifier must be {EXPECTED_BUNDLE_ID}",
            ),
            (
                rf"^\s*MARKETING_VERSION:\s*[\"']?{re.escape(EXPECTED_MARKETING_VERSION)}[\"']?\s*$",
                f"marketing version must be {EXPECTED_MARKETING_VERSION}",
            ),
            (
                rf"^\s*CURRENT_PROJECT_VERSION:\s*[\"']?{EXPECTED_BUILD_VERSION}[\"']?\s*$",
                f"build version must be {EXPECTED_BUILD_VERSION}",
            ),
            (r"^\s{2}SSTVEncoder:\s*$", "XcodeGen must define the SSTVEncoder target"),
            (r"^\s+type:\s*application\s*$", "SSTVEncoder must be an application target"),
            (r"^\s+platform:\s*iOS\s*$", "SSTVEncoder must target iOS"),
            (r"^\s{2}SSTVEncoderTests:\s*$", "an SSTVEncoderTests target is required"),
            (r"^\s+type:\s*bundle\.unit-test\s*$", "SSTVEncoderTests must be a unit-test bundle"),
            (r"^\s{2}SSTVKit:\s*$", "project.yml must declare the local SSTVKit package"),
            (r"^\s+path:\s*[\"']?\.\./SSTVKit[\"']?\s*$", "SSTVKit must be referenced through ../SSTVKit"),
            (r"^\s+-\s+package:\s*SSTVKit\s*$", "the app must link the SSTVKit package product"),
            (
                r"^\s*ASSETCATALOG_COMPILER_APPICON_NAME:\s*[\"']?AppIcon[\"']?\s*$",
                "XcodeGen must select the AppIcon asset set",
            ),
        )
        for pattern, message in exact_checks:
            self.require_regex(project, pattern, message)
        self.validate_asset_catalog_sources(project)

        test_target = re.search(
            r"^  SSTVEncoderTests:\s*\n(?P<body>.*?)(?=^  \S|\Z)",
            project,
            re.MULTILINE | re.DOTALL,
        )
        if test_target is not None:
            body = test_target.group("body")
            if not re.search(
                r"^\s{6}-\s+package:\s*SSTVKit\s*$",
                body,
                re.MULTILINE,
            ):
                self.fail("SSTVEncoderTests must directly depend on the SSTVKit package")

        self.reject_regex(
            project,
            r"^\s+(?:url|github):\s*",
            "remote XcodeGen package dependencies are not allowed",
        )
        self.reject_regex(
            project,
            r"^\s*-?\s*(?:framework|carthage):\s*",
            "prebuilt/Carthage framework dependencies are not allowed",
        )
        signing_setting = re.compile(
            r"^\s*(DEVELOPMENT_TEAM|PROVISIONING_PROFILE(?:_SPECIFIER)?|"
            r"CODE_SIGN_IDENTITY|CODE_SIGN_ENTITLEMENTS):\s*(.*?)\s*$",
            re.MULTILINE,
        )
        for match in signing_setting.finditer(project):
            value = match.group(2).strip()
            if value not in {"", "\"\"", "''"}:
                line = project.count("\n", 0, match.start()) + 1
                self.fail(
                    "repository project settings must not bind signing identities, "
                    f"profiles, or entitlements ({match.group(1)} at line {line})"
                )

        app_root = self.root / "SSTVEncoder"
        swift_files = sorted(app_root.rglob("*.swift")) if app_root.is_dir() else []
        if not swift_files:
            self.fail("SSTVEncoder must contain Swift app source files")
            return

        app_texts: list[tuple[Path, str]] = []
        for path in swift_files:
            try:
                app_texts.append((path, path.read_text(encoding="utf-8")))
            except (OSError, UnicodeDecodeError) as exc:
                self.fail(f"could not read {self.relative(path)}: {exc}")

        forbidden_source_patterns = (
            (r"^\s*import\s+(?:Network|NetworkExtension|MultipeerConnectivity|PushToTalk)\b", "network/PTT framework import"),
            (r"\bURLSession\b", "URLSession networking API"),
            (r"\bNW(?:Connection|Listener|PathMonitor|Browser)\b", "Network.framework API"),
            (r"\bwebSocketTask\b|\bWebSocket\b", "WebSocket API"),
            (r"\b(?:PTT|PushToTalk)\b", "PTT API or coupling"),
        )
        for path, text in app_texts:
            for pattern, label in forbidden_source_patterns:
                match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
                if match:
                    line = text.count("\n", 0, match.start()) + 1
                    self.fail(f"{self.relative(path)}:{line} contains forbidden {label}")

        microphone_source = self.require_file(
            "SSTVEncoder/Core/MicrophoneReceiver.swift"
        )
        microphone_patterns = (
            r"\brequestRecordPermission\b",
            r"\.inputNode\b",
            r"\.record\b",
        )
        for path, text in app_texts:
            for pattern in microphone_patterns:
                if re.search(pattern, text, re.MULTILINE | re.IGNORECASE):
                    if microphone_source is None or path.resolve() != microphone_source.resolve():
                        self.fail(
                            f"{self.relative(path)} contains microphone access outside "
                            "the explicit receive adapter"
                        )

        microphone_text = self.read_text(
            "SSTVEncoder/Core/MicrophoneReceiver.swift"
        )
        if microphone_text:
            for pattern, message in (
                (r"AVAudioApplication\.requestRecordPermission", "receiver must request microphone permission explicitly"),
                (r"\.inputNode\b", "receiver must use AVAudioEngine inputNode"),
                (r"func\s+stop\s*\(", "receiver must expose deterministic microphone cleanup"),
            ):
                self.require_regex(microphone_text, pattern, message)

        app_combined = "\n".join(text for _, text in app_texts)
        if not re.search(r"\b48_?000(?:\.0)?\b", app_combined):
            self.fail("app sources must explicitly request 48 kHz encoding/playback")

        metadata_files = sorted(
            path
            for path in app_root.rglob("*")
            if path.is_file() and path.suffix.lower() in {".plist", ".entitlements", ".yml", ".yaml"}
        )
        forbidden_metadata = re.compile(
            r"NSLocalNetworkUsageDescription|NSBonjourServices|"
            r"com\.apple\.developer\.networking|com\.apple\.developer\.push-to-talk|"
            r"aps-environment",
            re.IGNORECASE,
        )
        for path in metadata_files:
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError) as exc:
                self.fail(f"could not read {self.relative(path)}: {exc}")
                continue
            match = forbidden_metadata.search(text)
            if match:
                line = text.count("\n", 0, match.start()) + 1
                self.fail(
                    f"{self.relative(path)}:{line} contains forbidden network/PTT metadata"
                )

        info_plist = self.read_text("SSTVEncoder/App/Info.plist")
        self.require_regex(
            info_plist,
            r"<key>NSMicrophoneUsageDescription</key>\s*<string>[^<]+</string>",
            "Info.plist must explain microphone use for explicit receiving",
            flags=re.MULTILINE | re.DOTALL,
        )
        self.require_regex(
            project,
            r"^\s*NSMicrophoneUsageDescription:\s*\S.+$",
            "XcodeGen must preserve the microphone privacy string",
        )

    def validate_app_icon(self) -> None:
        generator = self.read_text("scripts/generate_app_icon.py")
        source_notes = self.read_text(
            "SSTVEncoder/Resources/AppIconSource/README.md"
        )

        if generator:
            required_generator_patterns = (
                (r"^from\s+PIL\s+import\s+", "AppIcon generator must use Pillow"),
                (r"^ICON_SIZE\s*=\s*1024\s*$", "AppIcon generator must require a 1024 px source"),
                (r"AppIcon\.appiconset", "AppIcon generator must create an AppIcon asset set"),
                (r"[\"']platform[\"']\s*:\s*[\"']ios[\"']", "AppIcon catalog must target iOS"),
                (r"convert\s*\(\s*[\"']RGB[\"']\s*\)", "AppIcon generator must remove alpha"),
            )
            for pattern, message in required_generator_patterns:
                self.require_regex(generator, pattern, message)

        if source_notes:
            self.require_regex(
                source_notes,
                r"SSTVEncoder/Resources/AppIconSource/AppIcon-1024\.png",
                "AppIcon source notes must name the conventional 1024 px source path",
            )
            self.require_regex(
                source_notes,
                r"1024\s*x\s*1024",
                "AppIcon source notes must require exact 1024 x 1024 dimensions",
                flags=re.MULTILINE | re.IGNORECASE,
            )

    def validate_workflow(self) -> None:
        workflow = self.read_text(".github/workflows/ios.yml")
        if not workflow:
            return

        required_patterns = (
            (r"^permissions:\s*\n\s{2}contents:\s*read\s*$", "workflow must set global contents: read permission"),
            (r"^\s+runs-on:\s*macos-14\s*$", "compatibility job must use macos-14"),
            (r"^\s+runs-on:\s*macos-15\s*$", "current jobs must use macos-15"),
            (r"Xcode_15\.0\.1\.app", "compatibility job must explicitly select Xcode 15.0.1"),
            (r"Swift version 5\\\.9", "compatibility job must verify the Swift 5.9 toolchain"),
            (r"Xcode_16\.4\.app", "workflow must explicitly select Xcode 16.4"),
            (r"python3\s+-m\s+venv", "workflow must isolate the AppIcon generator dependency"),
            (r"Pillow==12\.3\.0", "workflow must pin the Pillow AppIcon dependency"),
            (r"scripts/generate_app_icon\.py", "workflow must generate AppIcon assets"),
            (r"scripts/validate_project\.py", "workflow must run the source contract validator"),
            (r"swift\s+test\s+--package-path\s+SSTVKit", "workflow must run SwiftPM tests"),
            (r"xcodegen\s+generate", "workflow must generate the Xcode project"),
            (r"simctl\s+list\s+devices\s+available\s+--json", "workflow must dynamically select an available simulator"),
            (r"-destination\s+[\"']?platform=iOS Simulator,id=", "workflow must test on the selected simulator UDID"),
            (r"--runtime-major\s+17", "compatibility tests must select an available iOS 17 simulator"),
            (r"^\s{2}tests:\s*\n(?:.*\n)*?\s{4}needs:\s*compatibility\s*$", "current tests must follow the compatibility job"),
            (r"^\s{2}package:\s*\n\s{4}needs:\s*tests\s*$", "package job must be gated by the tests job"),
            (r"-configuration\s+Release", "device package must use Release configuration"),
            (r"-destination\s+[\"']generic/platform=iOS[\"']", "device build must target generic/platform=iOS"),
            (r"CODE_SIGNING_ALLOWED=NO", "device build must disable code signing"),
            (r"CODE_SIGNING_REQUIRED=NO", "device build must not require code signing"),
            (r"Payload/SSTVEncoder\.app", "workflow must manually package Payload/SSTVEncoder.app"),
            (r"scripts/verify_ipa\.py", "workflow must run the IPA verifier"),
            (r"actions/upload-artifact@v4", "workflow must upload with actions/upload-artifact@v4"),
            (r"actions/download-artifact@v4", "workflow must independently download the artifact"),
            (r"^\s{2}verify_artifact:\s*\n\s{4}needs:\s*package\s*$", "verification job must depend on the package job"),
            (r"--expected-manifest", "downstream job must compare the verification manifest"),
            (r"--expected-sha256-file", "downstream job must re-check the published SHA-256 file"),
        )
        for pattern, message in required_patterns:
            self.require_regex(workflow, pattern, message)

        forbidden_patterns = (
            (r"^\s*contents:\s*write\s*$", "workflow must never request contents: write"),
            (r"^\s*(?:actions|packages|pull-requests|id-token):\s*write\s*$", "workflow must not request write permissions"),
            (r"\bgh\s+release\b", "workflow must not create GitHub releases"),
            (r"softprops/action-gh-release|actions/create-release", "workflow must not use release actions"),
        )
        for pattern, message in forbidden_patterns:
            self.reject_regex(workflow, pattern, message, flags=re.MULTILINE | re.IGNORECASE)

        icon_generation_count = len(
            re.findall(r"scripts/generate_app_icon\.py", workflow)
        )
        xcodegen_count = len(re.findall(r"xcodegen\s+generate", workflow))
        if icon_generation_count != xcodegen_count:
            self.fail(
                "every XcodeGen invocation must have a matching AppIcon generation step"
            )

    def validate(self) -> Sequence[str]:
        if not self.root.is_dir():
            self.fail(f"repository root does not exist: {self.root}")
            return self.errors
        self.validate_package()
        self.validate_xcodegen_project()
        self.validate_app_icon()
        self.validate_workflow()
        return self.errors


def parse_args(argv: Iterable[str]) -> argparse.Namespace:
    default_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=default_root,
        help=f"repository root (default: {default_root})",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    validator = ContractValidator(args.root)
    errors = validator.validate()
    if errors:
        print(f"Contract validation failed with {len(errors)} error(s):", file=sys.stderr)
        for index, error in enumerate(errors, start=1):
            print(f"  {index}. {error}", file=sys.stderr)
        return 1

    print(
        "Contract validation passed: iOS 17 / Swift tools 5.9, local SSTVKit boundary, "
        "48 kHz Int16 WAV path, explicit receive-only microphone privacy, no network/PTT coupling, "
        "and gated unsigned IPA CI."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
