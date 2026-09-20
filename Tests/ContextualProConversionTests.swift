//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class ContextualProConversionTests: XCTestCase {
    func testReadingSessionIntentEventUsesStableDestinationAndSourceParameters() {
        let event = AnalyticsEvent.readingSessionInsightIntent(
            destination: .prediction,
            source: .sessionSummary
        )

        XCTAssertEqual(event.name, "reading_session_insight_intent")
        XCTAssertEqual(event.parameters["destination"], "prediction")
        XCTAssertEqual(event.parameters["source"], "reading_session_summary")
    }

    func testContextualUpgradeIntentUsesStableSourceParameters() {
        let event = AnalyticsEvent.proUpgradeIntent(source: .readingHistoryPreview)

        XCTAssertEqual(event.name, "pro_upgrade_intent")
        XCTAssertEqual(event.parameters, ["source": "reading_history_preview"])
        XCTAssertEqual(
            ReadingSessionAnalytics.Source.readingPredictionPreview.rawValue,
            "reading_prediction_preview"
        )
    }

    func testAnalyticsWrapperRemainsNotificationCenterBased() throws {
        let source = try Self.source(named: "Sources/Store/Analytics.swift")

        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .analyticsEventLogged"))
        XCTAssertFalse(source.contains("import Firebase"))
        XCTAssertFalse(source.contains("import Mixpanel"))
        XCTAssertFalse(source.contains("import Amplitude"))
    }

    func testSummaryOffersNonBlockingHistoryAndPredictionActionsWithoutPaywall() throws {
        let source = try Self.source(named: "Sources/Reader/Common/ReaderViewController.swift")

        XCTAssertTrue(source.contains(#"readingSessionSummary.history"#))
        XCTAssertTrue(source.contains(#"readingSessionSummary.prediction"#))
        XCTAssertTrue(source.contains("destination: .history"))
        XCTAssertTrue(source.contains("destination: .prediction"))
        XCTAssertTrue(source.contains("source: .sessionSummary"))

        guard let summaryStart = source.range(of: "final class ReadingSessionSummaryViewController"),
              let presenterStart = source.range(of: "enum ReadingSessionSummaryPresenter") else {
            return XCTFail("Summary UI boundaries are missing")
        }
        let summarySource = String(source[summaryStart.lowerBound..<presenterStart.lowerBound])
        XCTAssertFalse(summarySource.contains("PaywallView"))
        XCTAssertTrue(summarySource.contains("dismissButton.addTarget"))
    }

    func testHistoryAndPredictionLockedSurfacesPreviewPremiumValueAndUseContextualPaywallSource() throws {
        let source = try Self.source(named: "Sources/Home/ReadingStatsView.swift")

        XCTAssertTrue(source.contains("ReadingPremiumPreviewCard("))
        XCTAssertTrue(source.contains("reading_history_preview_title"))
        XCTAssertTrue(source.contains("reading_prediction_preview_title"))
        XCTAssertTrue(source.contains(#"bodyText: NSLocalizedString("reading_history_preview_body""#))
        XCTAssertTrue(source.contains("let bodyText: String"))
        XCTAssertTrue(source.contains(".proUpgradeIntent(source: source)"))
        XCTAssertTrue(source.contains("PaywallView(analyticsSource: paywallSource.rawValue)"))
        XCTAssertTrue(source.contains("book == nil ? .readingHistoryPreview : .readingPredictionPreview"))

        guard let lockedStart = source.range(of: "private var lockedContent: some View"),
              let stateStart = source.range(
                of: "private func historyStateView",
                range: lockedStart.lowerBound..<source.endIndex
              ) else {
            return XCTFail("Locked preview surface boundaries are missing")
        }
        let lockedSource = String(source[lockedStart.lowerBound..<stateStart.lowerBound])
        XCTAssertTrue(lockedSource.contains(".frame(maxWidth: 520)"))
        XCTAssertFalse(lockedSource.contains("UIDevice.current"))
    }

    func testContextualPaywallLogsProvidedSourceInsteadOfOnlyGenericSheetSource() throws {
        let source = try Self.source(named: "Sources/Home/PaywallView.swift")

        XCTAssertTrue(source.contains(#"analyticsSource: String = "paywall_sheet""#))
        XCTAssertTrue(source.contains(".paywallViewed(source: analyticsSource)"))
    }

    func testRS7LocalizationKeysExistInEverySupportedAppLocale() throws {
        let paths = [
            "Sources/Resources/en.lproj/Localizable.strings",
            "Sources/Resources/zh-Hans.lproj/Localizable.strings",
            "Sources/Resources/es.lproj/Localizable.strings",
            "Sources/Resources/fr.lproj/Localizable.strings",
            "Sources/Resources/de.lproj/Localizable.strings",
        ]
        let keys = [
            "reader_session_summary_history_action",
            "reader_session_summary_prediction_action",
            "reading_prediction_locked_title",
            "reading_prediction_locked_body",
            "reading_history_preview_title",
            "reading_history_preview_body",
            "reading_prediction_preview_title",
            "reading_prediction_preview_body",
        ]

        for path in paths {
            let source = try Self.source(named: path)
            for key in keys {
                XCTAssertTrue(source.contains("\"\(key)\""), "\(path) is missing \(key)")
            }
        }
    }

    private static func source(named path: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryURL.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
