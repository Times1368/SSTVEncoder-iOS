from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


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
        self.assertIn("Resources/Theme.xcassets", project)

    def test_components_use_named_tokens_and_no_new_persistence_framework(self) -> None:
        source = (ROOT / "SSTVEncoder/Features/DesignSystem/Components.swift").read_text(encoding="utf-8")
        self.assertIn("disabledReason", source)
        self.assertIn("monospacedDigit()", source)
        self.assertIn("Capsule()", source)
        self.assertNotIn("SwiftData", source)
        self.assertNotIn("#available", source)
        self.assertNotRegex(source, r"Color\s*\(\s*(?:red:|\.sRGB|hex:)")


if __name__ == "__main__":
    unittest.main()
