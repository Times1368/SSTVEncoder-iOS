import SwiftUI
import UIKit
import XCTest
@testable import SSTVEncoder

@MainActor
final class ThemeTests: XCTestCase {
    func testAppHostContainsCompiledAssetCatalog() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.github.times1368.sstvencoder")
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Assets", withExtension: "car"),
            "应用宿主中缺少已编译的颜色与图标资产：\(Bundle.main.bundlePath)"
        )
    }

    func testEveryNamedColorResolvesInBothAppearances() {
        for token in Theme.ColorToken.allCases {
            for style in [UIUserInterfaceStyle.light, .dark] {
                XCTAssertNotNil(UIColor(
                    named: token.rawValue,
                    in: .main,
                    compatibleWith: UITraitCollection(userInterfaceStyle: style)
                ), token.rawValue)
            }
        }
    }

    func testAccentAndInstrumentMatchTheApprovedPalette() throws {
        try assertColor(.accent, style: .light, hex: 0x2F6BFF)
        try assertColor(.accent, style: .dark, hex: 0x4C86FF)
        for style in [UIUserInterfaceStyle.light, .dark] {
            try assertColor(.instrument, style: style, hex: 0x060A14)
            try assertColor(.signalOK, style: style, hex: 0x30D158)
            try assertColor(.signalWarn, style: style, hex: 0xFF9F0A)
            try assertColor(.signalBad, style: style, hex: 0xFF453A)
        }
    }

    func testApprovedComponentMetrics() {
        XCTAssertEqual(Theme.Spacing.unit, 8)
        XCTAssertEqual(Theme.Metrics.cardRadius, 16)
        XCTAssertEqual(Theme.Metrics.primaryButtonHeight, 52)
        XCTAssertEqual(Theme.Metrics.statusHeight, 44)
        XCTAssertEqual(Theme.Metrics.waterfallHeight, 132)
        XCTAssertEqual(Theme.barColors.count, 6)
    }

    func testDisplayProgressIsClampedWithoutTouchingTheEncoder() {
        XCTAssertEqual(Theme.displayProgress(-0.5), 0)
        XCTAssertEqual(Theme.displayProgress(0.25), 0.25)
        XCTAssertEqual(Theme.displayProgress(1.5), 1)
        XCTAssertEqual(Theme.displayProgress(.nan), 0)
        XCTAssertEqual(Theme.displayProgress(.infinity), 0)
    }

    private func assertColor(
        _ token: Theme.ColorToken,
        style: UIUserInterfaceStyle,
        hex: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let color = try XCTUnwrap(UIColor(named: token.rawValue, in: .main, compatibleWith: traits))
            .resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(red, CGFloat((hex >> 16) & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(green, CGFloat((hex >> 8) & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(blue, CGFloat(hex & 255) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(alpha, 1, accuracy: 0.001, file: file, line: line)
    }
}
