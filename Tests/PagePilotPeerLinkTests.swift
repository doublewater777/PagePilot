import Foundation
import XCTest
@testable import PagePilot

final class PagePilotPeerLinkTests: XCTestCase {
    private let firstID = "11111111-1111-1111-1111-111111111111"
    private let secondID = "22222222-2222-2222-2222-222222222222"

    // MARK: - Frames

    func testDecoderSplitsSeveralFramesFromOneRead() throws {
        var data = try PagePilotPeerFrame.encode(["id": "a"])
        data.append(try PagePilotPeerFrame.encode(["id": "b"]))
        var decoder = PagePilotPeerFrameDecoder()

        let frames = try decoder.append(data)

        XCTAssertEqual(frames.compactMap { $0["id"] as? String }, ["a", "b"])
        XCTAssertTrue(decoder.buffer.isEmpty)
    }

    func testDecoderWaitsForTheRestOfAFrame() throws {
        let data = try PagePilotPeerFrame.encode(["id": "a", "kind": "status"])
        let split = data.count / 2
        var decoder = PagePilotPeerFrameDecoder()

        XCTAssertTrue(try decoder.append(data.prefix(split)).isEmpty)
        let frames = try decoder.append(data.suffix(from: split))

        XCTAssertEqual(frames.first?["kind"] as? String, "status")
    }

    func testDecoderKeepsTrailingPartialFrameForTheNextRead() throws {
        var data = try PagePilotPeerFrame.encode(["id": "a"])
        let second = try PagePilotPeerFrame.encode(["id": "b"])
        data.append(second.prefix(3))
        var decoder = PagePilotPeerFrameDecoder()

        XCTAssertEqual(try decoder.append(data).count, 1)
        XCTAssertEqual(try decoder.append(second.suffix(from: 3)).first?["id"] as? String, "b")
    }

    func testDecoderRejectsOversizedAndMalformedInput() {
        var oversized = PagePilotPeerFrameDecoder()
        XCTAssertThrowsError(try oversized.append(Data(repeating: 0x41, count: PagePilotPeerFrame.maximumBytes + 1)))

        var malformed = PagePilotPeerFrameDecoder()
        XCTAssertThrowsError(try malformed.append(Data("not json\n".utf8)))
    }

    // MARK: - Messages

    func testCommandRequestRoundTripsWithStableCommandID() throws {
        let request = PagePilotPeerRequest(target: firstID.uppercased(), kind: .command, action: .next, commandID: "turn-1")

        let decoded = try XCTUnwrap(PagePilotPeerRequest(frameObject: request.frameObject))

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.target, firstID)
        XCTAssertEqual(decoded.commandID, "turn-1")
    }

    func testCommandWithoutPageDirectionIsInvalid() {
        XCTAssertNil(PagePilotPeerRequest(frameObject: ["id": "1", "target": firstID, "kind": "command"]))
        XCTAssertNil(PagePilotPeerRequest(frameObject: ["id": "1", "target": firstID, "kind": "delete"]))
        XCTAssertNotNil(PagePilotPeerRequest(frameObject: ["id": "1", "target": firstID, "kind": "status"]))
    }

    func testResponsesCarryPayloadOrTypedError() throws {
        let success = try XCTUnwrap(PagePilotPeerResponse.parse(
            PagePilotPeerResponse.success(id: "1", payload: ["ok": true])
        ))
        XCTAssertEqual(success.id, "1")
        XCTAssertEqual(try success.result.get()["ok"] as? Bool, true)

        let failure = try XCTUnwrap(PagePilotPeerResponse.parse(
            PagePilotPeerResponse.failure(id: "2", error: .wrongTarget)
        ))
        XCTAssertEqual(failure.result.failureValue, .wrongTarget)

        let unknown = try XCTUnwrap(PagePilotPeerResponse.parse(["id": "3", "error": "mystery"]))
        XCTAssertEqual(unknown.result.failureValue, .invalidMessage)
    }

    func testHostAcceptsOnlyItsOwnIdentityWithPro() {
        let request = PagePilotPeerRequest(target: firstID, kind: .status)

        XCTAssertNil(PagePilotPeerHostValidation.rejection(
            for: request, localIdentifier: firstID.uppercased(), hasProAccess: true
        ))
        XCTAssertEqual(PagePilotPeerHostValidation.rejection(
            for: request, localIdentifier: secondID, hasProAccess: true
        ), .wrongTarget)
        XCTAssertEqual(PagePilotPeerHostValidation.rejection(
            for: request, localIdentifier: firstID, hasProAccess: false
        ), .proRequired)
    }

    func testErrorsMapToExistingWatchCodesAndRetryOnlyDroppedLinks() {
        XCTAssertEqual(PagePilotPeerError.notFound.watchErrorCode, "IPAD_NOT_FOUND")
        XCTAssertEqual(PagePilotPeerError.wrongTarget.watchErrorCode, "IPAD_NOT_FOUND")
        XCTAssertEqual(PagePilotPeerError.timedOut.watchErrorCode, "RELAY_TIMEOUT")
        XCTAssertEqual(PagePilotPeerError.proRequired.watchErrorCode, "PRO_REQUIRED")

        XCTAssertTrue(PagePilotPeerError.connectionLost.isRetryable)
        XCTAssertTrue(PagePilotPeerError.unreachable.isRetryable)
        XCTAssertFalse(PagePilotPeerError.timedOut.isRetryable)
        XCTAssertFalse(PagePilotPeerError.notFound.isRetryable)
        XCTAssertFalse(PagePilotPeerError.proRequired.isRetryable)
    }

    func testPendingRequestsDrainInSendOrder() {
        var pending = PagePilotPeerPendingRequests<String>()
        pending.add("first", for: "1")
        pending.add("second", for: "2")
        pending.add("third", for: "3")

        XCTAssertEqual(pending.remove("2"), "second")
        XCTAssertNil(pending.remove("2"))
        XCTAssertEqual(pending.removeAll(), ["first", "third"])
        XCTAssertTrue(pending.isEmpty)
    }

    // MARK: - Identity and selection

    func testStableIdentityRoundTripsThroughBonjourServiceName() {
        let serviceName = PagePilotRelayIdentity.serviceName(for: firstID)

        XCTAssertEqual(PagePilotRelayIdentity.identifier(fromServiceName: serviceName), firstID)
        XCTAssertNil(PagePilotRelayIdentity.identifier(fromServiceName: "PagePilot-iPad"))
        XCTAssertNil(PagePilotRelayIdentity.identifier(fromServiceName: "PagePilot-iPad-not-a-uuid"))
    }

    func testDiscoveredServiceBecomesSelectableTarget() throws {
        let target = try XCTUnwrap(PagePilotNearbyTarget.from(
            serviceName: PagePilotRelayIdentity.serviceName(for: firstID),
            name: "Bedroom iPad",
            bookTitle: "Dune"
        ))
        XCTAssertEqual(target, PagePilotNearbyTarget(id: firstID, name: "Bedroom iPad", bookTitle: "Dune"))

        XCTAssertNil(PagePilotNearbyTarget.from(serviceName: "other-service", name: "Other", bookTitle: nil))
        let unnamed = try XCTUnwrap(PagePilotNearbyTarget.from(
            serviceName: PagePilotRelayIdentity.serviceName(for: secondID),
            name: "  ",
            bookTitle: nil
        ))
        XCTAssertEqual(unnamed.name, "iPad")
        XCTAssertEqual(unnamed.bookTitle, "")
    }

    func testLegacyLANAssociationMigratesOnceAndExplicitSelectionWins() throws {
        let suite = "PagePilotNearbySelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(firstID.uppercased(), forKey: "pagepilot_nearby_associated_target")

        // Upgraded users keep page turns working with their previously paired iPad.
        let migrated = PagePilotNearbySelectionStore.selectedTarget(defaults: defaults)
        XCTAssertEqual(migrated, PagePilotNearbyTarget(id: firstID, name: "iPad", bookTitle: ""))
        XCTAssertNil(defaults.object(forKey: "pagepilot_nearby_associated_target"))

        let target = PagePilotNearbyTarget(id: secondID, name: "Living Room iPad", bookTitle: "Dune")
        PagePilotNearbySelectionStore.remember(target, defaults: defaults)
        XCTAssertEqual(PagePilotNearbySelectionStore.selectedTarget(defaults: defaults), target)
    }

    func testInvalidLegacyLANAssociationIsNotMigrated() throws {
        let suite = "PagePilotNearbySelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-a-uuid", forKey: "pagepilot_nearby_associated_target")
        XCTAssertNil(PagePilotNearbySelectionStore.selectedTarget(defaults: defaults))
    }

    func testIPadRelayEntitlementStartsAndStopsHostLifecycle() {
        XCTAssertEqual(PagePilotRelayEntitlementLifecyclePolicy.action(isIPad: true, hasProAccess: true), .start)
        XCTAssertEqual(PagePilotRelayEntitlementLifecyclePolicy.action(isIPad: true, hasProAccess: false), .stop)
        XCTAssertEqual(PagePilotRelayEntitlementLifecyclePolicy.action(isIPad: false, hasProAccess: true), .noOp)
    }
}

/// Real Network.framework traffic between a host and a client in one process.
/// iOS only lets the app browse the service types in its Info.plist, so tests
/// use the production type with fresh identities that no running app shares.
final class PagePilotPeerLinkIntegrationTests: XCTestCase {
    private let serviceType = PagePilotPeerLinkConfiguration.serviceType
    private var firstID = ""
    private var secondID = ""
    private var missingID = ""
    private var hosts: [PagePilotPeerHost] = []

    override func setUp() {
        super.setUp()
        firstID = UUID().uuidString.lowercased()
        secondID = UUID().uuidString.lowercased()
        missingID = UUID().uuidString.lowercased()
    }

    override func tearDown() {
        hosts.forEach { $0.stop() }
        hosts.removeAll()
        super.tearDown()
    }

    /// Thread-safe tally of what a host's handler received.
    private final class Received: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [String] = []

        func append(_ action: String) {
            lock.lock(); actions.append(action); lock.unlock()
        }

        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return actions
        }
    }

    @discardableResult
    private func startHost(
        id: String,
        hasPro: Bool = true,
        received: Received = Received()
    ) -> (PagePilotPeerHost, Received) {
        let host = PagePilotPeerHost(serviceType: serviceType, localIdentifier: { id }, restartDelay: 0.2)
        host.start(
            advertisement: PagePilotPeerAdvertisement(name: "Test iPad \(id.prefix(4))", bookTitle: "Dune"),
            hasProAccess: { hasPro },
            handler: { request, reply in
                received.append(request.action?.rawValue ?? request.kind.rawValue)
                reply(["ok": true, "didTurnPage": request.kind == .command, "from": id])
            }
        )
        hosts.append(host)
        return (host, received)
    }

    private func makeClient(discoveryTimeout: TimeInterval = 5) -> PagePilotPeerClient {
        PagePilotPeerClient(serviceType: serviceType, discoveryTimeout: discoveryTimeout, requestTimeout: 5)
    }

    private func send(
        _ client: PagePilotPeerClient,
        to target: String,
        kind: PagePilotPeerRequestKind,
        action: PageCommand? = nil,
        timeout: TimeInterval = 10
    ) -> Result<[String: Any], PagePilotPeerError>? {
        let done = expectation(description: "response from \(target)")
        var outcome: Result<[String: Any], PagePilotPeerError>?
        client.send(to: target, kind: kind, action: action, commandID: UUID().uuidString) { result in
            outcome = result
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
        return outcome
    }

    func testListsAdvertisedIPadsWithNameAndBook() {
        startHost(id: firstID)
        startHost(id: secondID)
        let client = makeClient(discoveryTimeout: 3)

        let done = expectation(description: "discovery")
        var targets: [PagePilotNearbyTarget] = []
        client.discoverTargets { result in
            targets = (try? result.get()) ?? []
            done.fulfill()
        }
        wait(for: [done], timeout: 8)

        XCTAssertTrue(Set(targets.map(\.id)).isSuperset(of: [firstID, secondID]))
        XCTAssertEqual(targets.first { $0.id == firstID }?.bookTitle, "Dune")
    }

    func testPageTurnsReuseOneConnectionToTheSelectedIPad() throws {
        let (host, received) = startHost(id: firstID)
        let client = makeClient()

        for action in [PageCommand.next, .next, .prev] {
            let payload = try XCTUnwrap(send(client, to: firstID, kind: .command, action: action)).get()
            XCTAssertEqual(payload["didTurnPage"] as? Bool, true)
        }

        XCTAssertEqual(received.all, ["next", "next", "prev"])
        XCTAssertEqual(host.totalAcceptedConnections, 1)
    }

    func testOnlyTheSelectedIPadReceivesCommands() throws {
        let (_, firstReceived) = startHost(id: firstID)
        let (_, secondReceived) = startHost(id: secondID)
        let client = makeClient()

        let payload = try XCTUnwrap(send(client, to: secondID, kind: .command, action: .next)).get()
        _ = try XCTUnwrap(send(client, to: secondID, kind: .command, action: .next)).get()

        XCTAssertEqual(payload["from"] as? String, secondID)
        XCTAssertEqual(secondReceived.all, ["next", "next"])
        XCTAssertEqual(firstReceived.all, [])
    }

    func testMissingIPadFailsAsNotFound() {
        startHost(id: firstID)
        let client = makeClient(discoveryTimeout: 1.5)

        let result = send(client, to: missingID, kind: .status)

        XCTAssertEqual(result?.failureValue, .notFound)
    }

    func testHostWithoutProRejectsRequests() {
        let (_, received) = startHost(id: firstID, hasPro: false)
        let client = makeClient()

        let result = send(client, to: firstID, kind: .command, action: .next)

        XCTAssertEqual(result?.failureValue, .proRequired)
        XCTAssertEqual(received.all, [])
    }

    func testClientReconnectsAfterTheIPadRestarts() throws {
        let (host, received) = startHost(id: firstID)
        let client = makeClient()
        _ = try XCTUnwrap(send(client, to: firstID, kind: .status)).get()

        // Simulates the iPad app being relaunched: the old link dies.
        host.stop()
        let restarted = expectation(description: "host restarted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { restarted.fulfill() }
        wait(for: [restarted], timeout: 2)
        host.start(
            advertisement: PagePilotPeerAdvertisement(name: "Test iPad", bookTitle: ""),
            hasProAccess: { true },
            handler: { request, reply in
                received.append(request.action?.rawValue ?? request.kind.rawValue)
                reply(["ok": true, "didTurnPage": true])
            }
        )

        let payload = try XCTUnwrap(send(client, to: firstID, kind: .command, action: .next, timeout: 15)).get()

        XCTAssertEqual(payload["didTurnPage"] as? Bool, true)
        XCTAssertEqual(received.all, ["status", "next"])
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
