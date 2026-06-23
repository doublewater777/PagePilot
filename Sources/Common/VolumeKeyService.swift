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
        try? session.setActive(true)
        session.addObserver(self, forKeyPath: #keyPath(AVAudioSession.outputVolume), options: .new, context: nil)
        isObserving = true
        anchorVolume = session.outputVolume
    }

    private func teardown() {
        guard isObserving else { return }
        let session = AVAudioSession.sharedInstance()
        session.removeObserver(self, forKeyPath: #keyPath(AVAudioSession.outputVolume))
        try? session.setActive(false)
        volumeView?.removeFromSuperview()
        volumeView = nil
        volumeSlider = nil
        isObserving = false
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(AVAudioSession.outputVolume),
              let newVolume = change?[.newKey] as? Float,
              shouldIntercept() else { return }

        let delta = newVolume - anchorVolume
        guard abs(delta) > 0.05 else { anchorVolume = newVolume; return }

        let currentAnchor = anchorVolume
        let mapping = VolumeKeyService.currentVolumeKeyMapping
        DispatchQueue.main.async { [weak self] in
            let isForward: Bool
            switch mapping {
            case .downForwardUpBackward:
                isForward = delta < 0
            case .upForwardDownBackward:
                isForward = delta > 0
            }
            if isForward {
                self?.onPageForward?()
            } else {
                self?.onPageBackward?()
            }
            self?.volumeSlider?.setValue(currentAnchor, animated: false)
        }
    }

    static var currentVolumeKeyMapping: VolumeKeyMapping {
        UserDefaults.standard.string(forKey: Self.volumeKeyMappingKey)
            .flatMap(VolumeKeyMapping.init(rawValue:))
            ?? Self.defaultVolumeKeyMapping
    }

    private func shouldIntercept() -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.volumeKeyEnabledKey) else { return false }
        guard let provider = behaviorProvider,
              (provider as? UIViewController)?.view.window?.isKeyWindow == true else { return false }
        guard !AVAudioSession.sharedInstance().isOtherAudioPlaying else { return false }

        return provider.volumeKeyBehavior == .turnPage
    }
}
