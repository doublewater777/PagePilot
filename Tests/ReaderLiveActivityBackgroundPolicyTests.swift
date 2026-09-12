import Foundation
import XCTest

final class ReaderLiveActivityBackgroundPolicyTests: XCTestCase {
    func testReaderBackgroundingFinishesReadingSession() throws {
        let source = try Self.readerViewControllerSource()

        XCTAssertNil(
            Self.range(of: "pauseForegroundReadingStatsIfNeeded", in: source),
            "Backgrounding ends the session, so there is no foreground stats to pause."
        )

        let backgroundHandler = try Self.requiredLine(
            "@objc private func appDidEnterBackground()",
            in: source
        )
        let finishCall = try Self.requiredLine(
            "finishReadingSessionIfNeeded(celebrateGoal: false)",
            in: source,
            startingAfter: backgroundHandler
        )
        let nextBoundary = try Self.requiredLine(
            "@objc private func appWillEnterForeground()",
            in: source,
            startingAfter: finishCall
        )

        XCTAssertGreaterThan(finishCall, backgroundHandler)
        XCTAssertNil(
            Self.range(of: "startReadingSessionIfNeeded()", in: source, startingAfter: backgroundHandler)
                .flatMap { $0 < nextBoundary ? $0 : nil },
            "Backgrounding must not restart a session it just ended."
        )
    }

    func testReaderForegroundingRestartsReadingSession() throws {
        let source = try Self.readerViewControllerSource()

        XCTAssertNil(
            Self.range(of: "resumeForegroundReadingStatsIfNeeded", in: source),
            "Foregrounding restarts the session, so there is no separate stats resume."
        )

        let foregroundHandler = try Self.requiredLine(
            "@objc private func appWillEnterForeground()",
            in: source
        )
        let startCall = try Self.requiredLine(
            "startReadingSessionIfNeeded()",
            in: source,
            startingAfter: foregroundHandler
        )

        XCTAssertGreaterThan(startCall, foregroundHandler)
    }

    func testReaderExitStillEndsWatchSessionAndLiveActivity() throws {
        let source = try Self.readerViewControllerSource()

        let disappearBoundary = try Self.requiredLine(
            "override func viewWillDisappear(_ animated: Bool)",
            in: source
        )
        let finishCall = try Self.requiredLine(
            "finishReadingSessionIfNeeded()",
            in: source,
            startingAfter: disappearBoundary
        )

        XCTAssertGreaterThan(finishCall, disappearBoundary)
    }

    private static func readerViewControllerSource() throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryURL
            .appendingPathComponent("Sources/Reader/Common/ReaderViewController.swift")

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
