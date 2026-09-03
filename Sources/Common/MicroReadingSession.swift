import Foundation
import ObjectiveC
import UIKit

/// A lightweight, time-boxed reading intention started from Home.
struct MicroReadingSession: Equatable {
    let bookId: Book.Id
    let duration: TimeInterval
}

enum MicroReadingPolicy {
    static let supportedMinutes = [3, 5, 10]

    static func duration(forMinutes minutes: Int) -> TimeInterval? {
        guard supportedMinutes.contains(minutes) else { return nil }
        return TimeInterval(minutes * 60)
    }

    static func localizedDuration(forMinutes minutes: Int) -> String {
        String(
            format: NSLocalizedString("micro_reading_minutes_format", comment: ""),
            minutes
        )
    }

    static func localizedDuration(seconds: TimeInterval) -> String {
        localizedDuration(forMinutes: max(1, Int(seconds / 60)))
    }

    static func countdownText(remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(remaining)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct MicroReadingCountdown {
    private(set) var remainingDuration: TimeInterval
    private var activeStartedAt: Date?

    init(duration: TimeInterval) {
        remainingDuration = duration
    }

    mutating func resume(at date: Date = Date()) {
        guard remainingDuration > 0, activeStartedAt == nil else { return }
        activeStartedAt = date
    }

    mutating func pause(at date: Date = Date()) {
        remainingDuration = remaining(at: date)
        activeStartedAt = nil
    }

    func remaining(at date: Date = Date()) -> TimeInterval {
        guard let activeStartedAt else { return remainingDuration }
        return max(0, remainingDuration - date.timeIntervalSince(activeStartedAt))
    }

    func isComplete(at date: Date = Date()) -> Bool {
        remaining(at: date) <= 0
    }
}

/// Bridges a Home quick-read tap to the next Reader created for that book.
/// Keeping this transient avoids adding persistence or schema changes for a
/// session that is only meaningful while the Reader is being opened.
@MainActor
enum MicroReadingLaunchStore {
    private struct Pending {
        let session: MicroReadingSession
        let createdAt: Date
    }

    private static var pending: Pending?
    private static let maximumLaunchDelay: TimeInterval = 60

    static func prepare(bookId: Book.Id, minutes: Int, now: Date = Date()) {
        guard let duration = MicroReadingPolicy.duration(forMinutes: minutes) else { return }
        pending = Pending(
            session: MicroReadingSession(bookId: bookId, duration: duration),
            createdAt: now
        )
    }

    static func consume(for bookId: Book.Id, now: Date = Date()) -> MicroReadingSession? {
        guard let pending else { return nil }

        if now.timeIntervalSince(pending.createdAt) > maximumLaunchDelay {
            self.pending = nil
            return nil
        }

        guard pending.session.bookId == bookId else { return nil }
        self.pending = nil
        return pending.session
    }

    static func clear() {
        pending = nil
    }
}

@MainActor
private var microReadingControllerAssociationKey: UInt8 = 0

@MainActor
protocol ReaderPositionIndicatorProviding: AnyObject {
    var positionIndicatorView: UIView { get }
}

private final class MicroReadingStatusView: UILabel {
    init() {
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityIdentifier = "microReadingCountdown"
        font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        textColor = .secondaryLabel
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(remaining: TimeInterval) {
        let time = MicroReadingPolicy.countdownText(remaining: remaining)
        text = "· \(time)"
        accessibilityLabel = String(
            format: NSLocalizedString("micro_reading_badge_format", comment: ""),
            time
        )
    }
}

/// Owns the active-time timer for a Micro Reading session. It deliberately
/// does not auto-dismiss the Reader when time is up: reaching the target is a
/// gentle checkpoint, not an interruption.
@MainActor
private final class MicroReadingSessionController: NSObject {
    private weak var viewController: UIViewController?
    private let session: MicroReadingSession
    private var countdown: MicroReadingCountdown
    private var timer: Timer?
    private var statusView: MicroReadingStatusView?
    private var isReaderVisible = false
    private var isComplete = false

    init(session: MicroReadingSession, viewController: UIViewController) {
        self.session = session
        self.viewController = viewController
        countdown = MicroReadingCountdown(duration: session.duration)
        super.init()
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        installStatusView()
        isReaderVisible = viewController?.view.window != nil
        resumeTimerIfNeeded()
    }

    func readerDidAppear() {
        isReaderVisible = true
        resumeTimerIfNeeded()
    }

    func readerWillDisappear() {
        isReaderVisible = false
        pauseTimer()
    }

    @objc private func appWillResignActive() {
        pauseTimer()
    }

    @objc private func appDidBecomeActive() {
        resumeTimerIfNeeded()
    }

    @objc private func timerDidFire() {
        let now = Date()
        let remaining = countdown.remaining(at: now)
        statusView?.update(remaining: remaining)
        if countdown.isComplete(at: now) {
            complete(at: now)
        }
    }

    private func resumeTimerIfNeeded() {
        guard !isComplete,
              isReaderVisible,
              UIApplication.shared.applicationState == .active,
              countdown.remainingDuration > 0,
              timer == nil else { return }

        countdown.resume()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerDidFire()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        timerDidFire()
    }

    private func pauseTimer() {
        countdown.pause()
        timer?.invalidate()
        timer = nil
        statusView?.update(remaining: countdown.remainingDuration)
    }

    private func complete(at date: Date) {
        guard !isComplete else { return }

        countdown.pause(at: date)
        isComplete = true
        timer?.invalidate()
        timer = nil
        removeStatusView()

        guard let view = viewController?.view, view.window != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let label = MicroReadingPolicy.localizedDuration(seconds: session.duration)
        let message = String(
            format: NSLocalizedString("micro_reading_complete_format", comment: ""),
            label
        )
        toast(message, on: view, duration: 2.5)
    }

    private func installStatusView() {
        guard let view = viewController?.view else { return }
        let statusView = MicroReadingStatusView()
        statusView.update(remaining: countdown.remainingDuration)
        statusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusView)
        if let provider = viewController as? ReaderPositionIndicatorProviding {
            NSLayoutConstraint.activate([
                statusView.leadingAnchor.constraint(
                    equalTo: provider.positionIndicatorView.trailingAnchor,
                    constant: 4
                ),
                statusView.centerYAnchor.constraint(equalTo: provider.positionIndicatorView.centerYAnchor),
                statusView.trailingAnchor.constraint(
                    lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                    constant: -16
                ),
            ])
        } else {
            NSLayoutConstraint.activate([
                statusView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
                statusView.bottomAnchor.constraint(
                    equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                    constant: -QuickPositionJumpPolicy.positionIndicatorBottomSpacing
                ),
            ])
        }

        self.statusView = statusView
    }

    private func removeStatusView() {
        statusView?.removeFromSuperview()
        statusView = nil
    }
}

@MainActor
enum MicroReadingSessionPresenter {
    static func attach(_ session: MicroReadingSession, to viewController: UIViewController) {
        let controller = MicroReadingSessionController(
            session: session,
            viewController: viewController
        )
        objc_setAssociatedObject(
            viewController,
            &microReadingControllerAssociationKey,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        controller.start()
    }

    static func readerDidAppear(_ viewController: UIViewController) {
        controller(for: viewController)?.readerDidAppear()
    }

    static func readerWillDisappear(_ viewController: UIViewController) {
        controller(for: viewController)?.readerWillDisappear()
    }

    private static func controller(for viewController: UIViewController) -> MicroReadingSessionController? {
        objc_getAssociatedObject(
            viewController,
            &microReadingControllerAssociationKey
        ) as? MicroReadingSessionController
    }
}
