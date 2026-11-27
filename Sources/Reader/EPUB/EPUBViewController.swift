//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftSoup
import SwiftUI
import UIKit
import WebKit

public extension FontFamily {
    /// Example of adding a custom font embedded in the application.
    static let literata: FontFamily = "Literata"
}

class EPUBViewController: VisualReaderViewController<EPUBNavigatorViewController> {
    private let preferencesStore: AnyUserPreferencesStore<EPUBPreferences>
    private var latestPreferences: EPUBPreferences
    private let selectionMenuPresenter = ReaderTextSelectionMenuPresenter()
    private var colorPickerPopover: UIHostingController<HighlightContextMenu>?

    override var supportsQuickThemeCycle: Bool { true }

    init(
        publication: Publication,
        locator: Locator?,
        bookId: Book.Id,
        books: BookRepository,
        bookmarks: BookmarkRepository,
        highlights: HighlightRepository,
        initialPreferences: EPUBPreferences,
        preferencesStore: AnyUserPreferencesStore<EPUBPreferences>
    ) throws {
        let templates = HTMLDecorationTemplate.defaultTemplates()

        let resources = FileURL(url: Bundle.main.resourceURL!)!

        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: locator,
            config: EPUBNavigatorViewController.Configuration(
                preferences: initialPreferences,
                editingActions: ReaderEditingActions.epubConfiguration,
                decorationTemplates: templates,
                fontFamilyDeclarations: [
                    CSSFontFamilyDeclaration(
                        fontFamily: .literata,
                        fontFaces: [
                            // Literata is a variable font family, so we can provide a font weight range.
                            CSSFontFace(
                                file: resources.appendingPath("Fonts/Literata-VariableFont_opsz,wght.ttf", isDirectory: false),
                                style: .normal, weight: .variable(200 ... 900)
                            ),
                            CSSFontFace(
                                file: resources.appendingPath("Fonts/Literata-Italic-VariableFont_opsz,wght.ttf", isDirectory: false),
                                style: .italic, weight: .variable(200 ... 900)
                            ),
                        ]
                    ).eraseToAnyHTMLFontFamilyDeclaration(),
                ]
            )
        )

        self.preferencesStore = preferencesStore
        self.latestPreferences = initialPreferences

        super.init(navigator: navigator, publication: publication, bookId: bookId, books: books, bookmarks: bookmarks, highlights: highlights)

        navigator.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        selectionMenuPresenter.attach(to: navigator.view, viewController: self)
        applyPreferencesToChrome(latestPreferences)

        preferencesStore.preferencesPublisher(for: bookId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prefs in
                self?.latestPreferences = prefs
                self?.applyPreferencesToChrome(prefs)
            }
            .store(in: &subscriptions)
    }

    private func applyPreferencesToChrome(_ preferences: EPUBPreferences) {
        let appearance = ReaderThemeAppearance.resolve(
            preferences: preferences,
            systemStyle: traitCollection.userInterfaceStyle
        )
        updateReaderThemeAppearance(appearance)

        let activePreset = ReaderPaperPreset.matching(
            preferences: preferences,
            systemStyle: traitCollection.userInterfaceStyle
        )
        updateActivePaperPreset(activePreset)

        let indicatorPreset = activePreset ?? (appearance.isDarkSurface ? .midnightInk : .morningPaper)
        updateQuickThemeIndicator(
            iconName: indicatorPreset.iconName,
            label: indicatorPreset.localizedTitle
        )
    }

    override func applyPaperPreset(_ preset: ReaderPaperPreset) {
        Task {
            do {
                var prefs = try await preferencesStore.preferences(for: bookId)
                preset.apply(to: &prefs)
                try await preferencesStore.savePreferences(prefs, of: bookId)
                await MainActor.run {
                    self.navigator.submitPreferences(prefs)
                    self.latestPreferences = prefs
                    self.applyPreferencesToChrome(prefs)
                }
            } catch {
                moduleDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    override func cycleQuickReaderTheme() {
        let current = ReaderPaperPreset.matching(
            preferences: latestPreferences,
            systemStyle: traitCollection.userInterfaceStyle
        ) ?? .morningPaper
        applyPaperPreset(current.next())
    }

    override func presentUserPreferences() {
        Task {
            do {
                let preferences = try await preferencesStore.preferences(for: bookId)

                let userPrefs = UserPreferences(
                    model: UserPreferencesViewModel(
                        bookId: bookId,
                        preferences: preferences,
                        configurable: navigator,
                        store: preferencesStore
                    ),
                    onClose: {
                        self.dismiss(animated: true)
                    }
                )
                let vc = UIHostingController(rootView: userPrefs)
                let isPad = traitCollection.horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
                if isPad, let anchor = bottomControlBarAnchorView {
                    vc.modalPresentationStyle = .popover
                    vc.preferredContentSize = CGSize(width: 390, height: 540)
                    if let popover = vc.popoverPresentationController {
                        popover.sourceView = anchor
                        popover.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.minY, width: 1, height: 1)
                        popover.permittedArrowDirections = [.down, .up]
                    }
                } else {
                    vc.modalPresentationStyle = .pageSheet
                    if let sheet = vc.sheetPresentationController {
                        let livePreviewId = UISheetPresentationController.Detent.Identifier("readerLivePreview")
                        let livePreviewDetent = UISheetPresentationController.Detent.custom(identifier: livePreviewId) { context in
                            min(460, context.maximumDetentValue * 0.56)
                        }
                        sheet.detents = [livePreviewDetent, .large()]
                        sheet.selectedDetentIdentifier = livePreviewId
                        // Keep the reading canvas bright behind the half-height sheet for live preview.
                        sheet.largestUndimmedDetentIdentifier = livePreviewId
                        sheet.prefersGrabberVisible = true
                        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    }
                }
                vc.configureReaderPanelKeyboard()
                present(vc, animated: true)
            } catch {
                moduleDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    func highlightSelection() {
        guard let selection = navigator.currentSelection else { return }

        colorPickerPopover?.dismiss(animated: false)

        let menuView = HighlightContextMenu(
            colors: [.yellow, .green, .blue, .red],
            showsNoteButton: true,
            showsCopyButton: false,
            showsDeleteButton: false
        )
        menuView.selectedColorPublisher.sink { [weak self] color in
            guard let self else { return }
            let highlight = Highlight(bookId: self.bookId, locator: selection.locator, color: color)
            self.saveHighlight(highlight)
            self.navigator.clearSelection()
            self.colorPickerPopover?.dismiss(animated: true)
            self.colorPickerPopover = nil
        }
        .store(in: &subscriptions)

        menuView.selectedNotePublisher.sink { [weak self] _ in
            guard let self else { return }
            self.colorPickerPopover?.dismiss(animated: true) {
                self.addNoteToSelection()
            }
            self.colorPickerPopover = nil
        }
        .store(in: &subscriptions)

        let hosting = UIHostingController(rootView: menuView)
        hosting.modalPresentationStyle = .popover
        hosting.preferredContentSize = menuView.preferredSize
        if #available(iOS 16.4, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }

        if let popover = hosting.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = selection.frame ?? .zero
            popover.permittedArrowDirections = [.down, .up]
            popover.delegate = self
        }

        colorPickerPopover = hosting
        present(hosting, animated: true)
    }

    func addNoteToSelection() {
        guard let selection = navigator.currentSelection, let highlights = highlights else { return }

        let quotedText = selection.locator.text.sanitized().highlight ?? ""
        let highlight = Highlight(bookId: bookId, locator: selection.locator, color: .yellow)
        Task {
            do {
                let highlightID = try await highlights.add(highlight)
                navigator.clearSelection()
                await MainActor.run {
                    presentHighlightNoteEditor(for: highlightID, quotedText: quotedText)
                }
            } catch {
                await MainActor.run {
                    moduleDelegate?.presentError(UserError(error), from: self)
                }
            }
        }
    }

    func copySelection() async {
        guard let text = navigator.currentSelection?.locator.text.highlight else { return }
        guard await publication.rights.copy(text: text) else {
            moduleDelegate?.presentError(UserError(NavigatorError.copyForbidden), from: self)
            return
        }
        UIPasteboard.general.string = text
        navigator.clearSelection()
    }

    func shareCurrentSelection() {
        guard let text = navigator.currentSelection?.locator.text.highlight else { return }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let presenter = activity.popoverPresentationController {
            presenter.sourceView = view
            presenter.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            presenter.permittedArrowDirections = []
        }
        present(activity, animated: true)
    }

    func presentQuotePostcardForSelection() {
        guard let selection = navigator.currentSelection else { return }
        let quotedText = selection.locator.text.sanitized().highlight
            ?? selection.locator.text.highlight
            ?? ""
        guard !quotedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        navigator.clearSelection()

        let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
        let payload = QuotePostcardPayload(
            quote: quotedText,
            bookTitle: publication.metadata.title ?? "PagePilot",
            author: authors.isEmpty ? nil : authors,
            chapterTitle: selection.locator.title ?? navigator.currentLocation?.title
        )
        presentQuotePostcard(payload)
    }

    func presentIntelligenceForSelection() {
        guard ReadingIntelligenceEngine.shared.isFeatureAvailable,
              let selection = navigator.currentSelection else { return }
        let quotedText = selection.locator.text.sanitized().highlight
            ?? selection.locator.text.highlight
            ?? ""
        let trimmed = quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        navigator.clearSelection()

        let task = ReadingIntelligenceTask.explainSelection(
            text: trimmed,
            bookTitle: publication.metadata.title ?? "PagePilot",
            chapterTitle: selection.locator.title ?? navigator.currentLocation?.title
        )
        presentReadingIntelligence(task: task)
    }

    func performWebViewAction(_ selectors: [String]) {
        guard let webView = findWebView(in: navigator.view) else { return }
        for name in selectors {
            let selector = NSSelectorFromString(name)
            if webView.responds(to: selector) {
                webView.perform(selector)
                return
            }
        }
    }

    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Footnotes

    private func presentFootnote(content: String, referrer: String?) -> Bool {
        var title = referrer
        if let t = title {
            title = try? clean(t, .none())
        }
        if !suitableTitle(title) {
            title = nil
        }

        let appearance = ReaderThemeAppearance.resolve(
            preferences: latestPreferences,
            systemStyle: traitCollection.userInterfaceStyle
        )
        let content = (try? clean(content, .none())) ?? ""
        let page =
            """
            <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <style>
                        body {
                            margin: 0;
                            padding: 20px 22px 32px;
                            background-color: \(appearance.cssHexBackground);
                            color: \(appearance.cssHexText);
                            font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", Georgia, serif;
                            font-size: 16px;
                            line-height: 1.68;
                            -webkit-text-size-adjust: 100%;
                        }
                        p { margin: 0 0 12px; }
                    </style>
                </head>
                <body>
                    \(content)
                </body>
            </html>
            """

        let wk = WKWebView()
        wk.isOpaque = false
        wk.backgroundColor = appearance.backgroundColor
        wk.scrollView.backgroundColor = appearance.backgroundColor
        wk.loadHTMLString(page, baseURL: nil)

        let vc = UIViewController()
        vc.view = wk
        vc.navigationItem.title = title
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            primaryAction: UIAction { _ in
                vc.dismiss(animated: true, completion: nil)
            }
        )

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = UIDevice.current.userInterfaceIdiom == .pad ? .formSheet : .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true, completion: nil)

        return false
    }

    /// This regex matches any string with at least 2 consecutive letters (not limited to ASCII).
    /// It's used when evaluating whether to display the body of a noteref referrer as the note's title.
    /// I.e. a `*` or `1` would not be used as a title, but `on` or `好書` would.
    private lazy var noterefTitleRegex: NSRegularExpression =
        try! NSRegularExpression(pattern: "[\\p{Ll}\\p{Lu}\\p{Lt}\\p{Lo}]{2}")

    /// Checks to ensure the title is non-nil and contains at least 2 letters.
    private func suitableTitle(_ title: String?) -> Bool {
        guard let title = title else { return false }
        let range = NSRange(location: 0, length: title.utf16.count)
        let match = noterefTitleRegex.firstMatch(in: title, range: range)
        return match != nil
    }
}

extension EPUBViewController: EPUBNavigatorDelegate {
    func navigator(_ navigator: Navigator, shouldNavigateToNoteAt link: ReadiumShared.Link, content: String, referrer: String?) -> Bool {
        presentFootnote(content: content, referrer: referrer)
    }

    func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
        selectionMenuPresenter.present(selection: selection)
        return false
    }
}

extension EPUBViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
