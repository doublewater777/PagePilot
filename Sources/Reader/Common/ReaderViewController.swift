//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumNavigator
import ReadiumShared
import SafariServices
import SwiftUI
import UIKit

struct ReaderSessionLifecycle {
    struct ActiveSession {
        let bookId: Book.Id
        let startedAt: Date
        let startProgression: Double
        var watchPageTurns: Int = 0
    }

    struct FinishedSession {
        let bookId: Book.Id
        let startedAt: Date
        let endedAt: Date
        let startProgression: Double
        let watchPageTurns: Int
    }

    private let bookId: Book.Id
    private(set) var isReaderVisible = false
    private var activeSession: ActiveSession?

    init(bookId: Book.Id) {
        self.bookId = bookId
    }

    mutating func readerDidAppear(
        at startedAt: Date,
        progression: Double,
        applicationIsActive: Bool
    ) -> ActiveSession? {
        isReaderVisible = true
        return startIfNeeded(
            at: startedAt,
            progression: progression,
            applicationIsActive: applicationIsActive
        )
    }

    mutating func readerWillDisappear(at endedAt: Date) -> FinishedSession? {
        isReaderVisible = false
        return finishIfNeeded(at: endedAt)
    }

    mutating func applicationDidEnterBackground(at endedAt: Date) -> FinishedSession? {
        finishIfNeeded(at: endedAt)
    }

    mutating func applicationDidBecomeActive(
        at startedAt: Date,
        progression: Double
    ) -> ActiveSession? {
        startIfNeeded(
            at: startedAt,
            progression: progression,
            applicationIsActive: true
        )
    }

    mutating func recordSuccessfulWatchPageTurn(origin: WatchPageTurnOrigin) {
        guard var session = activeSession else { return }
        session.watchPageTurns += 1
        activeSession = session
    }

    private mutating func startIfNeeded(
        at startedAt: Date,
        progression: Double,
        applicationIsActive: Bool
    ) -> ActiveSession? {
        guard isReaderVisible,
              applicationIsActive,
              activeSession == nil else {
            return nil
        }

        let session = ActiveSession(
            bookId: bookId,
            startedAt: startedAt,
            startProgression: progression
        )
        activeSession = session
        return session
    }

    private mutating func finishIfNeeded(at endedAt: Date) -> FinishedSession? {
        guard let session = activeSession else { return nil }
        activeSession = nil

        return FinishedSession(
            bookId: session.bookId,
            startedAt: session.startedAt,
            endedAt: endedAt,
            startProgression: session.startProgression,
            watchPageTurns: session.watchPageTurns
        )
    }
}


struct ReadingSessionSummary: Equatable {
    enum DailyGoalFeedback: Equatable {
        case remaining(minutes: Int)
        case complete
    }

    let durationSeconds: Int
    let startProgression: Double
    let endProgression: Double
    let progressDelta: Double
    let watchPageTurns: Int
    let dailyGoalFeedback: DailyGoalFeedback?
}

enum ReadingSessionSummaryPolicy {
    static let minimumDurationSeconds = 2 * 60
    static let minimumForwardProgress = 0.01
    static let minimumWatchPageTurns = 5
    private static let progressComparisonTolerance = 1e-9

    static func makeSummary(
        for session: ReadingSession,
        todaySeconds: Int,
        goalMinutes: Int,
        suppressGoalCompletion: Bool
    ) -> ReadingSessionSummary? {
        let isMeaningful =
            session.durationSeconds >= minimumDurationSeconds
            || session.progressDelta >= minimumForwardProgress - progressComparisonTolerance
            || session.watchPageTurns >= minimumWatchPageTurns

        guard isMeaningful else { return nil }

        let dailyGoalFeedback: ReadingSessionSummary.DailyGoalFeedback?
        if goalMinutes <= 0 {
            dailyGoalFeedback = nil
        } else {
            let goalSeconds = goalMinutes * 60
            if todaySeconds >= goalSeconds {
                dailyGoalFeedback = suppressGoalCompletion ? nil : .complete
            } else {
                let remainingSeconds = max(0, goalSeconds - todaySeconds)
                let remainingMinutes = max(1, (remainingSeconds + 59) / 60)
                dailyGoalFeedback = .remaining(minutes: remainingMinutes)
            }
        }

        return ReadingSessionSummary(
            durationSeconds: session.durationSeconds,
            startProgression: session.startProgression,
            endProgression: session.endProgression,
            progressDelta: session.progressDelta,
            watchPageTurns: session.watchPageTurns,
            dailyGoalFeedback: dailyGoalFeedback
        )
    }
}

final class ReadingSessionSummaryViewController: UIViewController {
    static let maximumContentWidth: CGFloat = 480

    let summary: ReadingSessionSummary
    private(set) var contentStack = UIStackView()
    private(set) var dismissButton = UIButton(type: .system)

    init(summary: ReadingSessionSummary) {
        self.summary = summary
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        isModalInPresentation = false
        preferredContentSize = CGSize(width: Self.maximumContentWidth, height: 360)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        view.accessibilityViewIsModal = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.accessibilityIdentifier = "readingSessionSummary.content"
        scrollView.addSubview(contentStack)

        let titleLabel = makeLabel(
            text: NSLocalizedString("reader_session_summary_title", comment: ""),
            textStyle: .title2
        )
        titleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: UIFont.systemFont(ofSize: 22, weight: .semibold))
        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.accessibilityIdentifier = "readingSessionSummary.title"
        contentStack.addArrangedSubview(titleLabel)

        let durationLabel = makeLabel(
            text: Self.durationText(seconds: summary.durationSeconds),
            textStyle: .title1
        )
        durationLabel.accessibilityIdentifier = "readingSessionSummary.duration"
        contentStack.addArrangedSubview(durationLabel)

        let progressLabel = makeLabel(
            text: progressText(),
            textStyle: .body
        )
        progressLabel.accessibilityIdentifier = "readingSessionSummary.progress"
        contentStack.addArrangedSubview(progressLabel)

        if summary.watchPageTurns > 0 {
            let format = NSLocalizedString("reader_session_summary_watch_turns_format", comment: "")
            let watchLabel = makeLabel(
                text: String(format: format, summary.watchPageTurns),
                textStyle: .body
            )
            watchLabel.accessibilityIdentifier = "readingSessionSummary.watchTurns"
            contentStack.addArrangedSubview(watchLabel)
        }

        if let dailyGoalFeedback = summary.dailyGoalFeedback {
            let goalText: String
            switch dailyGoalFeedback {
            case let .remaining(minutes):
                goalText = String(
                    format: NSLocalizedString("stats_goal_remaining_message", comment: ""),
                    minutes
                )
            case .complete:
                goalText = NSLocalizedString("stats_goal_complete_message", comment: "")
            }

            let goalLabel = makeLabel(text: goalText, textStyle: .subheadline)
            goalLabel.accessibilityIdentifier = "readingSessionSummary.dailyGoal"
            contentStack.addArrangedSubview(goalLabel)
        }

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = NSLocalizedString("reader_session_summary_done", comment: "")
        buttonConfiguration.buttonSize = .large
        dismissButton.configuration = buttonConfiguration
        dismissButton.addTarget(self, action: #selector(dismissSummary), for: .touchUpInside)
        dismissButton.accessibilityIdentifier = "readingSessionSummary.dismiss"
        contentStack.addArrangedSubview(dismissButton)

        let safeArea = view.safeAreaLayoutGuide
        let fillWidth = contentStack.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -48
        )
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumContentWidth),
            fillWidth,
        ])
    }

    private func makeLabel(text: String, textStyle: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: textStyle)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .label
        return label
    }

    private func progressText() -> String {
        let start = Self.percentText(summary.startProgression)
        let end = Self.percentText(summary.endProgression)

        guard summary.progressDelta > 0 else {
            return "\(start) → \(end)"
        }

        let delta = Self.percentText(summary.progressDelta)
        return String(
            format: NSLocalizedString("reader_session_summary_progress_format", comment: ""),
            start,
            end,
            delta
        )
    }

    private static func durationText(seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds >= 3600
            ? [.hour, .minute]
            : (seconds >= 60 ? [.minute] : [.second])

        return formatter.string(from: TimeInterval(max(0, seconds)))
            ?? "\(max(0, seconds))s"
    }

    private static func percentText(_ progression: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0

        return formatter.string(from: NSNumber(value: progression))
            ?? "\(Int((progression * 100).rounded()))%"
    }

    @objc private func dismissSummary() {
        dismiss(animated: true)
    }
}

enum ReadingSessionSummaryPresenter {
    static func present(_ summary: ReadingSessionSummary, after reader: UIViewController) {
        guard let navigationController = reader.navigationController else { return }

        let presentationBlock: () -> Void = { [weak navigationController, weak reader] in
            guard let navigationController,
                  let reader,
                  let host = navigationController.topViewController,
                  host !== reader,
                  host.presentedViewController == nil else {
                return
            }

            let summaryViewController = ReadingSessionSummaryViewController(summary: summary)
            if let sheet = summaryViewController.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
            }
            host.present(summaryViewController, animated: true)
        }

        if let transitionCoordinator = reader.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { context in
                guard !context.isCancelled else { return }
                DispatchQueue.main.async(execute: presentationBlock)
            }
        } else {
            DispatchQueue.main.async(execute: presentationBlock)
        }
    }
}

/// Base class for all reader view controllers.
class ReaderViewController<N: Navigator>: UIViewController,
    NavigatorDelegate, UIPopoverPresentationControllerDelegate, Loggable
{
    weak var moduleDelegate: ReaderFormatModuleDelegate?

    let navigator: N
    let publication: Publication
    let bookId: Book.Id
    private let books: BookRepository
    private let bookmarks: BookmarkRepository
    private var readingSessionLifecycle: ReaderSessionLifecycle

    var supportsDetailedReadingSessions: Bool { false }
    private var suppressedReadingProgress: Locator?
    private(set) var isReadingProgressPersistenceSuppressed = false

    var subscriptions = Set<AnyCancellable>()

    private(set) var searchViewModel: SearchViewModel?
    private var searchViewController: UIHostingController<SearchView>?

    init(
        navigator: N,
        publication: Publication,
        bookId: Book.Id,
        books: BookRepository,
        bookmarks: BookmarkRepository
    ) {
        self.navigator = navigator
        self.publication = publication
        self.bookId = bookId
        self.books = books
        self.bookmarks = bookmarks
        self.readingSessionLifecycle = ReaderSessionLifecycle(bookId: bookId)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(watchPageTurnDidSucceed(_:)), name: .watchPageTurnDidSucceed, object: nil)

        LastReadBooks.record(id: bookId.rawValue)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        setMainTabBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginReadingSession(
            readingSessionLifecycle.readerDidAppear(
                at: Date(),
                progression: currentReadingProgression,
                applicationIsActive: UIApplication.shared.applicationState == .active
            )
        )
        MicroReadingSessionPresenter.readerDidAppear(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        let isReaderExit =
            isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true

        MicroReadingSessionPresenter.readerWillDisappear(self)
        finishReadingSession(
            readingSessionLifecycle.readerWillDisappear(at: Date()),
            isVisibleReaderExit: isReaderExit
        )
        setMainTabBarHidden(false, animated: animated)
        if isReaderExit,
           UIApplication.shared.applicationState == .active {
            ReviewPromptManager.shared.tryPromptReview()
        }
    }

    private func setMainTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard let tabBarController else { return }

        if #available(iOS 18.0, *) {
            tabBarController.setTabBarHidden(hidden, animated: animated)
        } else {
            tabBarController.tabBar.isHidden = hidden
        }
    }

    private var currentReadingProgression: Double {
        navigator.currentLocation?.locations.totalProgression
            ?? WatchPageTurnService.shared.currentBookProgress
    }

    private func beginReadingSession(_ session: ReaderSessionLifecycle.ActiveSession?) {
        guard let session else { return }

        WatchReadingSessionContext.begin(
            at: session.startedAt,
            progression: session.startProgression
        )
    }

    private func finishReadingSession(
        _ finishedSession: ReaderSessionLifecycle.FinishedSession?,
        isVisibleReaderExit: Bool
    ) {
        guard let finishedSession else { return }

        WatchReadingSessionContext.end()

        ReadingStatsStore.shared.recordReadingSession(
            startDate: finishedSession.startedAt,
            endDate: finishedSession.endedAt,
            bookId: finishedSession.bookId
        )

        var detailedSession: ReadingSession?
        if supportsDetailedReadingSessions {
            let endProgression = navigator.currentLocation?.locations.totalProgression
                ?? finishedSession.startProgression
            let session = ReadingSession(
                bookId: finishedSession.bookId,
                startedAt: finishedSession.startedAt,
                endedAt: finishedSession.endedAt,
                startProgression: finishedSession.startProgression,
                endProgression: endProgression,
                watchPageTurns: finishedSession.watchPageTurns
            )
            detailedSession = session

            if session.durationSeconds > 0 {
                Task {
                    do {
                        try await AppModule.shared?.readingSessions.add(session)
                    } catch {
                        print("ReaderViewController: failed to save reading session: \(error)")
                    }
                }
            }
        }

        let todaySeconds = ReadingStatsStore.shared.todayReadingSeconds()
        let goalMinutes = ReadingPreferences.dailyGoalMinutes
        let goalReached = ReadingGoalPolicy.goalReached(
            todaySeconds: todaySeconds,
            goalMinutes: goalMinutes
        )
        let shouldCelebrateGoal =
            isVisibleReaderExit
            && goalReached
            && !ReadingGoalCelebration.alreadyCelebratedToday()

        let summary: ReadingSessionSummary?
        if isVisibleReaderExit, let detailedSession {
            summary = ReadingSessionSummaryPolicy.makeSummary(
                for: detailedSession,
                todaySeconds: todaySeconds,
                goalMinutes: goalMinutes,
                suppressGoalCompletion: shouldCelebrateGoal
            )
        } else {
            summary = nil
        }

        if shouldCelebrateGoal {
            ReadingGoalCelebration.markCelebratedToday()
            toast(NSLocalizedString("reader_goal_reached", comment: ""), on: view, duration: 2)
        }

        if let summary {
            ReaderSessionSummaryPresenter.present(summary, after: self)
        }
    }

    @objc private func appDidEnterBackground() {
        // Backgrounding ends the active interval without changing visibility,
        // so didBecomeActive can start a fresh interval only if this Reader
        // is still on screen.
        finishReadingSession(
            readingSessionLifecycle.applicationDidEnterBackground(at: Date()),
            isVisibleReaderExit: false
        )
    }

    /// The Watch Live Activity requires applicationState == .active;
    /// willEnterForeground fires while the app is still .inactive, so the
    /// restart must wait for didBecomeActive.
    @objc private func appDidBecomeActive() {
        beginReadingSession(
            readingSessionLifecycle.applicationDidBecomeActive(
                at: Date(),
                progression: currentReadingProgression
            )
        )
    }

    @objc private func watchPageTurnDidSucceed(_ notification: Notification) {
        guard let origin = notification.object as? WatchPageTurnOrigin else { return }
        readingSessionLifecycle.recordSuccessfulWatchPageTurn(origin: origin)
    }

    // MARK: - Navigation bar

    func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = []
        // Table of Contents
        buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "menuIcon"), style: .plain, target: self, action: #selector(presentOutline)))

        // User preferences
        buttons.append(UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(presentUserPreferences)))

        // DRM management
        if publication.isProtected {
            buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "drm"), style: .plain, target: self, action: #selector(presentDRMManagement)))
        }
        // Bookmarks
        buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "bookmark"), style: .plain, target: self, action: #selector(bookmarkCurrentPosition)))
        // Search
        if publication.isSearchable {
            buttons.append(UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(showSearchUI)))
        }

        return buttons
    }

    // MARK: - NavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard !isReadingProgressPersistenceSuppressed else {
            suppressedReadingProgress = locator
            return
        }
        persistReadingProgress(locator)
    }

    func beginSuppressingReadingProgressPersistence() {
        isReadingProgressPersistenceSuppressed = true
        suppressedReadingProgress = nil
    }

    func endSuppressingReadingProgressPersistence(commit: Bool) {
        let locator = suppressedReadingProgress
        suppressedReadingProgress = nil
        isReadingProgressPersistenceSuppressed = false
        if commit, let locator {
            persistReadingProgress(locator)
        }
    }

    private func persistReadingProgress(_ locator: Locator) {
        Task {
            do {
                try await books.saveProgress(for: bookId, locator: locator)

                // Keep MRU order warm while the user reads.
                LastReadBooks.record(id: bookId.rawValue)
            } catch {
                moduleDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        // SFSafariViewController crashes when given an URL without an HTTP scheme.
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }
        present(SFSafariViewController(url: url), animated: true)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        moduleDelegate?.presentError(UserError(error), from: self)
    }

    func navigator(_ navigator: any Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        log(.error, "Failed to load resource at \(href): \(error)")
    }

    // MARK: - Locations

    var currentBookmark: Bookmark? {
        guard let locator = navigator.currentLocation else {
            return nil
        }

        return Bookmark(bookId: bookId, locator: locator)
    }

    // MARK: - Outlines

    @objc func presentOutline() {
        guard let locatorPublisher = moduleDelegate?.presentOutline(of: publication, bookId: bookId, from: self) else {
            return
        }

        locatorPublisher
            .sink(receiveValue: { [weak self] locator in
                Task {
                    await self?.navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
                    self?.dismiss(animated: true)
                }
            })
            .store(in: &subscriptions)
    }

    // MARK: - User Preferences

    @objc func presentUserPreferences() {}

    // MARK: - Bookmarks

    @objc func bookmarkCurrentPosition() {
        guard let bookmark = currentBookmark else {
            return
        }

        Task {
            do {
                try await bookmarks.add(bookmark)
                toast(NSLocalizedString("reader_bookmark_success_message", comment: "Success message when adding a bookmark"), on: self.view, duration: 1)
            } catch {
                print(error)
                toast(NSLocalizedString("reader_bookmark_failure_message", comment: "Error message when adding a new bookmark failed"), on: self.view, duration: 2)
            }
        }
    }

    // MARK: - Search

    @objc func showSearchUI() {
        if searchViewModel == nil {
            searchViewModel = SearchViewModel(publication: publication)
            searchViewModel?.$selectedLocator.sink { [weak self] locator in
                guard let self else { return }

                self.searchViewController?.dismiss(animated: true, completion: nil)
                if let locator = locator {
                    Task {
                        await self.navigator.go(
                            to: locator,
                            options: NavigatorGoOptions(animated: true)
                        )
                    }
                }

                if let decorator = self.navigator as? DecorableNavigator {
                    var decorations: [Decoration] = []
                    if let locator = locator {
                        decorations.append(Decoration(
                            id: "selectedSearchResult",
                            locator: locator,
                            style: .highlight(tint: .yellow, isActive: false)
                        ))
                    }
                    decorator.apply(decorations: decorations, in: "search")
                }
            }
            .store(in: &subscriptions)
        }

        let searchView = SearchView(viewModel: searchViewModel!)
        let vc = UIHostingController(rootView: searchView)
        vc.modalPresentationStyle = .pageSheet
        present(vc, animated: true, completion: nil)
        searchViewController = vc
    }

    // MARK: - DRM

    @objc func presentDRMManagement() {
        guard publication.isProtected else {
            return
        }
        moduleDelegate?.presentDRM(for: publication, from: self)
    }

    // MARK: - UIPopoverPresentationControllerDelegate

    /// Prevent the popOver to be presented fullscreen on iPhones.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
