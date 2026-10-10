import AVFoundation
import MediaPlayer
import UIKit

enum VolumeKeyBehavior {
    case turnPage
    case controlVolume
}

enum VolumeKeyMapping: String, CaseIterable, Identifiable {
    case downForwardUpBackward = "down_forward_up_backward"
    case upForwardDownBackward = "up_forward_down_backward"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .downForwardUpBackward:
            return NSLocalizedString("settings_volume_key_down_forward", comment: "")
        case .upForwardDownBackward:
            return NSLocalizedString("settings_volume_key_up_forward", comment: "")
        }
    }
}

protocol VolumeKeyBehaviorProvider: AnyObject {
    var volumeKeyBehavior: VolumeKeyBehavior { get }
}

final class VolumeKeyService: NSObject {
    static let shared = VolumeKeyService()

    weak var behaviorProvider: VolumeKeyBehaviorProvider?
    var onPageForward: (() -> Void)?
    var onPageBackward: (() -> Void)?

    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var anchorVolume: Float = 0.5
    private var isObserving = false
    private var audioSessionGeneration = 0

    static let volumeKeyEnabledKey = "volume_key_turn_page"
    static let volumeKeyMappingKey = "volume_key_mapping"
    static let defaultVolumeKeyMapping: VolumeKeyMapping = .downForwardUpBackward

    private override init() {
        super.init()
    }

    func register(_ provider: VolumeKeyBehaviorProvider) {
        behaviorProvider = provider
        setupIfNeeded()
    }

    func unregister(_ provider: VolumeKeyBehaviorProvider) {
        guard behaviorProvider === provider else { return }
        behaviorProvider = nil
        onPageForward = nil
        onPageBackward = nil
        teardown()
    }

    private func setupIfNeeded() {
        guard !isObserving else { return }

        let vv = MPVolumeView(frame: .zero)
        vv.alpha = 0.001
        vv.isHidden = false
        volumeView = vv
        volumeSlider = vv.subviews.first(where: { $0 is UISlider }) as? UISlider

        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .first(where: { $0.isKeyWindow }) {
            window.addSubview(vv)
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
        session.addObserver(self, forKeyPath: #keyPath(AVAudioSession.outputVolume), options: .new, context: nil)
        isObserving = true
        anchorVolume = session.outputVolume
        activateAudioSession(session)
    }

    private func teardown() {
        guard isObserving else { return }
        let session = AVAudioSession.sharedInstance()
        session.removeObserver(self, forKeyPath: #keyPath(AVAudioSession.outputVolume))
        deactivateAudioSession(session)
        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
        isObserving = false
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(AVAudioSession.outputVolume),
              let newVolume = change?[.newKey] as? Float else { return }

        guard VolumeKeyDecisionPolicy.shouldIntercept(currentState()) else { return }

        let delta = newVolume - anchorVolume
        guard abs(delta) > 0.05 else { anchorVolume = newVolume; return }

        let action = VolumeKeyDecisionPolicy.direction(for: delta, mapping: Self.currentVolumeKeyMapping)
        let currentAnchor = anchorVolume
        DispatchQueue.main.async { [weak self] in
            switch action {
            case .forward:
                self?.onPageForward?()
            case .backward:
                self?.onPageBackward?()
            }
            self?.volumeSlider?.setValue(currentAnchor, animated: false)
        }
    }

    /// Captures the live gate inputs for `VolumeKeyDecisionPolicy` from
    /// UserDefaults, the audio session, and the registered provider's window.
    private func currentState() -> VolumeKeyState {
        let provider = behaviorProvider
        return VolumeKeyState(
            isEnabled: UserDefaults.standard.bool(forKey: Self.volumeKeyEnabledKey),
            isKeyWindow: (provider as? UIViewController)?.view.window?.isKeyWindow == true,
            isOtherAudioPlaying: AVAudioSession.sharedInstance().isOtherAudioPlaying,
            providerBehavior: provider?.volumeKeyBehavior ?? .controlVolume
        )
    }

    /// iOS 27 treats synchronous `setActive` on the main thread as a hang risk.
    /// A later `register` can overlap an in-flight `deactivate`, so the completion
    /// re-activates only when this service is still observing a newer session.
    private func activateAudioSession(_ session: AVAudioSession) {
        audioSessionGeneration += 1
        let generation = audioSessionGeneration
        if #available(iOS 27.0, *) {
            session.activate(options: []) { [weak self] _, _ in
                let volume = session.outputVolume
                DispatchQueue.main.async {
                    guard let self, self.audioSessionGeneration == generation else { return }
                    self.anchorVolume = volume
                }
            }
        } else {
            try? session.setActive(true)
            anchorVolume = session.outputVolume
        }
    }

    private func deactivateAudioSession(_ session: AVAudioSession) {
        let generation = audioSessionGeneration
        if #available(iOS 27.0, *) {
            session.deactivate(options: []) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, self.isObserving, self.audioSessionGeneration != generation else { return }
                    self.activateAudioSession(session)
                }
            }
        } else {
            try? session.setActive(false)
        }
    }

    static var currentVolumeKeyMapping: VolumeKeyMapping {
        UserDefaults.standard.string(forKey: Self.volumeKeyMappingKey)
            .flatMap(VolumeKeyMapping.init(rawValue:))
            ?? Self.defaultVolumeKeyMapping
    }

}
