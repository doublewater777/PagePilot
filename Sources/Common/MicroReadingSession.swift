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
        localizedDuration(seconds: TimeInterval(minutes * 60))
    }

    static func localizedDuration(seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(max(1, Int(seconds / 60))) min"
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

/// Owns the active-time timer for a Micro Reading session. It deliberately
/// does not auto-dismiss the Reader when time is up: reaching the target is a
/// gentle checkpoint, not an interruption.
@MainActor
private final class MicroReadingSessionController: NSObject {
    private weak var viewController: UIViewController?
    private let session: MicroReadingSession
    private var remaining: TimeInterval
    private var activeStartedAt: Date?
    private var timer: Timer?
    private var isComplete = false

    init(session: MicroReadingSession, viewController: UIViewController) {
        self.session = session
        self.viewController = viewController
        remaining = session.duration
        super.init()
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        showStartCheckpoint()
        resumeTimerIfNeeded()
    }

    @objc private func appDidEnterBackground() {
        pauseTimer()
    }

    @objc private func appWillEnterForeground() {
        guard viewController?.view.window != nil else { return }
        resumeTimerIfNeeded()
    }

    private func resumeTimerIfNeeded() {
        guard !isComplete, remaining > 0, activeStartedAt == nil else { return }

        activeStartedAt = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.complete()
            }
        }
    }

    private func pauseTimer() {
        guard let activeStartedAt else { return }

        remaining = max(0, remaining - Date().timeIntervalSince(activeStartedAt))
        self.activeStartedAt = nil
        timer?.invalidate()
        timer = nil

        if remaining == 0 {
            complete()
        }
    }

    private func complete() {
        guard !isComplete else { return }

        if let activeStartedAt {
            remaining = max(0, remaining - Date().timeIntervalSince(activeStartedAt))
        }
        guard remaining <= 0.25 else {
            self.activeStartedAt = nil
            resumeTimerIfNeeded()
            return
        }

        isComplete = true
        remaining = 0
        self.activeStartedAt = nil
        timer?.invalidate()
        timer = nil

        guard let view = viewController?.view, view.window != nil else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let label = MicroReadingPolicy.localizedDuration(seconds: session.duration)
        toast("✓ \(label)", on: view, duration: 2)
    }

    private func showStartCheckpoint() {
        guard let view = viewController?.view else { return }
        let label = MicroReadingPolicy.localizedDuration(seconds: session.duration)
        toast("⏱︎ \(label)", on: view, duration: 1.5)
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
}
