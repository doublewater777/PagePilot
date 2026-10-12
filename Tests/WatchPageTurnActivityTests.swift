import Foundation
import XCTest
@testable import PagePilot

final class WatchPageTurnActivityTests: XCTestCase {
    func testOutcomeReadsTurnedAndNotTurnedReplies() {
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": true, "didTurnPage": true]), .turned)
        // End of book or a suppressed turn: delivered, but the page stayed.
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": true, "didTurnPage": false]), .notTurned)
    }

    func testOutcomeMapsErrorCodes() {
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": false, "errorCode": "NAVIGATOR_NOT_READY"]), .readerNotReady)
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": false, "errorCode": "IPAD_NOT_FOUND"]), .iPadNotFound)
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": false, "errorCode": "RELAY_TIMEOUT"]), .unreachable)
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": false, "errorCode": "PRO_REQUIRED"]), .proRequired)
        XCTAssertEqual(WatchPageTurnOutcome(payload: ["ok": false]), .unreachable)
    }

    func testReplayedDuplicateCommandIsNotAnOutcome() {
        XCTAssertNil(WatchPageTurnOutcome(payload: ["ok": true, "didTurnPage": false, "duplicate": true]))
    }

    func testOneWatchTapMergesIPhoneAndIPadResultsIntoOneRow() {
        var log = WatchPageTurnActivityLog()
        log.record(commandID: "tap-1", direction: .next, source: .watch, destination: .iPad, outcome: .turned)
        log.record(commandID: "tap-1", direction: .next, source: .watch, destination: .iPhone, outcome: .readerNotReady)

        XCTAssertEqual(log.entries.count, 1)
        let entry = log.entries[0]
        // iPhone first, then iPad, whatever order the replies arrive in.
        XCTAssertEqual(entry.results.map(\.destination), [.iPhone, .iPad])
        XCTAssertEqual(entry.results.map(\.outcome), [.readerNotReady, .turned])
        XCTAssertTrue(entry.isSuccess)
    }

    func testSeparateTapsStaySeparateAndNewestComesFirst() {
        var log = WatchPageTurnActivityLog()
        log.record(commandID: "tap-1", direction: .next, source: .watch, destination: .iPad, outcome: .turned)
        log.record(commandID: "tap-2", direction: .prev, source: .watch, destination: .iPad, outcome: .unreachable)

        XCTAssertEqual(log.entries.map(\.direction), [.prev, .next])
        XCTAssertFalse(log.entries[0].isSuccess)
    }

    func testLogKeepsOnlyTheLatestFiveTaps() {
        var log = WatchPageTurnActivityLog()
        for index in 0..<7 {
            log.record(commandID: "tap-\(index)", direction: .next, source: .watch, destination: .iPhone, outcome: .turned)
        }
        XCTAssertEqual(log.entries.count, 5)
        XCTAssertEqual(log.entries.first?.commandID, "tap-6")
    }

    func testRepliesWithoutCommandIDNeverMerge() {
        var log = WatchPageTurnActivityLog()
        log.record(commandID: nil, direction: .next, source: .iPhone, destination: .iPad, outcome: .turned)
        log.record(commandID: nil, direction: .next, source: .iPhone, destination: .iPad, outcome: .turned)
        XCTAssertEqual(log.entries.count, 2)
    }

    func testIPadResultIsHiddenOnlyWhileNoIPadIsChosen() {
        XCTAssertFalse(WatchPageTurnActivityLog.shouldRecord(destination: .iPad, hasSelectedIPad: false))
        XCTAssertTrue(WatchPageTurnActivityLog.shouldRecord(destination: .iPad, hasSelectedIPad: true))
        XCTAssertTrue(WatchPageTurnActivityLog.shouldRecord(destination: .iPad, outcome: .proRequired, hasSelectedIPad: false))
        XCTAssertTrue(WatchPageTurnActivityLog.shouldRecord(destination: .iPhone, hasSelectedIPad: false))
        XCTAssertTrue(WatchPageTurnActivityLog.shouldRecord(destination: .thisDevice, hasSelectedIPad: false))
    }

    func testPeerRequestCarriesWhoAsked() throws {
        let request = PagePilotPeerRequest(
            target: "11111111-1111-1111-1111-111111111111",
            kind: .command,
            action: .next,
            commandID: "c1",
            source: .iPhone
        )
        let decoded = try XCTUnwrap(PagePilotPeerRequest(frameObject: request.frameObject))
        XCTAssertEqual(decoded.source, .iPhone)

        var legacy = request.frameObject
        legacy.removeValue(forKey: "source")
        XCTAssertEqual(PagePilotPeerRequest(frameObject: legacy)?.source, .watch)
    }
}
