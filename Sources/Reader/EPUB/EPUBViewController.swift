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
    private var pendingNoteHighlightID: Highlight.Id?
    private let selectionMenuPresenter = ReaderTextSelectionMenuPresenter()
    private var colorPickerPopover: UIHostingController<HighlightContextMenu>?

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

        super.init(navigator: navigator, publication: publication, bookId: bookId, books: books, bookmarks: bookmarks, highlights: highlights)

        navigator.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        selectionMenuPresenter.attach(to: navigator.view, viewController: self)
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
                onClose: { [weak self] in
                    self?.dismiss(animated: true)
                }
            )
            let vc = UIHostingController(rootView: userPrefs)
            vc.modalPresentationStyle = .formSheet
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
            colors: [.red, .green, .blue, .yellow],
            systemFontSize: 20,
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

        let hosting = UIHostingController(rootView: menuView)
        hosting.modalPresentationStyle = .popover
        hosting.preferredContentSize = menuView.preferredSize
        if #available(iOS 16.4, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }

        if let popover = hosting.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = selection.frame ?? .zero
            popover.permittedArrowDirections = .down
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
                    presentNoteEditor(for: highlightID, quotedText: quotedText)
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

    private func presentNoteEditor(for highlightID: Highlight.Id, quotedText: String) {
        pendingNoteHighlightID = highlightID
        let editor = HighlightNoteEditor(
            highlightID: highlightID,
            quotedText: quotedText,
            onSave: { [weak self] text in
                self?.dismiss(animated: true)
                guard let self = self else { return }
                self.updateHighlightNote(highlightID, note: text.trimmingCharacters(in: .whitespacesAndNewlines))
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        let hosting = UIHostingController(rootView: editor)
        hosting.modalPresentationStyle = .formSheet
        present(hosting, animated: true)
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

        let content = (try? clean(content, .none())) ?? ""
        let page =
            """
            <html>
                <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                </head>
                <body>
                    \(content)
                </body>
            </html>
            """

        let wk = WKWebView()
        wk.loadHTMLString(page, baseURL: nil)

        let vc = UIViewController()
        vc.view = wk
        vc.navigationItem.title = title
        vc.navigationItem.leftBarButtonItem = BarButtonItem(barButtonSystemItem: .done, actionHandler: { _ in
            vc.dismiss(animated: true, completion: nil)
        })

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
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
