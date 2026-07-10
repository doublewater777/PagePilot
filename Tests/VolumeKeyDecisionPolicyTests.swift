import XCTest
@testable import PagePilot

final class VolumeKeyDecisionPolicyTests: XCTestCase {

    // MARK: - shouldIntercept (the precedence chain)

    private func state(
        enabled: Bool = true,
        keyWindow: Bool = true,
        otherAudio: Bool = false,
        behavior: VolumeKeyBehavior = .turnPage
    ) -> VolumeKeyState {
        VolumeKeyState(
            isEnabled: enabled,
            isKeyWindow: keyWindow,
            isOtherAudioPlaying: otherAudio,
            providerBehavior: behavior
        )
    }

    func testInterceptsWhenAllGatesPass() {
        XCTAssertTrue(VolumeKeyDecisionPolicy.shouldIntercept(state()))
    }

    func testDisabledFlagBlocksInterception() {
        XCTAssertFalse(VolumeKeyDecisionPolicy.shouldIntercept(state(enabled: false)))
    }

    func testNotKeyWindowBlocksInterception() {
        XCTAssertFalse(VolumeKeyDecisionPolicy.shouldIntercept(state(keyWindow: false)))
    }

    func testOtherAudioPlayingBlocksInterception() {
        XCTAssertFalse(VolumeKeyDecisionPolicy.shouldIntercept(state(otherAudio: true)))
    }

    func testTTSPlayingBlocksInterception() {
        // The reader declares .controlVolume while TTS is speaking.
        XCTAssertFalse(VolumeKeyDecisionPolicy.shouldIntercept(state(behavior: .controlVolume)))
    }

    func testDisabledTakesPrecedenceOverTTS() {
        // enabled is the first gate; it short-circuits regardless of behavior.
        XCTAssertFalse(VolumeKeyDecisionPolicy.shouldIntercept(state(enabled: false, behavior: .controlVolume)))
    }

    // MARK: - direction

    func testDownForwardMappingVolumeDownIsForward() {
        XCTAssertEqual(
            VolumeKeyDecisionPolicy.direction(for: -0.2, mapping: .downForwardUpBackward),
            .forward
        )
    }

    func testDownForwardMappingVolumeUpIsBackward() {
        XCTAssertEqual(
            VolumeKeyDecisionPolicy.direction(for: 0.2, mapping: .downForwardUpBackward),
            .backward
        )
    }

    func testUpForwardMappingVolumeUpIsForward() {
        XCTAssertEqual(
            VolumeKeyDecisionPolicy.direction(for: 0.2, mapping: .upForwardDownBackward),
            .forward
        )
    }

    func testUpForwardMappingVolumeDownIsBackward() {
        XCTAssertEqual(
            VolumeKeyDecisionPolicy.direction(for: -0.2, mapping: .upForwardDownBackward),
            .backward
        )
    }
}
