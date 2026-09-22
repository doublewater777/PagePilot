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

        MicroReadingSessionPresenter.readerWillDisappear(self)
        finishReadingSession(
            readingSessionLifecycle.readerWillDisappear(at: Date())
        )
        setMainTabBarHidden(false, animated: animated)
        if (isMovingFromParent || isBeingDismissed),
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
        celebrateGoal: Bool = true
    ) {
        guard let finishedSession else { return }

        WatchReadingSessionContext.end()

        ReadingStatsStore.shared.recordReadingSession(
            startDate: finishedSession.startedAt,
            endDate: finishedSession.endedAt,
            bookId: finishedSession.bookId
        )

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

        // Celebrate the daily goal once per day, only on a visible exit (not
        // backgrounding) so the toast is actually seen.
        guard celebrateGoal,
              ReadingGoalPolicy.goalReached(
                  todaySeconds: ReadingStatsStore.shared.todayReadingSeconds(),
                  goalMinutes: ReadingPreferences.dailyGoalMinutes
              ),
              !ReadingGoalCelebration.alreadyCelebratedToday() else {
            return
        }
        ReadingGoalCelebration.markCelebratedToday()
        toast(NSLocalizedString("reader_goal_reached", comment: ""), on: view, duration: 2)
    }

    @objc private func appDidEnterBackground() {
        // Backgrounding ends the active interval without changing visibility,
        // so didBecomeActive can start a fresh interval only if this Reader
        // is still on screen.
        finishReadingSession(
            readingSessionLifecycle.applicationDidEnterBackground(at: Date()),
            celebrateGoal: false
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
