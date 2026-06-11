import StoreKit
import UIKit

@MainActor
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    private enum Keys {
        static let watchPageTurnCount = "review_watchPageTurnCount"
        static let appLaunchCount = "review_appLaunchCount"
        static let reviewRequestedVersion = "review_requestedVersion"
    }

    private let defaults: UserDefaults
    private let appVersionProvider: () -> String
    private let readingStatsProvider: () -> TimeInterval
    private let sceneProvider: () -> UIWindowScene?
    private let reviewRequester: (UIWindowScene) -> Void
    private var pendingReviewVersion: String?

    init(
        defaults: UserDefaults = .standard,
        appVersionProvider: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        },
        readingStatsProvider: @escaping () -> TimeInterval = {
            TimeInterval(ReadingStatsStore.shared.snapshot(for: .summary).totalSeconds)
        },
        sceneProvider: @escaping () -> UIWindowScene? = {
            UIApplication.shared.connectedScenes.first(
                where: { $0.activationState == .foregroundActive }
            ) as? UIWindowScene
        },
        reviewRequester: @escaping (UIWindowScene) -> Void = {
            SKStoreReviewController.requestReview(in: $0)
        }
    ) {
        self.defaults = defaults
        self.appVersionProvider = appVersionProvider
        self.readingStatsProvider = readingStatsProvider
        self.sceneProvider = sceneProvider
        self.reviewRequester = reviewRequester
    }

    var watchPageTurnCount: Int {
        defaults.integer(forKey: Keys.watchPageTurnCount)
    }

    var appLaunchCount: Int {
        defaults.integer(forKey: Keys.appLaunchCount)
    }

    func recordWatchPageTurn() {
        defaults.set(watchPageTurnCount + 1, forKey: Keys.watchPageTurnCount)
    }

    func recordAppLaunch() {
        defaults.set(appLaunchCount + 1, forKey: Keys.appLaunchCount)
    }

    func tryPromptReview(delay: TimeInterval = 1.0) {
        let currentVersion = appVersionProvider()
        guard !currentVersion.isEmpty else { return }

        if defaults.string(forKey: Keys.reviewRequestedVersion) == currentVersion {
            return
        }

        if pendingReviewVersion == currentVersion {
            return
        }

        guard watchPageTurnCount >= 10 else { return }

        let totalSeconds = readingStatsProvider()
        guard totalSeconds >= 20 * 60 else { return }

        guard appLaunchCount >= 2 else { return }

        pendingReviewVersion = currentVersion

        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard let self else { return }
            defer { pendingReviewVersion = nil }

            guard UIApplication.shared.applicationState == .active,
                  let scene = sceneProvider()
            else { return }

            defaults.set(currentVersion, forKey: Keys.reviewRequestedVersion)
            reviewRequester(scene)
        }
    }
}
