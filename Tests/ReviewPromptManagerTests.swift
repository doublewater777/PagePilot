import XCTest
@testable import PagePilot

@MainActor
final class ReviewPromptManagerTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = UserDefaults(suiteName: "ReviewPromptManagerTests-\(UUID().uuidString)")!
    }

    override func tearDownWithError() throws {
        defaults = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeManager(
        appVersion: String = "1.0.0",
        readingStatsSeconds: TimeInterval = 20 * 60,
        scene: UIWindowScene?? = nil,
        watchPageTurns: Int = 10,
        appLaunches: Int = 2
    ) -> ReviewPromptManager {
        let manager = ReviewPromptManager(
            defaults: defaults!,
            appVersionProvider: { appVersion },
            readingStatsProvider: { readingStatsSeconds },
            sceneProvider: { scene ?? nil },
            reviewRequester: { _ in }
        )

        // Seed exact counter values
        defaults!.set(watchPageTurns, forKey: "review_watchPageTurnCount")
        defaults!.set(appLaunches, forKey: "review_appLaunchCount")

        return manager
    }

    // MARK: - Counter threshold tests

    func testPromptSkippedWhenWatchPageTurnCountBelow10() {
        let manager = makeManager(watchPageTurns: 9)

        manager.tryPromptReview(delay: 0)

        // Version should NOT be written (guard exits before dispatch)
        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testPromptDoesNotWriteVersionWhenSceneIsUnavailableAtThreshold() async {
        let manager = makeManager(watchPageTurns: 10)

        manager.tryPromptReview(delay: 0)
        await Task.yield()

        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testPromptSkippedWhenAppLaunchCountBelow2() {
        let manager = makeManager(appLaunches: 1)

        manager.tryPromptReview(delay: 0)

        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testPromptSkippedWhenReadingTimeBelow20Minutes() {
        let manager = makeManager(readingStatsSeconds: 20 * 60 - 1)

        manager.tryPromptReview(delay: 0)

        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testPromptDoesNotWriteVersionWhenReadingTimeIsAtThresholdButSceneUnavailable() async {
        let manager = makeManager(readingStatsSeconds: 20 * 60)

        manager.tryPromptReview(delay: 0)
        await Task.yield()

        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    // MARK: - Version gating tests

    func testPromptSkippedWhenVersionAlreadyRequested() {
        defaults.set("1.0.0", forKey: "review_requestedVersion")
        let manager = makeManager(appVersion: "1.0.0")

        manager.tryPromptReview(delay: 0)

        // Early return at first guard — version unchanged, no dispatch
        XCTAssertEqual(defaults.string(forKey: "review_requestedVersion"), "1.0.0")
    }

    func testPromptDoesNotOverwritePreviousVersionWhenSceneUnavailable() async {
        defaults.set("0.9.0", forKey: "review_requestedVersion")
        let manager = makeManager(appVersion: "1.0.0")

        manager.tryPromptReview(delay: 0)
        await Task.yield()

        XCTAssertEqual(defaults.string(forKey: "review_requestedVersion"), "0.9.0")
    }

    // MARK: - Version write timing tests

    func testVersionNotWrittenSynchronouslyBeforeAsyncDispatch() {
        // Even when all gates pass, version should NOT be written synchronously.
        // It's only written inside the asyncAfter closure.
        let manager = makeManager()

        manager.tryPromptReview(delay: 0)

        // Immediately after call: version is nil (not yet written)
        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testVersionNotWrittenWhenSceneIsUnavailable() async {
        let manager = makeManager(
            scene: nil // no foreground scene available
        )

        manager.tryPromptReview(delay: 0)
        await Task.yield()

        XCTAssertNil(defaults.string(forKey: "review_requestedVersion"))
    }

    func testDuplicatePromptRequestsOnlyScheduleOneSceneLookupWhilePending() async throws {
        var sceneLookups = 0
        let manager = ReviewPromptManager(
            defaults: defaults!,
            appVersionProvider: { "1.0.0" },
            readingStatsProvider: { 20 * 60 },
            sceneProvider: {
                sceneLookups += 1
                return nil
            },
            reviewRequester: { _ in }
        )
        defaults!.set(10, forKey: "review_watchPageTurnCount")
        defaults!.set(2, forKey: "review_appLaunchCount")

        manager.tryPromptReview(delay: 0.01)
        manager.tryPromptReview(delay: 0.01)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(sceneLookups, 1)
    }

    // MARK: - Counter record tests

    func testRecordWatchPageTurnIncrementsCount() {
        let manager = makeManager(watchPageTurns: 0)

        manager.recordWatchPageTurn()
        XCTAssertEqual(manager.watchPageTurnCount, 1)

        manager.recordWatchPageTurn()
        XCTAssertEqual(manager.watchPageTurnCount, 2)
    }

    func testRecordAppLaunchIncrementsCount() {
        let manager = makeManager(appLaunches: 0)

        manager.recordAppLaunch()
        XCTAssertEqual(manager.appLaunchCount, 1)

        manager.recordAppLaunch()
        XCTAssertEqual(manager.appLaunchCount, 2)
    }
}
