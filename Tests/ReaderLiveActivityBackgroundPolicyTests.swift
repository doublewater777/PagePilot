import Foundation
import XCTest
@testable import PagePilot

final class ReaderLiveActivityBackgroundPolicyTests: XCTestCase {
    func testReaderBackgroundingFinishesReadingSession() throws {
        let source = try Self.readerViewControllerSource()

        let backgroundHandler = try Self.requiredLine(
            "@objc private func appDidEnterBackground()",
            in: source
        )
        let finishCall = try Self.requiredLine(
            "readingSessionLifecycle.applicationDidEnterBackground(at: Date())",
            in: source,
            startingAfter: backgroundHandler
        )
        let nextBoundary = try Self.requiredLine(
            "@objc private func appDidBecomeActive()",
            in: source,
            startingAfter: finishCall
        )

        XCTAssertGreaterThan(finishCall, backgroundHandler)
        XCTAssertNil(
            Self.range(
                of: "readingSessionLifecycle.applicationDidBecomeActive(",
                in: source,
                startingAfter: backgroundHandler
            ).flatMap { $0 < nextBoundary ? $0 : nil },
            "Backgrounding must not restart the interval it just ended."
        )
    }

    func testReaderForegroundingRestartsReadingSessionOnlyThroughActiveBoundary() throws {
        let source = try Self.readerViewControllerSource()

        let foregroundHandler = try Self.requiredLine(
            "@objc private func appDidBecomeActive()",
            in: source
        )
        let startCall = try Self.requiredLine(
            "readingSessionLifecycle.applicationDidBecomeActive(",
            in: source,
            startingAfter: foregroundHandler
        )

        XCTAssertGreaterThan(startCall, foregroundHandler)
    }

    func testReaderExitEndsTheVisibleSession() throws {
        let source = try Self.readerViewControllerSource()

        let disappearBoundary = try Self.requiredLine(
            "override func viewWillDisappear(_ animated: Bool)",
            in: source
        )
        let finishCall = try Self.requiredLine(
            "readingSessionLifecycle.readerWillDisappear(at: Date())",
            in: source,
            startingAfter: disappearBoundary
        )

        XCTAssertGreaterThan(finishCall, disappearBoundary)
    }

    func testBackgroundForegroundCreatesTwoNonOverlappingSessions() throws {
        let bookId = Book.Id(rawValue: 11)
        var lifecycle = ReaderSessionLifecycle(bookId: bookId)
        let firstStart = Date(timeIntervalSince1970: 100)
        let backgroundAt = firstStart.addingTimeInterval(30)
        let secondStart = backgroundAt.addingTimeInterval(5)
        let dismissalAt = secondStart.addingTimeInterval(20)

        let first = try XCTUnwrap(
            lifecycle.readerDidAppear(
                at: firstStart,
                progression: 0.1,
                applicationIsActive: true
            )
        )
        XCTAssertEqual(first.bookId, bookId)

        let firstFinished = try XCTUnwrap(
            lifecycle.applicationDidEnterBackground(at: backgroundAt)
        )
        let second = try XCTUnwrap(
            lifecycle.applicationDidBecomeActive(
                at: secondStart,
                progression: 0.2
            )
        )
        let secondFinished = try XCTUnwrap(
            lifecycle.readerWillDisappear(at: dismissalAt)
        )

        XCTAssertLessThanOrEqual(firstFinished.endedAt, second.startedAt)
        XCTAssertEqual(firstFinished.bookId, bookId)
        XCTAssertEqual(secondFinished.bookId, bookId)
        XCTAssertEqual(secondFinished.startedAt, secondStart)
    }

    func testReaderDismissalFinalizesExactlyOnce() throws {
        var lifecycle = ReaderSessionLifecycle(bookId: Book.Id(rawValue: 12))
        let start = Date(timeIntervalSince1970: 200)

        XCTAssertNotNil(
            lifecycle.readerDidAppear(
                at: start,
                progression: 0.3,
                applicationIsActive: true
            )
        )
        XCTAssertNotNil(
            lifecycle.readerWillDisappear(at: start.addingTimeInterval(10))
        )
        XCTAssertNil(
            lifecycle.readerWillDisappear(at: start.addingTimeInterval(11))
        )
        XCTAssertNil(
            lifecycle.applicationDidEnterBackground(at: start.addingTimeInterval(12))
        )
    }

    func testSuccessfulDirectAndRelayWatchTurnsCountOnlyInsideActiveSession() throws {
        var lifecycle = ReaderSessionLifecycle(bookId: Book.Id(rawValue: 13))
        let start = Date(timeIntervalSince1970: 300)

        lifecycle.recordSuccessfulWatchPageTurn(origin: .direct)
        _ = lifecycle.readerDidAppear(
            at: start,
            progression: 0.4,
            applicationIsActive: true
        )
        lifecycle.recordSuccessfulWatchPageTurn(origin: .direct)
        lifecycle.recordSuccessfulWatchPageTurn(origin: .iPadRelay)

        let finished = try XCTUnwrap(
            lifecycle.readerWillDisappear(at: start.addingTimeInterval(15))
        )
        XCTAssertEqual(finished.watchPageTurns, 2)

        lifecycle.recordSuccessfulWatchPageTurn(origin: .direct)
        XCTAssertNil(
            lifecycle.applicationDidEnterBackground(at: start.addingTimeInterval(16))
        )
    }

    func testSeparateReadersKeepTheirOwnBookAttribution() throws {
        let firstBook = Book.Id(rawValue: 21)
        let secondBook = Book.Id(rawValue: 22)
        var firstReader = ReaderSessionLifecycle(bookId: firstBook)
        var secondReader = ReaderSessionLifecycle(bookId: secondBook)
        let start = Date(timeIntervalSince1970: 400)

        _ = firstReader.readerDidAppear(
            at: start,
            progression: 0.1,
            applicationIsActive: true
        )
        let firstFinished = try XCTUnwrap(
            firstReader.readerWillDisappear(at: start.addingTimeInterval(5))
        )

        _ = secondReader.readerDidAppear(
            at: start.addingTimeInterval(6),
            progression: 0.7,
            applicationIsActive: true
        )
        secondReader.recordSuccessfulWatchPageTurn(origin: .iPadRelay)
        let secondFinished = try XCTUnwrap(
            secondReader.readerWillDisappear(at: start.addingTimeInterval(12))
        )

        XCTAssertEqual(firstFinished.bookId, firstBook)
        XCTAssertEqual(secondFinished.bookId, secondBook)
        XCTAssertEqual(firstFinished.watchPageTurns, 0)
        XCTAssertEqual(secondFinished.watchPageTurns, 1)
    }

    func testSessionRequiresVisibleReaderAndActiveApplication() {
        var lifecycle = ReaderSessionLifecycle(bookId: Book.Id(rawValue: 30))
        let now = Date(timeIntervalSince1970: 500)

        XCTAssertNil(
            lifecycle.applicationDidBecomeActive(
                at: now,
                progression: 0.2
            )
        )
        XCTAssertNil(
            lifecycle.readerDidAppear(
                at: now,
                progression: 0.2,
                applicationIsActive: false
            )
        )
        XCTAssertNotNil(
            lifecycle.applicationDidBecomeActive(
                at: now.addingTimeInterval(1),
                progression: 0.2
            )
        )
    }

    func testWatchDirectAndIPadRelaySuccessPathsPublishMeasuredTurns() throws {
        let source = try Self.watchPageTurnServiceSource()

        XCTAssertEqual(
            Self.occurrenceCount(
                of: "recordSuccessfulWatchPageTurn(origin: .direct)",
                in: source
            ),
            1
        )
        XCTAssertEqual(
            Self.occurrenceCount(
                of: "recordSuccessfulWatchPageTurn(origin: .iPadRelay)",
                in: source
            ),
            1
        )
    }

    func testVisibleVisualReaderOwnsWatchNavigatorRegistration() throws {
        let source = try Self.visualReaderViewControllerSource()

        let appearBoundary = try Self.requiredLine(
            "override func viewWillAppear(_ animated: Bool)",
            in: source
        )
        let registerCall = try Self.requiredLine(
            "WatchPageTurnService.shared.registerNavigator(visualNavigator, publication: publication)",
            in: source,
            startingAfter: appearBoundary
        )
        let disappearBoundary = try Self.requiredLine(
            "override func viewWillDisappear(_ animated: Bool)",
            in: source,
            startingAfter: registerCall
        )
        let unregisterCall = try Self.requiredLine(
            "WatchPageTurnService.shared.unregisterNavigator(visualNavigator)",
            in: source,
            startingAfter: disappearBoundary
        )

        XCTAssertGreaterThan(registerCall, appearBoundary)
        XCTAssertLessThan(registerCall, disappearBoundary)
        XCTAssertGreaterThan(unregisterCall, disappearBoundary)
    }

    private static func readerViewControllerSource() throws -> String {
        try source(named: "Sources/Reader/Common/ReaderViewController.swift")
    }

    private static func visualReaderViewControllerSource() throws -> String {
        try source(named: "Sources/Reader/Common/VisualReaderViewController.swift")
    }

    private static func watchPageTurnServiceSource() throws -> String {
        try source(named: "Sources/App/Services/WatchPageTurnService.swift")
    }

    private static func source(named path: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL.appendingPathComponent(path)
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

    private static func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}


final class ReadingSessionSummaryTests: XCTestCase {
    func testMeaningfulThresholdQualifiesAtDurationBoundary() {
        XCTAssertNotNil(
            ReadingSessionSummaryPolicy.makeSummary(
                for: makeSession(durationSeconds: 120),
                todaySeconds: 0,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )
    }

    func testMeaningfulThresholdQualifiesAtOnePercentForwardProgress() {
        XCTAssertNotNil(
            ReadingSessionSummaryPolicy.makeSummary(
                for: makeSession(
                    durationSeconds: 10,
                    startProgression: 0.20,
                    endProgression: 0.21
                ),
                todaySeconds: 0,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )
    }

    func testMeaningfulThresholdQualifiesAtFiveWatchTurns() {
        XCTAssertNotNil(
            ReadingSessionSummaryPolicy.makeSummary(
                for: makeSession(durationSeconds: 10, watchPageTurns: 5),
                todaySeconds: 0,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )
    }

    func testTrivialExitDoesNotProduceSummary() {
        XCTAssertNil(
            ReadingSessionSummaryPolicy.makeSummary(
                for: makeSession(
                    durationSeconds: 119,
                    startProgression: 0.20,
                    endProgression: 0.209,
                    watchPageTurns: 4
                ),
                todaySeconds: 0,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )
    }

    func testSummaryCarriesSessionMetricsWithoutInventingWatchTurns() throws {
        let summary = try XCTUnwrap(
            ReadingSessionSummaryPolicy.makeSummary(
                for: makeSession(
                    durationSeconds: 125,
                    startProgression: 0.20,
                    endProgression: 0.35,
                    watchPageTurns: 0
                ),
                todaySeconds: 20 * 60,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )

        XCTAssertEqual(summary.durationSeconds, 125)
        XCTAssertEqual(summary.startProgression, 0.20, accuracy: 0.0001)
        XCTAssertEqual(summary.endProgression, 0.35, accuracy: 0.0001)
        XCTAssertEqual(summary.progressDelta, 0.15, accuracy: 0.0001)
        XCTAssertEqual(summary.watchPageTurns, 0)
        XCTAssertEqual(summary.dailyGoalFeedback, .remaining(minutes: 10))
    }

    func testDailyGoalCompletionIsSuppressedWhenExistingCelebrationWillFire() throws {
        let session = makeSession(durationSeconds: 120)

        let suppressed = try XCTUnwrap(
            ReadingSessionSummaryPolicy.makeSummary(
                for: session,
                todaySeconds: 30 * 60,
                goalMinutes: 30,
                suppressGoalCompletion: true
            )
        )
        XCTAssertNil(suppressed.dailyGoalFeedback)

        let alreadyCelebrated = try XCTUnwrap(
            ReadingSessionSummaryPolicy.makeSummary(
                for: session,
                todaySeconds: 30 * 60,
                goalMinutes: 30,
                suppressGoalCompletion: false
            )
        )
        XCTAssertEqual(alreadyCelebrated.dailyGoalFeedback, .complete)
    }

    func testSummaryIsOnlyRequestedForActualReaderExit() throws {
        let source = try Self.readerViewControllerSource()

        XCTAssertTrue(source.contains("isVisibleReaderExit: isReaderExit"))
        XCTAssertTrue(source.contains("isVisibleReaderExit: false"))
        XCTAssertTrue(source.contains("if isVisibleReaderExit, let detailedSession"))
    }

    @MainActor
    func testSummaryViewIsDismissibleAccessibleAndAdaptive() throws {
        let summary = ReadingSessionSummary(
            durationSeconds: 125,
            startProgression: 0.20,
            endProgression: 0.35,
            progressDelta: 0.15,
            watchPageTurns: 0,
            dailyGoalFeedback: .remaining(minutes: 10)
        )
        let viewController = ReadingSessionSummaryViewController(summary: summary)
        viewController.loadViewIfNeeded()

        XCTAssertFalse(viewController.isModalInPresentation)
        XCTAssertEqual(
            viewController.dismissButton.accessibilityIdentifier,
            "readingSessionSummary.dismiss"
        )
        XCTAssertNil(
            viewController.contentStack.arrangedSubviews.first {
                $0.accessibilityIdentifier == "readingSessionSummary.watchTurns"
            },
            "A zero Watch count must not create a fake Watch metric."
        )

        let labels = viewController.contentStack.arrangedSubviews.compactMap { $0 as? UILabel }
        XCTAssertFalse(labels.isEmpty)
        XCTAssertTrue(labels.allSatisfy(\.adjustsFontForContentSizeCategory))

        let titleLabel = try XCTUnwrap(
            labels.first { $0.accessibilityIdentifier == "readingSessionSummary.title" }
        )
        XCTAssertTrue(titleLabel.accessibilityTraits.contains(.header))

        viewController.view.bounds = CGRect(x: 0, y: 0, width: 320, height: 700)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        XCTAssertLessThanOrEqual(viewController.contentStack.frame.width, 272.5)

        viewController.view.bounds = CGRect(x: 0, y: 0, width: 1024, height: 900)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        XCTAssertLessThanOrEqual(
            viewController.contentStack.frame.width,
            ReadingSessionSummaryViewController.maximumContentWidth + 0.5
        )
    }

    private func makeSession(
        durationSeconds: Int,
        startProgression: Double = 0.20,
        endProgression: Double = 0.20,
        watchPageTurns: Int = 0
    ) -> ReadingSession {
        let start = Date(timeIntervalSince1970: 1_000)
        return ReadingSession(
            bookId: Book.Id(rawValue: 1),
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(durationSeconds)),
            startProgression: startProgression,
            endProgression: endProgression,
            watchPageTurns: watchPageTurns
        )
    }

    private static func readerViewControllerSource() throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL.appendingPathComponent(
            "Sources/Reader/Common/ReaderViewController.swift"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
