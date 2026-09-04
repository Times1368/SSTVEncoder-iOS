from __future__ import annotations

import contextlib
import io
import json
import plistlib
import stat
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from PIL import Image

from scripts.generate_app_icon import generate_asset_catalog
from scripts.select_simulator import candidates_from_document, choose
from scripts.validate_project import ContractValidator
from scripts.verify_ipa import (
    CPU_TYPE_ARM64,
    LC_BUILD_VERSION,
    LC_CODE_SIGNATURE,
    PLATFORM_IOS,
    Expectations,
    VerificationError,
    main as verify_main,
    verify_ipa,
)


def macho_executable(*, cpu_type: int = CPU_TYPE_ARM64, signed: bool = False) -> bytes:
    build_version = struct.pack(
        "<IIIIII", LC_BUILD_VERSION, 24, PLATFORM_IOS, 17 << 16, 18 << 16, 0
    )
    signature = struct.pack("<II", LC_CODE_SIGNATURE, 8) if signed else b""
    commands = build_version + signature
    header = b"\xcf\xfa\xed\xfe" + struct.pack(
        "<iiIIIII",
        cpu_type,
        0,
        2,
        2 if signed else 1,
        len(commands),
        0,
        0,
    )
    return header + commands


def zip_info(name: str, mode: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name)
    info.create_system = 3
    info.external_attr = mode << 16
    if stat.S_ISDIR(mode):
        info.external_attr |= 0x10
    return info


def write_fixture(
    path: Path,
    *,
    signed: bool = False,
    cpu_type: int = CPU_TYPE_ARM64,
    extra_member: str | None = None,
) -> None:
    plist = plistlib.dumps(
        {
            "CFBundleExecutable": "SSTVEncoder",
            "CFBundleIdentifier": "io.github.times1368.sstvencoder",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "CFBundleVersion": "1",
            "DTPlatformName": "iphoneos",
            "MinimumOSVersion": "17.0",
        },
        fmt=plistlib.FMT_BINARY,
    )
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(zip_info("Payload/", stat.S_IFDIR | 0o755), b"")
        archive.writestr(
            zip_info("Payload/SSTVEncoder.app/", stat.S_IFDIR | 0o755), b""
        )
        archive.writestr(
            zip_info("Payload/SSTVEncoder.app/Info.plist", stat.S_IFREG | 0o644),
            plist,
        )
        archive.writestr(
            zip_info("Payload/SSTVEncoder.app/SSTVEncoder", stat.S_IFREG | 0o755),
            macho_executable(cpu_type=cpu_type, signed=signed),
        )
        if extra_member:
            archive.writestr(zip_info(extra_member, stat.S_IFREG | 0o644), b"bad")


class IPAValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.ipa = Path(self.temporary.name) / "SSTVEncoder.ipa"
        self.expectations = Expectations(
            app_name="SSTVEncoder",
            bundle_id="io.github.times1368.sstvencoder",
            marketing_version="1.0.0",
            build_version="1",
            minimum_os="17.0",
        )

    def test_valid_unsigned_arm64_fixture(self) -> None:
        write_fixture(self.ipa)
        manifest = verify_ipa(self.ipa, self.expectations)
        self.assertEqual(manifest["binary"]["architectures"], ["arm64"])
        self.assertTrue(manifest["security"]["unsigned"])
        self.assertEqual(len(manifest["artifact"]["sha256"]), 64)

    def test_path_traversal_is_rejected(self) -> None:
        write_fixture(self.ipa, extra_member="Payload/../escape")
        with self.assertRaisesRegex(VerificationError, "unsafe ZIP member path"):
            verify_ipa(self.ipa, self.expectations)

    def test_macho_code_signature_is_rejected(self) -> None:
        write_fixture(self.ipa, signed=True)
        with self.assertRaisesRegex(VerificationError, "LC_CODE_SIGNATURE"):
            verify_ipa(self.ipa, self.expectations)

    def test_non_arm64_executable_is_rejected(self) -> None:
        write_fixture(self.ipa, cpu_type=0x01000007)
        with self.assertRaisesRegex(VerificationError, "arm64-only"):
            verify_ipa(self.ipa, self.expectations)

    def test_written_integrity_files_are_reverified(self) -> None:
        write_fixture(self.ipa)
        manifest = Path(self.temporary.name) / "verification-manifest.json"
        checksum = Path(self.temporary.name) / "SSTVEncoder.ipa.sha256"
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(
                verify_main(
                    [
                        str(self.ipa),
                        "--manifest",
                        str(manifest),
                        "--sha256-file",
                        str(checksum),
                    ]
                ),
                0,
            )
            self.assertEqual(
                verify_main(
                    [
                        str(self.ipa),
                        "--expected-manifest",
                        str(manifest),
                        "--expected-sha256-file",
                        str(checksum),
                    ]
                ),
                0,
            )


class SimulatorSelectionTests(unittest.TestCase):
    def test_runtime_filter_and_newest_runtime_selection(self) -> None:
        document = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
                    {
                        "name": "iPhone 15",
                        "udid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "state": "Shutdown",
                        "isAvailable": True,
                    }
                ],
                "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                    {
                        "name": "iPhone 16 Pro",
                        "udid": "11111111-2222-3333-4444-555555555555",
                        "state": "Shutdown",
                        "isAvailable": True,
                    }
                ],
            }
        }
        i_os_17 = choose(candidates_from_document(document, 17))
        newest = choose(candidates_from_document(document, None))
        self.assertEqual(i_os_17.name, "iPhone 15")
        self.assertEqual(newest.name, "iPhone 16 Pro")


class AppIconGenerationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "Assets.xcassets"

    def test_placeholder_creates_opaque_single_size_app_icon_catalog(self) -> None:
        icon_path = generate_asset_catalog(source=None, output=self.output)

        with Image.open(icon_path) as icon:
            self.assertEqual(icon.size, (1024, 1024))
            self.assertEqual(icon.mode, "RGB")

        contents = json.loads(
            (self.output / "AppIcon.appiconset" / "Contents.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(
            contents["images"],
            [
                {
                    "filename": "AppIcon-1024.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
        )

    def test_exact_1024_source_is_converted_to_opaque_rgb(self) -> None:
        source = self.root / "source.png"
        Image.new("RGBA", (1024, 1024), (12, 34, 56, 100)).save(source)

        icon_path = generate_asset_catalog(source=source, output=self.output)

        with Image.open(icon_path) as icon:
            self.assertEqual(icon.mode, "RGB")
            self.assertEqual(icon.getpixel((0, 0)), (12, 34, 56))

    def test_non_1024_source_is_rejected_before_output_is_written(self) -> None:
        source = self.root / "wrong-size.png"
        Image.new("RGB", (512, 512), "black").save(source)

        with self.assertRaisesRegex(ValueError, "1024 x 1024"):
            generate_asset_catalog(source=source, output=self.output)
        self.assertFalse(self.output.exists())


class ProjectContractTests(unittest.TestCase):
    PROJECT = """\
name: SSTVEncoder
options:
  deploymentTarget:
    iOS: "17.0"
packages:
  SSTVKit:
    path: ../SSTVKit
targets:
  SSTVEncoder:
    type: application
    platform: iOS
    resources:
      - path: Resources/Generated/Assets.xcassets
    settings:
      base:
        SWIFT_VERSION: "5.0"
        PRODUCT_BUNDLE_IDENTIFIER: io.github.times1368.sstvencoder
        MARKETING_VERSION: 1.0.0
        CURRENT_PROJECT_VERSION: 1
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    dependencies:
      - package: SSTVKit
  SSTVEncoderTests:
    type: bundle.unit-test
    platform: iOS
    dependencies:
      - target: SSTVEncoder
      - package: SSTVKit
        product: SSTVKit
"""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "SSTVEncoder" / "App").mkdir(parents=True)
        (self.root / "SSTVEncoder" / "project.yml").write_text(
            self.PROJECT, encoding="utf-8"
        )
        (self.root / "SSTVEncoder" / "App" / "App.swift").write_text(
            "let requiredSampleRate = 48_000\n", encoding="utf-8"
        )

    def test_swift_5_language_mode_and_nested_deployment_target_pass(self) -> None:
        validator = ContractValidator(self.root)
        validator.validate_xcodegen_project()
        self.assertEqual(validator.errors, [])

    def test_project_swift_version_5_9_is_rejected(self) -> None:
        project = self.root / "SSTVEncoder" / "project.yml"
        project.write_text(
            self.PROJECT.replace('SWIFT_VERSION: "5.0"', 'SWIFT_VERSION: "5.9"'),
            encoding="utf-8",
        )
        validator = ContractValidator(self.root)
        validator.validate_xcodegen_project()
        self.assertTrue(any("SWIFT_VERSION" in error for error in validator.errors))

    def test_app_icon_catalog_and_build_setting_are_required(self) -> None:
        project = self.root / "SSTVEncoder" / "project.yml"
        project.write_text(
            self.PROJECT.replace(
                "    resources:\n"
                "      - path: Resources/Generated/Assets.xcassets\n",
                "",
            ).replace(
                "        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon\n",
                "",
            ),
            encoding="utf-8",
        )
        validator = ContractValidator(self.root)
        validator.validate_xcodegen_project()
        self.assertTrue(any("AppIcon" in error for error in validator.errors))

    def test_test_target_requires_a_direct_sstvkit_dependency(self) -> None:
        project = self.root / "SSTVEncoder" / "project.yml"
        project.write_text(
            self.PROJECT.replace(
                "      - target: SSTVEncoder\n"
                "      - package: SSTVKit\n"
                "        product: SSTVKit\n",
                "      - target: SSTVEncoder\n",
            ),
            encoding="utf-8",
        )
        validator = ContractValidator(self.root)
        validator.validate_xcodegen_project()
        self.assertTrue(
            any("directly depend" in error for error in validator.errors)
        )


if __name__ == "__main__":
    unittest.main()
