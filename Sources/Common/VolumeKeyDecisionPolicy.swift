import Foundation

/// A snapshot of the conditions that gate Volume Key Page Turn interception.
///
/// Captured by `VolumeKeyService` from UserDefaults, the audio session, and the
/// registered provider's window, then handed to `VolumeKeyDecisionPolicy` so the
/// policy stays a pure function of state.
struct VolumeKeyState {
    let isEnabled: Bool
    let isKeyWindow: Bool
    let isOtherAudioPlaying: Bool
    let providerBehavior: VolumeKeyBehavior
}

/// The page action a volume-button press maps to.
enum VolumeKeyAction {
    case forward
    case backward
}

/// Pure decision logic for Volume Key Page Turn.
///
/// Concentrates the full interception precedence - the enabled flag, the
/// frontmost-window guard, the other-audio guard, and the reader's declared
/// intent (the TTS gate, supplied via `volumeKeyBehavior`) - into one function,
/// alongside the direction mapping. `VolumeKeyService` gathers `VolumeKeyState`
/// and executes the result; the dead-zone / volume-anchor plumbing stays in the
/// service, since it is signal processing rather than a page-turn decision.
enum VolumeKeyDecisionPolicy {
    /// True when every gate in the precedence chain allows interception:
    /// enabled -> frontmost window -> no other audio -> reader wants `.turnPage`.
    static func shouldIntercept(_ state: VolumeKeyState) -> Bool {
        guard state.isEnabled else { return false }
        guard state.isKeyWindow else { return false }
        guard !state.isOtherAudioPlaying else { return false }
        return state.providerBehavior == .turnPage
    }

    /// Maps a volume delta to a page action according to the user's mapping.
    static func direction(for volumeDelta: Float, mapping: VolumeKeyMapping) -> VolumeKeyAction {
        switch mapping {
        case .downForwardUpBackward:
            return volumeDelta < 0 ? .forward : .backward
        case .upForwardDownBackward:
            return volumeDelta > 0 ? .forward : .backward
        }
    }
}
