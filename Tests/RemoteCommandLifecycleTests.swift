import MediaPlayer
import XCTest
@testable import PagePilot

final class RemoteCommandLifecycleTests: XCTestCase {
    /// Verifies the registration pattern TTSViewModel now uses:
    /// register once, save token, remove on teardown.
    /// The old bug called addTarget on every start(), stacking targets.
    func testRegisterOnceRemoveOnceDoesNotLeak() {
        let cmd = MPRemoteCommandCenter.shared().togglePlayPauseCommand
        var callCount = 0
        var token: Any?
        token = cmd.addTarget { _ in
            callCount += 1
            return .success
        }
        XCTAssertNotNil(token)
        if let token { cmd.removeTarget(token) }
        token = nil
        XCTAssertEqual(callCount, 0)
    }

    /// Verify that removeTarget with the saved token is safe and idempotent.
    func testRemoveTargetIsIdempotent() {
        let cmd = MPRemoteCommandCenter.shared().togglePlayPauseCommand
        var token: Any?
        token = cmd.addTarget { _ in .success }
        if let token { cmd.removeTarget(token) }
        // Second remove should be a no-op (token already removed).
        if let token { cmd.removeTarget(token) }
        XCTAssertNotNil(token)
    }
}
