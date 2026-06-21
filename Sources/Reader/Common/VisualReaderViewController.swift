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

/// Base class for the reader view controller of a `VisualNavigator`.
class VisualReaderViewController<N: UIViewController & Navigator>: ReaderViewController<N>, VisualNavigatorDelegate {
    private lazy var positionLabel = UILabel()

    private var ttsViewModel: TTSViewModel?
    private var ttsControlsViewController: UIHostingController<TTSControls>?
    private var positionCount: Int?

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

        Task {
            self.positionCount = try? await publication.positions().get().count
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
        DirectionalNavigationAdapter(
            pointerPolicy: .init(types: [.mouse, .touch])
        ).bind(to: navigator)

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

        view.backgroundColor = .white

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ShowNavigationBar") {
            navigationBarHidden = false
        }
        #endif

        updateNavigationBar(animated: false)

        addChild(navigator)
        navigator.view.frame = view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigator.view)
        navigator.didMove(toParent: self)

        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.font = .systemFont(ofSize: 12)
        positionLabel.textColor = .darkGray
        // Prevents VoiceOver from selecting the position label while reading
        // the page.
        positionLabel.isAccessibilityElement = false

        view.addSubview(positionLabel)
        NSLayoutConstraint.activate([
            positionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            positionLabel.bottomAnchor.constraint(equalTo: navigator.view.bottomAnchor, constant: -20),
        ])

        Task { [weak self] in
            guard let self = self else { return }

            let ttsVM = TTSViewModel(navigator: self.navigator, publication: self.publication)

            await MainActor.run {
                self.ttsViewModel = ttsVM
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
                        controls.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20),
                    ])
                    controls.didMove(toParent: self)

                    ttsViewModel.$state
                        .receive(on: DispatchQueue.main)
                        .sink { state in
                            controls.view.isHidden = !state.showControls
                        }
                        .store(in: &self.subscriptions)

                    // Refresh navigation bar to display TTS button now that the view model is ready
                    self.navigationItem.rightBarButtonItems = self.makeNavigationBarButtons()
                }
            }
        }

        // Register with WatchPageTurnService for remote page turn control
        WatchPageTurnService.shared.activate()
        if let visualNavigator = navigator as? VisualNavigator {
            WatchPageTurnService.shared.registerNavigator(visualNavigator, publication: publication)
        }

        // Navigate to locator from external trigger (e.g. MyNotes)
        if let visualNavigator = navigator as? VisualNavigator,
           let target = AppModule.shared?.pendingNavigationTarget,
           target.bookId == bookId {
            AppModule.shared?.pendingNavigationTarget = nil
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await visualNavigator.go(to: target.locator, options: NavigatorGoOptions(animated: false))
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        VolumeKeyService.shared.register(self)
        VolumeKeyService.shared.onPageForward = { [weak self] in
            guard let navigator = self?.navigator as? VisualNavigator else { return }
            Task { await navigator.goForward(options: NavigatorGoOptions(animated: false)) }
        }
        VolumeKeyService.shared.onPageBackward = { [weak self] in
            guard let navigator = self?.navigator as? VisualNavigator else { return }
            Task { await navigator.goBackward(options: NavigatorGoOptions(animated: false)) }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        VolumeKeyService.shared.unregister(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        ttsViewModel?.stop()
        WatchPageTurnService.shared.unregisterNavigator()
    }

    // MARK: - Navigation bar

    private var navigationBarHidden: Bool = true {
        didSet {
            updateNavigationBar()
        }
    }

    override func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = super.makeNavigationBarButtons()

        // Text to speech
        if let ttsViewModel = ttsViewModel {
            buttons.append(UIBarButtonItem(image: UIImage(systemName: "speaker.wave.2.fill"), style: .plain, target: ttsViewModel, action: #selector(TTSViewModel.start)))
        }

        return buttons
    }

    func toggleNavigationBar() {
        navigationBarHidden = !navigationBarHidden
    }

    func updateNavigationBar(animated: Bool = true) {
        navigationController?.setNavigationBarHidden(navigationBarHidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersStatusBarHidden: Bool {
        navigationBarHidden
    }

    // MARK: - VisualNavigatorDelegate

    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)

        positionLabel.text = {
            if let positionCount = positionCount, let position = locator.locations.position {
                return "\(position) / \(positionCount)"
            } else if let progression = locator.locations.totalProgression {
                return "\(progression)%"
            } else {
                return nil
            }
        }()

        // Update Watch progress
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
                try await highlights.add(highlight)
                toast(NSLocalizedString("reader_highlight_success_message", comment: "Success message when adding a bookmark"), on: view, duration: 1)
            } catch {
                print(error)
                toast(NSLocalizedString("reader_highlight_failure_message", comment: "Error message when adding a new bookmark failed"), on: view, duration: 2)
            }
        }
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
        if highlightContextMenu != nil {
            highlightContextMenu?.removeFromParent()
        }

        let menuView = HighlightContextMenu(colors: [.red, .green, .blue, .yellow],
                                            systemFontSize: 20)

        menuView.selectedColorPublisher.sink { [weak self] color in
            self?.currentHighlightCancellable?.cancel()
            self?.updateHighlight(event.decoration.highlightID, withColor: color)
            self?.highlightContextMenu?.dismiss(animated: true, completion: nil)
        }
        .store(in: &subscriptions)

        menuView.selectedDeletePublisher.sink { [weak self] _ in
            self?.currentHighlightCancellable?.cancel()
            self?.deleteHighlight(event.decoration.highlightID)
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
            popoverController.permittedArrowDirections = .down
            popoverController.sourceRect = event.rect ?? .zero
            popoverController.sourceView = view
            popoverController.delegate = self
            present(hosting, animated: true, completion: nil)
        }
    }
}

extension Decoration {
    var highlightID: Highlight.Id {
        Highlight.Id(string: id)!
    }
}

extension VisualReaderViewController: VolumeKeyBehaviorProvider {
    var volumeKeyBehavior: VolumeKeyBehavior {
        // Keep the hardware buttons as volume control while TTS is speaking.
        if let tts = ttsViewModel, tts.state.isPlaying {
            return .controlVolume
        }
        return .turnPage
    }
}


