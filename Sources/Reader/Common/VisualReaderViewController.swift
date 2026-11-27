//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit
import WatchConnectivity

enum WatchGuidePresentationPolicy {
    static func shouldShow(
        isPhone: Bool,
        onboardingStep: OnboardingFlow.Step,
        availability: WatchAvailability,
        installReminderDismissed: Bool
    ) -> Bool {
        guard isPhone else { return false }

        if onboardingStep == .reader {
            switch availability {
            case .unsupported:
                return false
            case .unpaired, .appNotInstalled, .unreachable, .ready:
                return true
            }
        }

        guard availability == .appNotInstalled else { return false }
        return !installReminderDismissed
    }
}

struct WatchInstallReminderStore {
    private let defaults: UserDefaults
    private let key = "watchInstallReminder.dismissed.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isDismissed: Bool {
        defaults.bool(forKey: key)
    }

    func dismiss() {
        defaults.set(true, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

/// Base class for the reader view controller of a `VisualNavigator`.
class VisualReaderViewController<N: UIViewController & Navigator>: ReaderViewController<N>, VisualNavigatorDelegate, ReaderPositionIndicatorProviding {
    override var supportsDetailedReadingSessions: Bool { true }

    // MARK: - Keyboard shortcuts (Mac Catalyst)

    /// Appends a text-to-speech toggle on top of the reader-wide shortcuts
    /// declared in ReaderViewController.
    override var keyCommands: [UIKeyCommand]? {
        var commands = (super.keyCommands ?? []) + [
            // Esc: close any presented sheet, otherwise toggle the reader chrome.
            UIKeyCommand(
                title: NSLocalizedString("sc_reader_dismiss", comment: "Keyboard shortcut: dismiss sheet or toggle chrome"),
                action: #selector(readerEscape),
                input: UIKeyCommand.inputEscape
            ),
            UIKeyCommand(
                title: NSLocalizedString("sc_toggle_tts", comment: "Keyboard shortcut: toggle text-to-speech"),
                action: #selector(toggleTTS),
                input: "t",
                modifierFlags: [.command, .shift]
            ),
        ]
        if ReadingIntelligenceEngine.shared.isFeatureAvailable && !publication.isProtected {
            commands.append(
                UIKeyCommand(
                    title: NSLocalizedString("ai_recap_title", comment: ""),
                    action: #selector(presentReadingRecap),
                    input: "r",
                    modifierFlags: [.command, .shift]
                )
            )
            commands.append(
                UIKeyCommand(
                    title: NSLocalizedString("ai_chapter_summary_title", comment: ""),
                    action: #selector(presentChapterSummary),
                    input: "s",
                    modifierFlags: [.command, .shift]
                )
            )
        }
        #if targetEnvironment(macCatalyst)
        for command in commands where command.modifierFlags.contains(.command) || command.input == UIKeyCommand.inputEscape {
            command.wantsPriorityOverSystemBehavior = true
        }
        #endif
        return commands
    }

    @objc private func readerEscape() {
        // If a modal sheet (outline / preferences / search) is presented, close it.
        if let presented = presentedViewController {
            presented.dismiss(animated: true)
            return
        }
        // Otherwise toggle the reader navigation chrome (toolbar / navbar).
        toggleNavigationBar()
    }

    @objc private func toggleTTS() {
        guard let ttsViewModel else { return }
        if ttsViewModel.state.isPlaying {
            ttsViewModel.stop()
        } else {
            ttsViewModel.start()
        }
    }

    private lazy var positionLabel = UILabel()

    var positionIndicatorView: UIView {
        positionLabel
    }

    private var ttsViewModel: TTSViewModel?
    private var ttsControlsViewController: UIHostingController<TTSControls>?
    private var bottomBarModel = ReaderBottomBarModel()
    private var bottomBarHost: UIHostingController<ReaderBottomControlBar>?
    private var activeReaderThemeAppearance: ReaderThemeAppearance?
    private var positionCount: Int?
    private var positions: [Locator] = []
    private var directionalNavigationAdapter: DirectionalNavigationAdapter?
    #if targetEnvironment(macCatalyst)
    private var scrollPageTurnController: MacScrollPageTurnController?
    private var isTurningPageWithScroll = false
    #endif
    private var quickPositionJumpController: QuickPositionJumpInteractionController?
    private var wasTTSPlayingBeforeQuickPositionJump = false
    private var quickPositionJumpSuppressionToken: UUID?
    private var onboardingWatchGuideViewController: UIHostingController<OnboardingWatchGuideView>?
    private var onboardingWatchSuccessCancellable: AnyCancellable?
    private var onboardingIPadHintViewController: UIHostingController<OnboardingIPadReaderHintView>?
    private var didDismissWatchGuideThisSession = false
    private let watchInstallReminderStore = WatchInstallReminderStore()

    // Hands-Free Bedside Mode & Watch live feedback
    private var handsFreeState = HandsFreeReadingState()
    private var handsFreeShieldView: UIView?
    private var handsFreeUnlockButton: UIButton?
    private var handsFreeFilamentTrack: UIView?
    private var handsFreeFilamentFill: UIView?
    private var handsFreeFilamentWidthConstraint: NSLayoutConstraint?
    private var watchFeedbackPill: UIView?
    private var watchFeedbackHideWorkItem: DispatchWorkItem?

    init(
        navigator: N,
        publication: Publication,
        bookId: Book.Id,
        books: BookRepository,
        bookmarks: BookmarkRepository,
        highlights: HighlightRepository?
    ) {
        self.highlights = highlights
        self.ttsViewModel = nil
        self.ttsControlsViewController = nil

        super.init(
            navigator: navigator,
            publication: publication,
            bookId: bookId,
            books: books,
            bookmarks: bookmarks
        )

        setupUserInteraction()
        addHighlightDecorationsObserverOnce()
        updateHighlightDecorations()

        Task { [weak self] in
            let positions = (try? await publication.positions().get()) ?? []
            await MainActor.run {
                self?.positions = positions
                self?.positionCount = positions.count
                self?.quickPositionJumpController?.positions = positions
                self?.syncBottomBarState(with: self?.navigator.currentLocation)
            }
        }
    }

    /// Setups the user interaction (e.g. taps) with the navigator.
    private func setupUserInteraction() {
        guard let navigator = navigator as? VisualNavigator else {
            return
        }

        // Show a red dot at the location where the user tapped.
//        navigator.addObserver(.tap { [weak self] event in
//            guard let self else { return false }
//
//            let tapView = UIView(frame: .init(x: 0, y: 0, width: 50, height: 50))
//            view.addSubview(tapView)
//            tapView.backgroundColor = .red
//            tapView.center = event.location
//            tapView.layer.cornerRadius = 25
//            tapView.layer.masksToBounds = true
//            UIView.animate(withDuration: 0.8, animations: {
//                tapView.alpha = 0
//            }) { _ in
//                tapView.removeFromSuperview()
//            }
//
//            return false
//        })

        // This adapter will automatically turn pages when the user taps the
        // screen edges or press arrow keys.
        //
        // Bind it to the navigator before adding your own observers to prevent
        // triggering your actions when turning pages.
        #if targetEnvironment(macCatalyst)
        // Readium consumes presses in its own first responder. Handle app
        // commands through its input observer rather than the outer responder.
        navigator.addObserver(.key { [weak self] event in
            guard let self, self.presentedViewController == nil else { return false }
            if event.key == .escape, event.modifiers.isEmpty {
                self.readerEscape()
                return true
            }
            if event.key == .space, event.modifiers == .shift {
                _ = await self.navigator.goBackward(options: NavigatorGoOptions(animated: true))
                return true
            }
            guard case let .character(character) = event.key else { return false }
            let key = character.lowercased()
            switch (key, event.modifiers) {
            case ("o", [.command, .shift]): self.presentOutline()
            case ("f", .command): self.showSearchUI()
            case ("d", .command): self.bookmarkCurrentPosition()
            case ("p", [.command, .shift]): self.presentUserPreferences()
            case ("t", [.command, .shift]): self.toggleTTS()
            case ("k", [.command, .shift]): self.cycleQuickReaderTheme()
            case ("l", [.command, .shift]): self.toggleHandsFreeMode()
            case ("1", .command), ("2", .command):
                guard let tab = Int(key) else { return false }
                (UIApplication.shared.delegate as? AppDelegate)?.selectMainTab(tab - 1)
            default: return false
            }
            return true
        })
        #endif

        let adapter = DirectionalNavigationAdapter(
            pointerPolicy: .init(types: [.mouse, .touch])
        )
        adapter.bind(to: navigator)
        directionalNavigationAdapter = adapter

        // Clear the current search highlight on tap.
        navigator.addObserver(.activate { [weak self] _ in
            guard
                let searchViewModel = self?.searchViewModel,
                searchViewModel.selectedLocator != nil
            else {
                return false
            }

            searchViewModel.selectedLocator = nil
            return true
        })

        // Toggle the navigation bar on tap, if nothing else took precedence.
        navigator.addObserver(.activate { [weak self] _ in
            self?.toggleNavigationBar()
            return true
        })
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ShowNavigationBar") {
            navigationBarHidden = false
        }
        #endif

        updateNavigationBar(animated: false)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previous: UITraitCollection) in
            guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
            self.applyChromeAppearance()
        }

        addChild(navigator)
        #if !targetEnvironment(macCatalyst)
        navigator.view.frame = view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #endif
        view.addSubview(navigator.view)
        navigator.didMove(toParent: self)
        #if targetEnvironment(macCatalyst)
        navigator.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigator.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigator.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            navigator.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            navigator.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])
        #endif

        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        // Prevents VoiceOver from selecting the position label while reading
        // the page.
        positionLabel.isAccessibilityElement = false

        view.addSubview(positionLabel)
        NSLayoutConstraint.activate([
            positionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            positionLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -QuickPositionJumpPolicy.positionIndicatorBottomSpacing
            ),
        ])
        #if targetEnvironment(macCatalyst)
        setupPageTurnButtons()
        setupScrollPageTurning()
        #else
        title = publication.metadata.title
        setupBottomControlBar()
        #endif

        let quickPositionJumpController = QuickPositionJumpInteractionController(
            hostView: view,
            positionLabel: positionLabel,
            currentLocator: { [weak self] in self?.navigator.currentLocation },
            onTap: { [weak self] in self?.toggleNavigationBar() },
            onBegin: { [weak self] in await self?.beginQuickPositionJump() },
            onCommit: { [weak self] locator in
                guard let navigator = self?.navigator as? VisualNavigator else { return false }
                return await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
            },
            onRestore: { [weak self] locator in
                guard let navigator = self?.navigator as? VisualNavigator else { return false }
                return await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
            },
            onFinish: { [weak self] outcome in self?.finishQuickPositionJump(outcome) },
            onDeferredCleanup: { [weak self] restored in
                self?.finishInterruptedQuickPositionJump(restored: restored)
            }
        )
        quickPositionJumpController.positions = positions
        self.quickPositionJumpController = quickPositionJumpController

        applyChromeAppearance()
        updateBottomControlBarVisibility(animated: false)

        Task { [weak self] in
            guard let self = self else { return }

            let ttsVM = TTSViewModel(navigator: self.navigator, publication: self.publication)

            await MainActor.run {
                self.ttsViewModel = ttsVM
                self.bottomBarModel.supportsTTS = (ttsVM != nil)
                if let ttsViewModel = self.ttsViewModel {
                    let controls = UIHostingController(rootView: TTSControls(viewModel: ttsViewModel))
                    self.ttsControlsViewController = controls

                    controls.view.backgroundColor = .clear
                    controls.view.isHidden = true

                    self.addChild(controls)
                    controls.view.translatesAutoresizingMaskIntoConstraints = false
                    self.view.addSubview(controls.view)
                    NSLayoutConstraint.activate([
                        controls.view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                        controls.view.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                        controls.view.trailingAnchor.constraint(lessThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                        controls.view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
                    ])
                    controls.didMove(toParent: self)

                    ttsViewModel.$state
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] state in
                            controls.view.isHidden = !state.showControls
                            self?.bottomBarModel.isTTSPlaying = state.isPlaying
                            self?.updateBottomControlBarVisibility(animated: true)
                        }
                        .store(in: &self.subscriptions)

                    // Refresh navigation bar to display TTS button on Mac Catalyst
                    self.navigationItem.rightBarButtonItems = self.makeNavigationBarButtons()
                }
            }
        }

        WatchPageTurnService.shared.activate()
        showOnboardingWatchGuideIfNeeded()
        showOnboardingIPadHintIfNeeded()
        observeWatchPageTurnVisualFeedback()

        // Refine position from external trigger (e.g. MyNotes) once the navigator is ready.
        if let visualNavigator = navigator as? VisualNavigator,
           let target = AppModule.shared?.pendingNavigationTarget,
           target.bookId == bookId {
            let locator = target.locator
            AppModule.shared?.pendingNavigationTarget = nil
            Task {
                await navigateToLocator(locator, on: visualNavigator)
            }
        }
    }

    private func showOnboardingWatchGuideIfNeeded() {
        reconcileOnboardingWatchGuide()

        WatchPageTurnService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileOnboardingWatchGuide()
            }
            .store(in: &subscriptions)
    }

    private func reconcileOnboardingWatchGuide() {
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let availability = WatchPageTurnService.shared.watchAvailability
        let flow = OnboardingProgressStore().load(platform: .iPhone)

        if availability != .appNotInstalled {
            watchInstallReminderStore.reset()
        }

        let shouldShow = WatchGuidePresentationPolicy.shouldShow(
            isPhone: isPhone,
            onboardingStep: flow.step,
            availability: availability,
            installReminderDismissed: watchInstallReminderStore.isDismissed
        )

        if shouldShow,
           !didDismissWatchGuideThisSession,
           onboardingWatchGuideViewController == nil {
            presentOnboardingWatchGuide()
        } else if !shouldShow,
                  onboardingWatchGuideViewController != nil {
            removeOnboardingWatchGuide()
        }
    }

    private func presentOnboardingWatchGuide() {
        let flow = OnboardingProgressStore().load(platform: .iPhone)
        let isActivationGuide = flow.step == .reader
        let dismissTitle: LocalizedStringKey = flow.step == .reader
            ? "onboarding_watch_skip"
            : "close_button"
        let guide = OnboardingWatchGuideView(
            service: WatchPageTurnService.shared,
            dismissTitle: dismissTitle,
            onDismiss: { [weak self] in
                self?.dismissOnboardingWatchGuide()
            },
            onCollapse: {
                if isActivationGuide {
                    Analytics.shared.log(.onboardingWatchGuideCollapsed)
                }
            }
        )
        let hostingController = UIHostingController(rootView: guide)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            hostingController.view.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            hostingController.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            hostingController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -68),
        ])
        hostingController.didMove(toParent: self)
        onboardingWatchGuideViewController = hostingController
        if isActivationGuide {
            Analytics.shared.log(
                .onboardingWatchGuideShown(
                    availability: watchAvailabilityAnalyticsName
                )
            )
        }

        onboardingWatchSuccessCancellable = NotificationCenter.default.publisher(for: .watchPageTurnDidSucceed)
            .prefix(1)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.completeOnboardingWatchGuide()
            }
    }

    private func showOnboardingIPadHintIfNeeded() {
        guard PagePilotReaderHost.isSupported else { return }
        let store = OnboardingProgressStore()
        let flow = store.load(platform: .iPad)
        guard flow.platform == .iPad, flow.step == .reader else { return }

        let hint = OnboardingIPadReaderHintView(onDismiss: { [weak self] in
            let store = OnboardingProgressStore()
            var flow = store.load(platform: .iPad)
            flow.finish()
            store.save(flow)
            self?.removeOnboardingIPadHint()
        })
        let hostingController = UIHostingController(rootView: hint)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            hostingController.view.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            hostingController.view.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            hostingController.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            hostingController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
        ])
        hostingController.didMove(toParent: self)
        onboardingIPadHintViewController = hostingController
    }

    private func completeOnboardingWatchGuide() {
        let store = OnboardingProgressStore()
        var flow = store.load(platform: .iPhone)
        flow.didCompleteWatchPageTurn()
        store.save(flow)
        watchInstallReminderStore.reset()
        Analytics.shared.log(.onboardingWatchActivationCompleted)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toast(
            NSLocalizedString("onboarding_watch_success", comment: ""),
            on: view,
            duration: 1.2
        )

        guard let guideView = onboardingWatchGuideViewController?.view else { return }
        if UIAccessibility.isReduceMotionEnabled {
            removeOnboardingWatchGuide()
            return
        }
        guideView.layer.shadowColor = UIColor(red: 41 / 255, green: 158 / 255, blue: 148 / 255, alpha: 1).cgColor
        guideView.layer.shadowOpacity = 0.55
        guideView.layer.shadowRadius = 22
        UIView.animate(withDuration: 0.25, animations: {
            guideView.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        }) { [weak self] _ in
            UIView.animate(withDuration: 0.3, animations: {
                guideView.alpha = 0
            }) { _ in
                self?.removeOnboardingWatchGuide()
            }
        }
    }

    private func dismissOnboardingWatchGuide() {
        let progressStore = OnboardingProgressStore()
        var flow = progressStore.load(platform: .iPhone)
        let isActivationGuide = flow.step == .reader
        if isActivationGuide {
            flow.finish()
            progressStore.save(flow)
        }

        let availability = WatchPageTurnService.shared.watchAvailability
        if isActivationGuide {
            Analytics.shared.log(
                .onboardingWatchGuideDismissed(
                    availability: watchAvailabilityAnalyticsName
                )
            )
        }
        if availability == .appNotInstalled {
            watchInstallReminderStore.dismiss()
        }

        didDismissWatchGuideThisSession = true
        removeOnboardingWatchGuide()
    }

    private func removeOnboardingWatchGuide() {
        onboardingWatchSuccessCancellable?.cancel()
        onboardingWatchSuccessCancellable = nil
        guard let hostingController = onboardingWatchGuideViewController else { return }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        onboardingWatchGuideViewController = nil
    }

    private var watchAvailabilityAnalyticsName: String {
        switch WatchPageTurnService.shared.watchAvailability {
        case .unsupported: return "unsupported"
        case .unpaired: return "unpaired"
        case .appNotInstalled: return "app_not_installed"
        case .unreachable: return "unreachable"
        case .ready: return "ready"
        }
    }

    private func removeOnboardingIPadHint() {
        guard let hostingController = onboardingIPadHintViewController else { return }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        onboardingIPadHintViewController = nil
    }

    /// Retries navigation until the navigator accepts the locator or times out.
    override func navigateToReadingLocation(_ locator: Locator) {
        guard let visualNavigator = navigator as? VisualNavigator else { return }
        Task { await navigateToLocator(locator, on: visualNavigator) }
    }

    private func navigateToLocator(_ locator: Locator, on navigator: VisualNavigator) async {
        for _ in 0 ..< 30 {
            if await navigator.go(to: locator, options: NavigatorGoOptions(animated: false)) {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func beginQuickPositionJump() async {
        directionalNavigationAdapter?.pointerPolicy.types = []
        directionalNavigationAdapter?.keyboardPolicy = .init(
            handleArrowKeys: false,
            handleSpaceKey: false
        )
        quickPositionJumpSuppressionToken = WatchPageTurnService.shared.beginPageTurnSuppression()
        beginSuppressingReadingProgressPersistence()
        await ttsViewModel?.suspendNavigation()
        wasTTSPlayingBeforeQuickPositionJump = ttsViewModel?.state.isPlaying == true
        if wasTTSPlayingBeforeQuickPositionJump {
            ttsViewModel?.pause()
        }
    }

    private func finishQuickPositionJump(_ outcome: QuickPositionJumpInteractionController.Outcome) {
        if case .interrupted = outcome {
            return
        }

        directionalNavigationAdapter?.pointerPolicy.types = [.mouse, .touch]
        directionalNavigationAdapter?.keyboardPolicy = .init()
        if let token = quickPositionJumpSuppressionToken {
            WatchPageTurnService.shared.endPageTurnSuppression(token)
            quickPositionJumpSuppressionToken = nil
        }

        let shouldResumeTTS = wasTTSPlayingBeforeQuickPositionJump
        wasTTSPlayingBeforeQuickPositionJump = false
        switch outcome {
        case let .committed(target):
            endSuppressingReadingProgressPersistence(commit: true)
            publishWatchProgress(navigator.currentLocation ?? target)
            ttsViewModel?.resumeNavigation()
            if shouldResumeTTS {
                ttsViewModel?.restart(from: target)
            }
        case .cancelled:
            endSuppressingReadingProgressPersistence(commit: false)
            ttsViewModel?.resumeNavigation()
            if shouldResumeTTS {
                ttsViewModel?.pauseOrResume()
            }
        case .failed:
            endSuppressingReadingProgressPersistence(commit: false)
            ttsViewModel?.resumeNavigation()
            if shouldResumeTTS {
                ttsViewModel?.pauseOrResume()
            }
            toast(
                NSLocalizedString("reader_quick_position_failure", comment: ""),
                on: view,
                duration: 2
            )
        case .interrupted:
            break
        }
    }

    private func finishInterruptedQuickPositionJump(restored: Bool) {
        directionalNavigationAdapter?.pointerPolicy.types = [.mouse, .touch]
        directionalNavigationAdapter?.keyboardPolicy = .init()
        if let token = quickPositionJumpSuppressionToken {
            WatchPageTurnService.shared.endPageTurnSuppression(token)
            quickPositionJumpSuppressionToken = nil
        }
        endSuppressingReadingProgressPersistence(commit: false)
        ttsViewModel?.resumeNavigation()
        let shouldResumeTTS = wasTTSPlayingBeforeQuickPositionJump
        wasTTSPlayingBeforeQuickPositionJump = false
        if shouldResumeTTS {
            ttsViewModel?.pauseOrResume()
        }
        if !restored, viewIfLoaded?.window != nil {
            toast(
                NSLocalizedString("reader_quick_position_failure", comment: ""),
                on: view,
                duration: 2
            )
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if isReadingWindowActive, let visualNavigator = navigator as? VisualNavigator {
            WatchPageTurnService.shared.registerNavigator(visualNavigator, publication: publication)
        }

        VolumeKeyService.shared.register(self)
        VolumeKeyService.shared.onPageForward = { [weak self] in
            guard self?.quickPositionJumpController?.isActive != true,
                  let navigator = self?.navigator as? VisualNavigator else { return }
            Task { await navigator.goForward(options: NavigatorGoOptions(animated: false)) }
        }
        VolumeKeyService.shared.onPageBackward = { [weak self] in
            guard self?.quickPositionJumpController?.isActive != true,
                  let navigator = self?.navigator as? VisualNavigator else { return }
            Task { await navigator.goBackward(options: NavigatorGoOptions(animated: false)) }
        }
    }

    override func readingWindowDidActivate() {
        super.readingWindowDidActivate()
        if isReadingWindowActive, let visualNavigator = navigator as? VisualNavigator {
            WatchPageTurnService.shared.registerNavigator(visualNavigator, publication: publication)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        VolumeKeyService.shared.unregister(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setHandsFreeMode(false, announce: false)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        wasTTSPlayingBeforeQuickPositionJump = false
        quickPositionJumpController?.cancel()
        ttsViewModel?.stop()
        if let visualNavigator = navigator as? VisualNavigator {
            WatchPageTurnService.shared.unregisterNavigator(visualNavigator)
        }
    }

    deinit {
        if handsFreeState.isEnabled {
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        quickPositionJumpController?.cancel()
        super.viewWillTransition(to: size, with: coordinator)
        PostHogAnalytics.shared.recordPostureChange(size: size)
    }

    #if targetEnvironment(macCatalyst)
    private func setupScrollPageTurning() {
        scrollPageTurnController = MacScrollPageTurnController(
            view: navigator.view,
            canTurn: { [weak self] in
                guard let self, let visualNavigator = self.navigator as? VisualNavigator else { return false }
                if let pdfView = (self.navigator as? PDFNavigatorViewController)?.pdfView,
                   pdfView.scaleFactor > pdfView.minScaleFactor * 1.01 {
                    return false
                }
                return !visualNavigator.presentation.scroll
                    && self.presentedViewController == nil
                    && self.quickPositionJumpController?.isActive != true
            },
            onTurn: { [weak self] translation in
                guard let self, !self.isTurningPageWithScroll,
                      let visualNavigator = self.navigator as? VisualNavigator
                else { return }
                self.isTurningPageWithScroll = true
                Task {
                    defer { self.isTurningPageWithScroll = false }
                    let options = NavigatorGoOptions(animated: true)
                    if abs(translation.x) > abs(translation.y) {
                        if translation.x < 0 {
                            _ = await visualNavigator.goRight(options: options)
                        } else {
                            _ = await visualNavigator.goLeft(options: options)
                        }
                    } else if translation.y < 0 {
                        _ = await self.navigator.goForward(options: options)
                    } else {
                        _ = await self.navigator.goBackward(options: options)
                    }
                }
            }
        )
    }

    private func setupPageTurnButtons() {
        for forward in [false, true] {
            let button = UIButton(type: .system)
            let title = NSLocalizedString(forward ? "sc_next_page" : "sc_prev_page", comment: "")
            button.setImage(UIImage(systemName: forward ? "chevron.forward" : "chevron.backward"), for: .normal)
            button.accessibilityLabel = title
            button.addInteraction(UIToolTipInteraction(defaultToolTip: title))
            button.addAction(UIAction { [weak self] _ in
                guard let self,
                      self.presentedViewController == nil,
                      self.quickPositionJumpController?.isActive != true
                else { return }
                Task {
                    if forward {
                        _ = await self.navigator.goForward(options: NavigatorGoOptions(animated: true))
                    } else {
                        _ = await self.navigator.goBackward(options: NavigatorGoOptions(animated: true))
                    }
                }
            }, for: .primaryActionTriggered)
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28),
                button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -2),
                forward
                    ? button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20)
                    : button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            ])
        }
    }
    #endif

    // MARK: - Navigation bar & Bottom Floating Control Bar

    override var usesBottomControlBar: Bool { !PagePilotReaderHost.isMac }

    var supportsQuickThemeCycle: Bool { false }

    func cycleQuickReaderTheme() {}

    func applyPaperPreset(_ preset: ReaderPaperPreset) {}

    func updateActivePaperPreset(_ preset: ReaderPaperPreset?) {
        bottomBarModel.activePaperPreset = preset
        if PagePilotReaderHost.isMac {
            navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        }
    }

    // MARK: - Hands-Free Bedside Mode & Watch Feedback

    private func observeWatchPageTurnVisualFeedback() {
        NotificationCenter.default.publisher(for: .watchPageTurnDidSucceed)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isReadingWindowActive else { return }
                self.showWatchPageTurnFeedbackPill()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.handsFreeState.isEnabled else { return }
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.handsFreeState.isEnabled, self.viewIfLoaded?.window != nil else { return }
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .store(in: &subscriptions)
    }

    func toggleHandsFreeMode() {
        setHandsFreeMode(!handsFreeState.isEnabled, announce: true)
    }

    private func setHandsFreeMode(_ enabled: Bool, announce: Bool) {
        guard handsFreeState.isEnabled != enabled else { return }
        if enabled {
            handsFreeState.enable()
        } else {
            handsFreeState.disable()
        }

        bottomBarModel.isHandsFreeMode = handsFreeState.isEnabled
        UIApplication.shared.isIdleTimerDisabled = handsFreeState.shouldKeepScreenAwake

        if handsFreeState.isEnabled {
            navigationBarHidden = true
            installHandsFreeOverlayIfNeeded()
            handsFreeShieldView?.isHidden = false
            handsFreeUnlockButton?.isHidden = false
            handsFreeFilamentTrack?.isHidden = false
            updateHandsFreeFilamentProgress()
            positionLabel.isHidden = true
            if announce {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showTopMicroPill(
                    icon: "moon.stars.fill",
                    text: NSLocalizedString("reader_handsfree_enabled_toast", comment: "")
                )
            }
        } else {
            handsFreeShieldView?.isHidden = true
            handsFreeUnlockButton?.isHidden = true
            handsFreeFilamentTrack?.isHidden = true
            positionLabel.isHidden = false
            if announce {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showTopMicroPill(
                    icon: "lock.open.fill",
                    text: NSLocalizedString("reader_handsfree_disabled_toast", comment: "")
                )
            }
        }
    }

    private func installHandsFreeOverlayIfNeeded() {
        guard handsFreeShieldView == nil else { return }

        // Transparent anti-accidental-touch shield absorbing stray pillow/palm touches
        let shield = UIView()
        shield.translatesAutoresizingMaskIntoConstraints = false
        shield.backgroundColor = .clear
        let shieldTap = UITapGestureRecognizer(target: self, action: #selector(handleHandsFreeShieldTap))
        shield.addGestureRecognizer(shieldTap)
        let shieldPan = UIPanGestureRecognizer(target: self, action: #selector(handleHandsFreeShieldPan))
        shield.addGestureRecognizer(shieldPan)
        view.addSubview(shield)
        NSLayoutConstraint.activate([
            shield.topAnchor.constraint(equalTo: view.topAnchor),
            shield.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shield.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        handsFreeShieldView = shield

        // Ultra-subtle 2pt bottom reading progress filament
        let track = UIView()
        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = UIColor.secondaryLabel.withAlphaComponent(0.18)
        track.layer.cornerRadius = 1
        track.clipsToBounds = true
        track.isUserInteractionEnabled = false
        view.addSubview(track)

        let fill = UIView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = AppColors.uiAccentTeal
        fill.layer.cornerRadius = 1
        track.addSubview(fill)

        let widthConstraint = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: max(0.01, CGFloat(bottomBarModel.progress)))
        NSLayoutConstraint.activate([
            track.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            track.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            track.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            track.heightAnchor.constraint(equalToConstant: 2),

            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            widthConstraint,
        ])
        handsFreeFilamentTrack = track
        handsFreeFilamentFill = fill
        handsFreeFilamentWidthConstraint = widthConstraint

        // Quiet bottom-right unlock pill
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = AppColors.uiAccentTeal.withAlphaComponent(0.16)
        config.baseForegroundColor = AppColors.uiAccentTeal
        config.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
        var attrs = AttributeContainer()
        attrs.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        config.attributedTitle = AttributedString(
            NSLocalizedString("reader_handsfree_unlock_pill", comment: ""),
            attributes: attrs
        )

        let unlockBtn = UIButton(configuration: config)
        unlockBtn.translatesAutoresizingMaskIntoConstraints = false
        unlockBtn.addAction(UIAction { [weak self] _ in
            self?.setHandsFreeMode(false, announce: true)
        }, for: .primaryActionTriggered)
        view.addSubview(unlockBtn)
        NSLayoutConstraint.activate([
            unlockBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            unlockBtn.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -12),
        ])
        handsFreeUnlockButton = unlockBtn
    }

    private func updateHandsFreeFilamentProgress() {
        guard let track = handsFreeFilamentTrack, let fill = handsFreeFilamentFill else { return }
        handsFreeFilamentWidthConstraint?.isActive = false
        let fraction = max(0.01, min(1.0, CGFloat(bottomBarModel.progress)))
        let updated = fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: fraction)
        updated.isActive = true
        handsFreeFilamentWidthConstraint = updated
        UIView.animate(withDuration: 0.25) {
            track.layoutIfNeeded()
        }
    }

    @objc private func handleHandsFreeShieldTap() {
        guard let unlockBtn = handsFreeUnlockButton else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.animate(withDuration: 0.14, animations: {
            unlockBtn.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }) { _ in
            UIView.animate(withDuration: 0.22) {
                unlockBtn.transform = .identity
            }
        }
    }

    @objc private func handleHandsFreeShieldPan() {
        // Intentionally absorbs stray pillow/bedside swipes while Hands-Free lock is active.
    }

    private func showWatchPageTurnFeedbackPill() {
        showTopMicroPill(
            icon: "applewatch",
            text: NSLocalizedString("reader_watch_turned_pill", comment: "")
        )
    }

    private func showTopMicroPill(icon: String, text: String) {
        watchFeedbackHideWorkItem?.cancel()
        watchFeedbackPill?.removeFromSuperview()

        let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer.cornerRadius = 16
        pill.clipsToBounds = true
        pill.layer.borderWidth = 0.6
        pill.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        pill.isUserInteractionEnabled = false
        pill.alpha = 0
        pill.transform = CGAffineTransform(translationX: 0, y: -10).scaledBy(x: 0.94, y: 0.94)

        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = AppColors.uiAccentTeal
        dot.layer.cornerRadius = 3
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])

        let iconView = UIImageView(image: UIImage(
            systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        ))
        iconView.tintColor = AppColors.uiAccentTeal
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [dot, iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(stack)
        view.addSubview(pill)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -7),

            pill.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            pill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
        watchFeedbackPill = pill

        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
            pill.alpha = 1
            pill.transform = .identity
        }

        let workItem = DispatchWorkItem { [weak self, weak pill] in
            guard let pill else { return }
            UIView.animate(withDuration: 0.25, animations: {
                pill.alpha = 0
                pill.transform = CGAffineTransform(translationX: 0, y: -8)
            }) { _ in
                pill.removeFromSuperview()
                if self?.watchFeedbackPill === pill {
                    self?.watchFeedbackPill = nil
                }
            }
        }
        watchFeedbackHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    func presentQuotePostcard(_ payload: QuotePostcardPayload) {
        let postcardView = QuotePostcardView(payload: payload)
        let hosting = UIHostingController(rootView: postcardView)
        let isRegular = traitCollection.horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
        hosting.modalPresentationStyle = isRegular ? .formSheet : .pageSheet
        if isRegular {
            hosting.preferredContentSize = CGSize(width: 480, height: 660)
        } else if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(hosting, animated: true)
    }

    func presentReadingIntelligence(
        task: ReadingIntelligenceTask,
        contextLoader: (() async -> ReadingIntelligenceTask?)? = nil
    ) {
        guard ReadingIntelligenceEngine.shared.isFeatureAvailable else { return }
        let sheetView = ReadingIntelligenceSheet(task: task, contextLoader: contextLoader)
        let hosting = UIHostingController(rootView: sheetView)
        let isRegular = traitCollection.horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
        hosting.modalPresentationStyle = isRegular ? .formSheet : .pageSheet
        if isRegular {
            hosting.preferredContentSize = CGSize(width: 520, height: 620)
        } else if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
        }
        present(hosting, animated: true)
    }

    @objc func presentReadingRecap() {
        guard ReadingIntelligenceEngine.shared.isFeatureAvailable, !publication.isProtected else { return }
        let bookTitle = publication.metadata.title ?? "PagePilot"
        let locator = navigator.currentLocation
        let chapterTitle = locator?.title ?? bottomBarModel.chapterTitle
        let placeholder = ReadingIntelligenceTask.recap(
            bookTitle: bookTitle,
            chapterTitle: chapterTitle.isEmpty ? nil : chapterTitle,
            priorExcerpt: ""
        )
        let pub = publication
        presentReadingIntelligence(task: placeholder) {
            let excerpt = await ReadingExcerptExtractor.extractPriorContext(from: pub, currentLocator: locator)
            guard !excerpt.isEmpty else { return nil }
            return .recap(
                bookTitle: bookTitle,
                chapterTitle: chapterTitle.isEmpty ? nil : chapterTitle,
                priorExcerpt: excerpt
            )
        }
    }

    @objc func presentChapterSummary() {
        guard ReadingIntelligenceEngine.shared.isFeatureAvailable, !publication.isProtected else { return }
        let bookTitle = publication.metadata.title ?? "PagePilot"
        let locator = navigator.currentLocation
        let chapterTitle = locator?.title ?? bottomBarModel.chapterTitle
        let placeholder = ReadingIntelligenceTask.chapterSummary(
            bookTitle: bookTitle,
            chapterTitle: chapterTitle.isEmpty ? nil : chapterTitle,
            chapterExcerpt: ""
        )
        let pub = publication
        presentReadingIntelligence(task: placeholder) {
            let excerpt = await ReadingExcerptExtractor.extractCurrentChapter(from: pub, currentLocator: locator)
            guard !excerpt.isEmpty else { return nil }
            return .chapterSummary(
                bookTitle: bookTitle,
                chapterTitle: chapterTitle.isEmpty ? nil : chapterTitle,
                chapterExcerpt: excerpt
            )
        }
    }

    var bottomControlBarAnchorView: UIView? {
        bottomBarHost?.view
    }

    private var navigationBarHidden: Bool = !PagePilotReaderHost.isMac {
        didSet {
            updateNavigationBar()
        }
    }

    override func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = super.makeNavigationBarButtons()

        // On Mac Catalyst, expose quick Paper Presets menu, Hands-Free focus lock, and TTS in the top toolbar.
        if PagePilotReaderHost.isMac {
            if supportsQuickThemeCycle {
                let activePreset = bottomBarModel.activePaperPreset
                let presetActions = ReaderPaperPreset.allCases.map { preset in
                    UIAction(
                        title: preset.localizedTitle,
                        image: UIImage(systemName: preset.iconName),
                        state: activePreset == preset ? .on : .off
                    ) { [weak self] _ in
                        self?.applyPaperPreset(preset)
                    }
                }
                let presetButton = UIBarButtonItem(
                    image: UIImage(systemName: activePreset?.iconName ?? "sun.max"),
                    menu: UIMenu(title: NSLocalizedString("reader_prefs_theme_section", comment: ""), children: presetActions)
                )
                presetButton.accessibilityLabel = NSLocalizedString("reader_prefs_theme_section", comment: "")
                buttons.append(presetButton)
            }

            let handsFreeButton = UIBarButtonItem(
                image: UIImage(systemName: handsFreeState.isEnabled ? "lock.fill" : "moon.stars"),
                style: .plain,
                target: self,
                action: #selector(toggleHandsFreeFromToolbar)
            )
            handsFreeButton.accessibilityLabel = NSLocalizedString("reader_bar_handsfree", comment: "")
            buttons.append(handsFreeButton)

            if ReadingIntelligenceEngine.shared.isFeatureAvailable && !publication.isProtected {
                let aiMenu = UIMenu(
                    title: NSLocalizedString("ai_badge_apple_intelligence", comment: ""),
                    children: [
                        UIAction(
                            title: NSLocalizedString("ai_recap_title", comment: ""),
                            image: UIImage(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        ) { [weak self] _ in
                            self?.presentReadingRecap()
                        },
                        UIAction(
                            title: NSLocalizedString("ai_chapter_summary_title", comment: ""),
                            image: UIImage(systemName: "text.document")
                        ) { [weak self] _ in
                            self?.presentChapterSummary()
                        },
                    ]
                )
                let aiButton = UIBarButtonItem(
                    image: UIImage(systemName: "sparkles"),
                    menu: aiMenu
                )
                aiButton.accessibilityLabel = NSLocalizedString("ai_badge_apple_intelligence", comment: "")
                buttons.append(aiButton)
            }

            if let ttsViewModel = ttsViewModel {
                let ttsButton = UIBarButtonItem(
                    image: UIImage(systemName: "headphones"),
                    style: .plain,
                    target: ttsViewModel,
                    action: #selector(TTSViewModel.start)
                )
                ttsButton.accessibilityLabel = NSLocalizedString("reader_bar_listen", comment: "")
                buttons.append(ttsButton)
            }
        }

        return buttons
    }

    @objc private func toggleHandsFreeFromToolbar() {
        toggleHandsFreeMode()
    }

    func toggleNavigationBar() {
        navigationBarHidden = !navigationBarHidden
    }

    func updateNavigationBar(animated: Bool = true) {
        navigationController?.setNavigationBarHidden(navigationBarHidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
        updateBottomControlBarVisibility(animated: animated)
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersStatusBarHidden: Bool {
        navigationBarHidden
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if let appearance = activeReaderThemeAppearance {
            return appearance.isDarkSurface ? .lightContent : .darkContent
        }
        return .default
    }

    /// Applies the active publication theme (Light / Sepia / Dark / custom) to native reader chrome.
    func updateReaderThemeAppearance(_ appearance: ReaderThemeAppearance) {
        activeReaderThemeAppearance = appearance
        applyChromeAppearance()
    }

    func updateQuickThemeIndicator(iconName: String, label: String) {
        bottomBarModel.supportsQuickTheme = supportsQuickThemeCycle
        bottomBarModel.themeIconName = iconName
        bottomBarModel.themeLabel = label
    }

    private func applyChromeAppearance() {
        if let appearance = activeReaderThemeAppearance {
            view.backgroundColor = appearance.backgroundColor
            positionLabel.textColor = appearance.secondaryTextColor
            bottomBarModel.isDarkChrome = appearance.isDarkSurface
            navigationController?.navigationBar.overrideUserInterfaceStyle = appearance.isDarkSurface ? .dark : .light
        } else {
            view.backgroundColor = .systemBackground
            positionLabel.textColor = .secondaryLabel
            bottomBarModel.isDarkChrome = (traitCollection.userInterfaceStyle == .dark)
            navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    private func setupBottomControlBar() {
        bottomBarModel.supportsQuickTheme = supportsQuickThemeCycle
        bottomBarModel.supportsIntelligence = ReadingIntelligenceEngine.shared.isFeatureAvailable && !publication.isProtected
        ReadingIntelligenceEngine.shared.$simulationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.bottomBarModel.supportsIntelligence = ReadingIntelligenceEngine.shared.isFeatureAvailable && !self.publication.isProtected
                if PagePilotReaderHost.isMac {
                    self.navigationItem.rightBarButtonItems = self.makeNavigationBarButtons()
                }
            }
            .store(in: &subscriptions)
        let controlBar = ReaderBottomControlBar(
            model: bottomBarModel,
            onOutline: { [weak self] in
                self?.presentOutline()
            },
            onAppearance: { [weak self] in
                self?.presentUserPreferences()
            },
            onSelectPaperPreset: { [weak self] preset in
                self?.applyPaperPreset(preset)
            },
            onToggleHandsFree: { [weak self] in
                self?.toggleHandsFreeMode()
            },
            onToggleTTS: { [weak self] in
                self?.toggleTTS()
            },
            onIntelligenceRecap: { [weak self] in
                self?.presentReadingRecap()
            },
            onIntelligenceSummary: { [weak self] in
                self?.presentChapterSummary()
            },
            onScrubPreview: { [weak self] index in
                self?.previewBottomBarPosition(at: index)
            },
            onScrubCommit: { [weak self] index in
                self?.commitBottomBarPosition(at: index)
            }
        )

        let host = UIHostingController(rootView: controlBar)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)

        let widthFill = host.view.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -28)
        widthFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            widthFill,
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        host.didMove(toParent: self)
        bottomBarHost = host
    }

    private func updateBottomControlBarVisibility(animated: Bool) {
        guard let barView = bottomBarHost?.view else { return }
        let isTTSVisible = ttsViewModel?.state.showControls == true
        let shouldShowBar = !navigationBarHidden && !isTTSVisible

        let applyState = {
            barView.alpha = shouldShowBar ? 1 : 0
            barView.transform = shouldShowBar ? .identity : CGAffineTransform(translationX: 0, y: 18)
            self.positionLabel.alpha = (shouldShowBar || isTTSVisible) ? 0 : 1
        }

        if shouldShowBar {
            barView.isHidden = false
            barView.isUserInteractionEnabled = true
        } else {
            barView.isUserInteractionEnabled = false
        }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.2,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: applyState
            ) { _ in
                if !shouldShowBar {
                    barView.isHidden = true
                }
            }
        } else {
            applyState()
            barView.isHidden = !shouldShowBar
        }
    }

    private func syncBottomBarState(with locator: Locator?) {
        let total = positions.count
        bottomBarModel.totalPositions = total

        let title = locator?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        bottomBarModel.chapterTitle = (title?.isEmpty == false)
            ? title!
            : (publication.metadata.title ?? "")

        if let position = locator?.locations.position, total > 0 {
            let clamped = max(1, min(total, position))
            bottomBarModel.currentPositionIndex = clamped - 1
            let pct = QuickPositionJumpPolicy.percentage(
                totalProgression: locator?.locations.totalProgression,
                targetPosition: clamped,
                positionCount: total
            )
            bottomBarModel.percentageText = "\(pct)%"
            bottomBarModel.positionText = positionsArePages
                ? "\(clamped) / \(total)"
                : String(format: NSLocalizedString("reader_position_format", comment: ""), clamped, total)
            bottomBarModel.progress = total > 1 ? Double(clamped - 1) / Double(total - 1) : 1.0
            if let remainingMin = ReadingTimeEstimator.remainingMinutes(currentPosition: clamped, targetEndPosition: total) {
                bottomBarModel.remainingTimeText = ReadingTimeEstimator.localizedRemainingText(minutes: remainingMin)
            } else {
                bottomBarModel.remainingTimeText = ""
            }
        } else if let totalProgression = locator?.locations.totalProgression {
            let clamped = min(max(totalProgression, 0), 1)
            bottomBarModel.progress = clamped
            bottomBarModel.percentageText = "\(Int((clamped * 100).rounded()))%"
            bottomBarModel.positionText = ""
            bottomBarModel.remainingTimeText = ""
        }
        if handsFreeState.isEnabled {
            updateHandsFreeFilamentProgress()
        }
    }

    private func previewBottomBarPosition(at index: Int) {
        guard positions.indices.contains(index) else { return }
        let locator = positions[index]
        let total = positions.count
        let pos = index + 1
        let pct = QuickPositionJumpPolicy.percentage(
            totalProgression: locator.locations.totalProgression,
            targetPosition: pos,
            positionCount: total
        )
        let title = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            bottomBarModel.chapterTitle = title
        }
        bottomBarModel.percentageText = "\(pct)%"
        bottomBarModel.positionText = positionsArePages
            ? "\(pos) / \(total)"
            : String(format: NSLocalizedString("reader_position_format", comment: ""), pos, total)
    }

    private func commitBottomBarPosition(at index: Int) {
        guard positions.indices.contains(index),
              let visualNavigator = navigator as? VisualNavigator else { return }
        let target = positions[index]
        Task {
            _ = await visualNavigator.go(to: target, options: NavigatorGoOptions(animated: false))
        }
    }

    // MARK: - VisualNavigatorDelegate

    /// Whether locator positions correspond to actual pages (PDF, fixed-layout
    /// publications) rather than Readium's synthetic reflowable positions.
    var positionsArePages: Bool {
        publication.metadata.layout == .fixed
    }

    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)

        positionLabel.text = {
            guard let positionCount = positionCount,
                  let position = locator.locations.position
            else {
                return nil
            }

            if positionsArePages {
                // PDF / fixed-layout: positions are actual page numbers.
                return "\(position) / \(positionCount)"
            }

            // Reflowable publications use Readium positions, paired with estimated time left on Mac.
            let base = String(
                format: NSLocalizedString(
                    "reader_position_format",
                    comment: "Reader footer: current reading position out of total positions"
                ),
                position,
                positionCount
            )
            if PagePilotReaderHost.isMac,
               let remainingMin = ReadingTimeEstimator.remainingMinutes(currentPosition: position, targetEndPosition: positionCount) {
                return "\(base) · \(ReadingTimeEstimator.localizedRemainingText(minutes: remainingMin))"
            }
            return base
        }()

        syncBottomBarState(with: locator)

        // Update Watch progress
        if !isReadingProgressPersistenceSuppressed {
            publishWatchProgress(locator)
        }
    }

    private func publishWatchProgress(_ locator: Locator) {
        guard isReadingWindowActive else { return }
        WatchPageTurnService.shared.updateProgress(
            title: publication.metadata.title ?? "",
            progression: locator.locations.totalProgression
        )
    }

    // MARK: - Highlights

    let highlights: HighlightRepository?
    private var highlightContextMenu: UIHostingController<HighlightContextMenu>?
    private let highlightDecorationGroup = "highlights"
    private var currentHighlightCancellable: AnyCancellable?

    func saveHighlight(_ highlight: Highlight) {
        guard let highlights = highlights else { return }

        Task {
            do {
                let currentCount = try await highlights.totalCount()
                let decision = NotesQuota.evaluateAdd(
                    currentCount: currentCount,
                    hasProAccess: ProPurchaseManager.shared.hasProAccess
                )

                if case .blocked = decision {
                    await MainActor.run {
                        presentHighlightLimitPaywall()
                    }
                    return
                }

                try await highlights.add(highlight)
                PostHogAnalytics.shared.capture("highlight_created", properties: [
                    "color": "\(highlight.color)"
                ])

                await MainActor.run {
                    switch decision {
                    case .allowWithWarning(let remaining):
                        let message = String(
                            format: NSLocalizedString("reader_highlight_quota_warning", comment: ""),
                            remaining
                        )
                        toast(message, on: view, duration: 2)
                    case .allow, .blocked:
                        toast(NSLocalizedString("reader_highlight_success_message", comment: "Success message when adding a highlight"), on: view, duration: 1)
                    }
                }
            } catch {
                print(error)
                await MainActor.run {
                    toast(NSLocalizedString("reader_highlight_failure_message", comment: "Error message when adding a new highlight failed"), on: view, duration: 2)
                }
            }
        }
    }

    private func presentHighlightLimitPaywall() {
        let limit = ProPurchaseManager.freeHighlightLimit
        let alert = UIAlertController(
            title: NSLocalizedString("reader_highlight_limit_title", comment: ""),
            message: String(
                format: NSLocalizedString("reader_highlight_limit_message", comment: ""),
                limit
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("reader_highlight_limit_upgrade", comment: ""),
            style: .default
        ) { [weak self] _ in
            guard let self else { return }
            Analytics.shared.log(.paywallViewed(source: "notes_limit"))
            let paywall = UIHostingController(rootView: PaywallView())
            paywall.modalPresentationStyle = .formSheet
            self.present(paywall, animated: true)
        })
        present(alert, animated: true)
    }

    func updateHighlight(_ highlightID: Highlight.Id, withColor color: HighlightColor) {
        guard let highlights = highlights else { return }

        Task {
            try! await highlights.update(highlightID, color: color)
        }
    }

    func updateHighlightNote(_ highlightID: Highlight.Id, note: String?) {
        guard let highlights = highlights else { return }

        Task {
            try! await highlights.update(highlightID, note: note)
        }
    }

    func deleteHighlight(_ highlightID: Highlight.Id) {
        guard let highlights = highlights else { return }

        Task {
            try! await highlights.remove(highlightID)
        }
    }

    private func addHighlightDecorationsObserverOnce() {
        if highlights == nil { return }

        if let decorator = navigator as? DecorableNavigator {
            decorator.observeDecorationInteractions(inGroup: highlightDecorationGroup) { [weak self] event in
                self?.activateDecoration(event)
            }
        }
    }

    private func updateHighlightDecorations() {
        guard let highlights = highlights else { return }

        highlights.all(for: bookId)
            .assertNoFailure()
            .sink { [weak self] highlights in
                if let self = self, let decorator = self.navigator as? DecorableNavigator {
                    let decorations = highlights.map { Decoration(id: $0.id!.string, locator: $0.locator, style: .highlight(tint: $0.color.uiColor, isActive: false)) }
                    decorator.apply(decorations: decorations, in: self.highlightDecorationGroup)
                }
            }
            .store(in: &subscriptions)
    }

    private func activateDecoration(_ event: OnDecorationActivatedEvent) {
        guard let highlights = highlights else { return }

        let id = event.decoration.highlightID
        currentHighlightCancellable = highlights.highlight(for: id).sink { _ in
        } receiveValue: { [weak self] highlight in
            guard let self = self else { return }
            self.activateDecoration(for: highlight, on: event)
        }
    }

    private func activateDecoration(for highlight: Highlight, on event: OnDecorationActivatedEvent) {
        highlightContextMenu?.dismiss(animated: false)
        highlightContextMenu = nil

        let highlightID = event.decoration.highlightID
        let quotedText = highlight.locator.text.sanitized().highlight ?? ""
        let existingNote = highlight.note ?? ""

        let menuView = HighlightContextMenu(
            colors: [.yellow, .green, .blue, .red],
            selectedColor: highlight.color,
            hasNote: !existingNote.isEmpty,
            showsNoteButton: true,
            showsCopyButton: !quotedText.isEmpty,
            showsPostcardButton: !quotedText.isEmpty && !publication.isProtected,
            showsIntelligenceButton: ReadingIntelligenceEngine.shared.isFeatureAvailable && !quotedText.isEmpty && !publication.isProtected,
            showsDeleteButton: true
        )

        menuView.selectedColorPublisher.sink { [weak self] color in
            self?.currentHighlightCancellable?.cancel()
            self?.updateHighlight(highlightID, withColor: color)
            self?.highlightContextMenu?.dismiss(animated: true, completion: nil)
        }
        .store(in: &subscriptions)

        menuView.selectedNotePublisher.sink { [weak self] _ in
            guard let self else { return }
            self.currentHighlightCancellable?.cancel()
            self.highlightContextMenu?.dismiss(animated: true) {
                self.presentHighlightNoteEditor(
                    for: highlightID,
                    quotedText: quotedText,
                    initialNote: existingNote,
                    initialColor: highlight.color
                )
            }
        }
        .store(in: &subscriptions)

        menuView.selectedCopyPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.currentHighlightCancellable?.cancel()
            UIPasteboard.general.string = quotedText
            self.highlightContextMenu?.dismiss(animated: true) {
                toast(NSLocalizedString("reader_copy", comment: ""), on: self.view, duration: 1.0)
            }
        }
        .store(in: &subscriptions)

        menuView.selectedPostcardPublisher.sink { [weak self] _ in
            guard let self else { return }
            self.currentHighlightCancellable?.cancel()
            let authors = self.publication.metadata.authors.map(\.name).joined(separator: ", ")
            let payload = QuotePostcardPayload(
                quote: quotedText,
                note: existingNote.isEmpty ? nil : existingNote,
                bookTitle: self.publication.metadata.title ?? "PagePilot",
                author: authors.isEmpty ? nil : authors,
                chapterTitle: highlight.locator.title ?? self.navigator.currentLocation?.title,
                date: highlight.created
            )
            self.highlightContextMenu?.dismiss(animated: true) {
                self.presentQuotePostcard(payload)
            }
        }
        .store(in: &subscriptions)

        menuView.selectedIntelligencePublisher.sink { [weak self] _ in
            guard let self else { return }
            self.currentHighlightCancellable?.cancel()
            let task = ReadingIntelligenceTask.explainSelection(
                text: quotedText,
                bookTitle: self.publication.metadata.title ?? "PagePilot",
                chapterTitle: highlight.locator.title ?? self.navigator.currentLocation?.title
            )
            self.highlightContextMenu?.dismiss(animated: true) {
                self.presentReadingIntelligence(task: task)
            }
        }
        .store(in: &subscriptions)

        menuView.selectedDeletePublisher.sink { [weak self] _ in
            self?.currentHighlightCancellable?.cancel()
            self?.deleteHighlight(highlightID)
            self?.highlightContextMenu?.dismiss(animated: true, completion: nil)
        }
        .store(in: &subscriptions)

        let hosting = UIHostingController(rootView: menuView)
        hosting.modalPresentationStyle = .popover
        hosting.preferredContentSize = menuView.preferredSize
        if #available(iOS 16.4, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }

        highlightContextMenu = hosting

        if let popoverController = hosting.popoverPresentationController {
            popoverController.permittedArrowDirections = [.down, .up]
            popoverController.sourceRect = event.rect ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popoverController.sourceView = view
            popoverController.delegate = self
            present(hosting, animated: true, completion: nil)
        }
    }

    func presentHighlightNoteEditor(
        for highlightID: Highlight.Id,
        quotedText: String,
        initialNote: String = "",
        initialColor: HighlightColor = .yellow
    ) {
        let editor = HighlightNoteEditor(
            highlightID: highlightID,
            quotedText: quotedText,
            initialNote: initialNote,
            initialColor: initialColor,
            onColorChange: { [weak self] newColor in
                self?.updateHighlight(highlightID, withColor: newColor)
            },
            onSave: { [weak self] text in
                self?.dismiss(animated: true)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.updateHighlightNote(highlightID, note: trimmed.isEmpty ? nil : trimmed)
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hosting = UIHostingController(rootView: editor)
        hosting.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : .pageSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(hosting, animated: true)
    }
}

extension Decoration {
    var highlightID: Highlight.Id {
        Highlight.Id(string: id)!
    }
}

extension VisualReaderViewController: VolumeKeyBehaviorProvider {
    var volumeKeyBehavior: VolumeKeyBehavior {
        if quickPositionJumpController?.isActive == true {
            return .controlVolume
        }
        // Keep the hardware buttons as volume control while TTS is speaking.
        if let tts = ttsViewModel, tts.state.isPlaying {
            return .controlVolume
        }
        return .turnPage
    }
}

#if targetEnvironment(macCatalyst)
/// Keeps pointer scrolling separate from Readium's touch and text-selection gestures.
@MainActor
private final class MacScrollPageTurnController: NSObject, UIGestureRecognizerDelegate {
    private let canTurn: () -> Bool
    private let onTurn: (CGPoint) -> Void
    private let wheel = UIPanGestureRecognizer()
    private let trackpad = UIPanGestureRecognizer()
    private var trackpadSession = TrackpadPageTurnSession()
    private var lastWheelTurn: TimeInterval = 0

    init(view: UIView, canTurn: @escaping () -> Bool, onTurn: @escaping (CGPoint) -> Void) {
        self.canTurn = canTurn
        self.onTurn = onTurn
        super.init()
        wheel.allowedScrollTypesMask = .discrete
        trackpad.allowedScrollTypesMask = .continuous
        for gesture in [wheel, trackpad] {
            gesture.allowedTouchTypes = []
            gesture.delegate = self
            gesture.addTarget(self, action: #selector(handleScroll(_:)))
            view.addGestureRecognizer(gesture)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        canTurn()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer
            && otherGestureRecognizer !== wheel && otherGestureRecognizer !== trackpad
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        if gesture === trackpad {
            if let turn = trackpadSession.update(
                state: canTurn() ? gesture.state : .cancelled,
                translation: translation
            ) {
                onTurn(turn)
            }
            return
        }
        guard [.began, .changed, .ended].contains(gesture.state), canTurn(),
              max(abs(translation.x), abs(translation.y)) >= 12
        else { return }
        // Limit a fast wheel burst without losing subsequent deliberate turns.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastWheelTurn >= 0.25 else { return }
        lastWheelTurn = now
        gesture.setTranslation(.zero, in: gesture.view)
        onTurn(translation)
    }
}
#endif

/// A continuous two-finger swipe may turn once, including its final displacement.
struct TrackpadPageTurnSession {
    private var isActive = false
    private var didTurn = false

    mutating func update(state: UIGestureRecognizer.State, translation: CGPoint) -> CGPoint? {
        switch state {
        case .began:
            isActive = true
            didTurn = false
        case .changed, .ended:
            break
        default:
            isActive = false
            return nil
        }
        defer {
            if state == .ended { isActive = false }
        }
        guard isActive, !didTurn, max(abs(translation.x), abs(translation.y)) >= 48 else {
            return nil
        }
        didTurn = true
        return translation
    }
}

// MARK: - Floating Reader Bottom Control Bar

@MainActor
final class ReaderBottomBarModel: ObservableObject {
    @Published var chapterTitle: String = ""
    @Published var positionText: String = ""
    @Published var percentageText: String = ""
    @Published var remainingTimeText: String = ""
    @Published var progress: Double = 0
    @Published var totalPositions: Int = 0
    @Published var currentPositionIndex: Int = 0
    @Published var supportsQuickTheme: Bool = false
    @Published var activePaperPreset: ReaderPaperPreset? = .morningPaper
    @Published var themeIconName: String = "sun.max"
    @Published var themeLabel: String = NSLocalizedString("reader_bar_theme", comment: "")
    @Published var supportsTTS: Bool = false
    @Published var isTTSPlaying: Bool = false
    @Published var isHandsFreeMode: Bool = false
    @Published var supportsIntelligence: Bool = false
    @Published var isDarkChrome: Bool = false
}

struct ReaderBottomControlBar: View {
    @ObservedObject var model: ReaderBottomBarModel
    let onOutline: () -> Void
    let onAppearance: () -> Void
    let onSelectPaperPreset: (ReaderPaperPreset) -> Void
    let onToggleHandsFree: () -> Void
    let onToggleTTS: () -> Void
    let onIntelligenceRecap: () -> Void
    let onIntelligenceSummary: () -> Void
    let onScrubPreview: (Int) -> Void
    let onScrubCommit: (Int) -> Void

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var lastHapticIndex: Int = -1

    private var canScrub: Bool {
        model.totalPositions > 1
    }

    var body: some View {
        VStack(spacing: 10) {
            // Chapter title + remaining reading time & percentage + scrubber
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.chapterTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    HStack(spacing: 5) {
                        if !model.remainingTimeText.isEmpty {
                            Text(model.remainingTimeText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else if !model.positionText.isEmpty {
                            Text(model.positionText)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if !model.percentageText.isEmpty {
                            Text(model.percentageText)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.accentBlue)
                        }
                    }
                    .monospacedDigit()
                }

                if canScrub {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubValue : Double(model.currentPositionIndex) },
                            set: { newValue in
                                scrubValue = newValue
                                let idx = max(0, min(model.totalPositions - 1, Int(newValue.rounded())))
                                if idx != lastHapticIndex {
                                    lastHapticIndex = idx
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                                onScrubPreview(idx)
                            }
                        ),
                        in: 0...Double(max(1, model.totalPositions - 1)),
                        onEditingChanged: { editing in
                            if editing {
                                isScrubbing = true
                                scrubValue = Double(model.currentPositionIndex)
                                lastHapticIndex = model.currentPositionIndex
                            } else {
                                let targetIndex = max(0, min(model.totalPositions - 1, Int(scrubValue.rounded())))
                                isScrubbing = false
                                onScrubCommit(targetIndex)
                            }
                        }
                    )
                    .tint(AppColors.accentBlue)
                }
            }

            // 1-Tap 4 Curated Paper Presets strip (Morning Paper / Sepia / E-Ink / Midnight)
            if model.supportsQuickTheme {
                HStack(spacing: 6) {
                    ForEach(ReaderPaperPreset.allCases) { preset in
                        let isSelected = model.activePaperPreset == preset
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelectPaperPreset(preset)
                        } label: {
                            Text(preset.localizedTitle)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(preset.swiftUITextColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(preset.swiftUIBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(
                                            isSelected ? AppColors.accentBlue : Color.primary.opacity(0.14),
                                            lineWidth: isSelected ? 1.8 : 0.6
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
                .opacity(0.45)

            // Action row (Contents / Appearance / Hands-Free Bedside / Listen)
            HStack(spacing: 4) {
                barActionButton(
                    icon: "list.bullet",
                    title: NSLocalizedString("reader_bar_contents", comment: ""),
                    isActive: false,
                    action: onOutline
                )

                barActionButton(
                    icon: "textformat.size",
                    title: NSLocalizedString("reader_bar_appearance", comment: ""),
                    isActive: false,
                    action: onAppearance
                )

                barActionButton(
                    icon: model.isHandsFreeMode ? "lock.fill" : "moon.stars",
                    title: NSLocalizedString("reader_bar_handsfree", comment: ""),
                    isActive: model.isHandsFreeMode,
                    accentColor: AppColors.accentTeal,
                    action: onToggleHandsFree
                )

                if model.supportsTTS {
                    barActionButton(
                        icon: model.isTTSPlaying ? "waveform" : "headphones",
                        title: NSLocalizedString("reader_bar_listen", comment: ""),
                        isActive: model.isTTSPlaying,
                        action: onToggleTTS
                    )
                }

                if model.supportsIntelligence {
                    Menu {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onIntelligenceRecap()
                        } label: {
                            Label(
                                NSLocalizedString("ai_recap_title", comment: ""),
                                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                            )
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onIntelligenceSummary()
                        } label: {
                            Label(
                                NSLocalizedString("ai_chapter_summary_title", comment: ""),
                                systemImage: "text.document"
                            )
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.accentGradient)
                                .frame(height: 22)

                            Text(NSLocalizedString("ai_bar_short_label", comment: ""))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(NSLocalizedString("ai_badge_apple_intelligence", comment: ""))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    model.isDarkChrome ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(model.isDarkChrome ? 0.42 : 0.14), radius: 22, y: 10)
        .environment(\.colorScheme, model.isDarkChrome ? .dark : .light)
    }

    private func barActionButton(
        icon: String,
        title: String,
        isActive: Bool,
        accentColor: SwiftUI.Color = AppColors.accentBlue,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive ? accentColor : .primary)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isActive ? accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
