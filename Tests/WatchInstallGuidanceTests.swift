import Foundation
import XCTest

@testable import PagePilot

final class WatchInstallGuidanceTests: XCTestCase {
    func testWatchAppURLTargetsIPhoneWatchApp() {
        XCTAssertEqual(WatchPageTurnService.watchAppURL.absoluteString, "bridge://")
    }

    func testInstallStateShowsActionThatOpensWatchApp() throws {
        let source = try Self.guideViewSource()

        let installCase = try Self.requiredLine(
            "if service.watchAvailability == .appNotInstalled {",
            in: source
        )
        let actionButton = try Self.requiredLine(
            "onboarding_watch_install_action",
            in: source,
            startingAfter: installCase
        )
        let openCall = try Self.requiredLine(
            "openURL(WatchPageTurnService.watchAppURL)",
            in: source,
            startingAfter: actionButton
        )

        XCTAssertGreaterThan(openCall, installCase)
    }

    func testInstallActionIsLocalizedForSupportedLanguages() throws {
        let expected: [String: String] = [
            "en": "Open Watch App",
            "zh-Hans": "打开 Watch App",
            "de": "Watch-App öffnen",
            "es": "Abrir la app Watch",
            "fr": "Ouvrir l’app Watch",
        ]

        for (language, action) in expected {
            let bundleURL = try XCTUnwrap(
                Bundle.main.url(forResource: language, withExtension: "lproj"),
                "Missing localization bundle for \(language)"
            )
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))

            XCTAssertEqual(
                bundle.localizedString(forKey: "onboarding_watch_install_action", value: nil, table: nil),
                action,
                "\(language) install action"
            )
        }
    }

    private static func guideViewSource() throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL
            .appendingPathComponent("Sources/Reader/Common/OnboardingWatchGuideView.swift")

        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func requiredLine(
        _ line: String,
        in source: String,
        startingAfter offset: Int = 0,
        file: StaticString = #filePath,
        lineNumber: UInt = #line
    ) throws -> Int {
        guard let position = self.range(of: line, in: source, startingAfter: offset) else {
            XCTFail("Required source boundary is missing: \(line)", file: file, line: lineNumber)
            return offset
        }
        return position
    }

    private static func range(of line: String, in source: String, startingAfter offset: Int = 0) -> Int? {
        guard offset <= source.utf16.count else { return nil }
        let start = String.Index(utf16Offset: offset, in: source)
        return source.range(of: line, range: start..<source.endIndex)?
            .lowerBound
            .utf16Offset(in: source)
    }
}
