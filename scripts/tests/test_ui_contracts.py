from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

from scripts.validate_project import ContractValidator


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "SSTVEncoder/Resources/Theme.xcassets"


class ThemeContractTests(unittest.TestCase):
    def color_pairs(self, name: str) -> tuple[str, str]:
        payload = json.loads((CATALOG / f"{name}.colorset/Contents.json").read_text(encoding="utf-8"))
        self.assertEqual(len(payload["colors"]), 2, name)
        values = {}
        for item in payload["colors"]:
            dark = item.get("appearances") == [{"appearance": "luminosity", "value": "dark"}]
            components = item["color"]["components"]
            self.assertEqual(float(components["alpha"]), 1)
            values["dark" if dark else "any"] = "".join(
                f"{round(float(components[channel]) * 255):02X}" for channel in ("red", "green", "blue")
            )
        return values["any"], values["dark"]

    def test_approved_colors_have_any_and_dark_variants(self) -> None:
        expected = {
            "Accent": ("2F6BFF", "4C86FF"),
            "Instrument": ("060A14", "060A14"),
            "SignalOK": ("30D158", "30D158"),
            "SignalWarn": ("FF9F0A", "FF9F0A"),
            "SignalBad": ("FF453A", "FF453A"),
            "BarsWhite": ("E4ECF8", "E4ECF8"),
            "BarsYellow": ("FFD84A", "FFD84A"),
            "BarsCyan": ("2FD3E6", "2FD3E6"),
            "BarsGreen": ("34CF6A", "34CF6A"),
            "BarsMagenta": ("E052C6", "E052C6"),
            "BarsRed": ("FF4A3D", "FF4A3D"),
        }
        for name, colors in expected.items():
            with self.subTest(color=name):
                self.assertEqual(self.color_pairs(name), colors)

    def test_every_theme_token_has_an_asset(self) -> None:
        source = (ROOT / "SSTVEncoder/Features/DesignSystem/Theme.swift").read_text(encoding="utf-8")
        names = re.findall(r'case \w+ = "(\w+)"', source)
        self.assertGreaterEqual(len(names), 18)
        for name in names:
            with self.subTest(color=name):
                self.color_pairs(name)
        self.assertNotRegex(source, r"Color\s*\(\s*(?:red:|\.sRGB|hex:)")
        project = (ROOT / "SSTVEncoder/project.yml").read_text(encoding="utf-8")
        validator = ContractValidator(ROOT)
        validator.validate_asset_catalog_sources(project)
        self.assertEqual(validator.errors, [])

    def test_components_use_named_tokens_and_no_new_persistence_framework(self) -> None:
        source = (ROOT / "SSTVEncoder/Features/DesignSystem/Components.swift").read_text(encoding="utf-8")
        self.assertIn("disabledReason", source)
        self.assertIn("monospacedDigit()", source)
        self.assertIn("Capsule()", source)
        self.assertNotIn("SwiftData", source)
        self.assertNotIn("#available", source)
        self.assertNotRegex(source, r"Color\s*\(\s*(?:red:|\.sRGB|hex:)")


class TabShellContractTests(unittest.TestCase):
    def test_four_tab_shell_defaults_to_receive(self) -> None:
        source = (ROOT / "SSTVEncoder/Features/ContentView.swift").read_text(encoding="utf-8")
        shell = source.split("private struct EncoderView", 1)[0]
        self.assertIn("selectedTab = AppTab.defaultTab", shell)
        self.assertIn("TabView(selection: $selectedTab)", shell)
        for tab in ("receive", "transmit", "library", "settings"):
            self.assertIn(f".tag(AppTab.{tab})", shell)
        self.assertLess(shell.index("ReceiveView()"), shell.index("EncoderView()"))
        self.assertNotIn("startMicrophone", shell)
        self.assertNotIn("requestRecordPermission", shell)

    def test_existing_privacy_copy_is_preserved_and_titles_are_inline(self) -> None:
        transmit = (ROOT / "SSTVEncoder/Features/ContentView.swift").read_text(encoding="utf-8")
        receive = (ROOT / "SSTVEncoder/Features/ReceiveView.swift").read_text(encoding="utf-8")
        self.assertIn("仅生成、播放和导出音频；不会连接或控制电台发射。", transmit)
        self.assertIn("只有点击“启动麦克风”后才会请求并使用麦克风；原始音频不会保存或上传。", receive)
        self.assertIn('.navigationTitle("发射")', transmit)
        self.assertIn('.navigationTitle("接收")', receive)
        for source in (transmit, receive):
            self.assertIn(".navigationBarTitleDisplayMode(.inline)", source)
            self.assertIn(".onDisappear", source)

    def test_new_tabs_do_not_pretend_to_have_persistence_or_start_audio(self) -> None:
        source = (ROOT / "SSTVEncoder/Features/AppShellViews.swift").read_text(encoding="utf-8")
        self.assertIn("尚未启用自动入库", source)
        self.assertIn("设置页骨架", source)
        self.assertGreaterEqual(source.count(".navigationBarTitleDisplayMode(.inline)"), 3)
        for forbidden in ("SwiftData", "AVAudioEngine", "startMicrophone", "requestRecordPermission", "#available"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
