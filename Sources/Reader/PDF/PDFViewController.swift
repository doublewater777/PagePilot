//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

final class PDFViewController: VisualReaderViewController<PDFNavigatorViewController> {
    private let preferencesStore: AnyUserPreferencesStore<PDFPreferences>

    /// PDF positions are real page numbers, so the footer shows "x / y".
    override var positionsArePages: Bool { true }

    init(
        publication: Publication,
        locator: Locator?,
        bookId: Book.Id,
        books: BookRepository,
        bookmarks: BookmarkRepository,
        highlights: HighlightRepository,
        initialPreferences: PDFPreferences,
        preferencesStore: AnyUserPreferencesStore<PDFPreferences>
    ) throws {
        self.preferencesStore = preferencesStore

        let navigator = try PDFNavigatorViewController(
            publication: publication,
            initialLocation: locator,
            config: PDFNavigatorViewController.Configuration(
                preferences: initialPreferences
            )
        )

        super.init(navigator: navigator, publication: publication, bookId: bookId, books: books, bookmarks: bookmarks, highlights: highlights)

        navigator.delegate = self
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
                vc.preferredContentSize = CGSize(width: 390, height: 480)
                if let popover = vc.popoverPresentationController {
                    popover.sourceView = anchor
                    popover.sourceRect = CGRect(x: anchor.bounds.midX, y: anchor.bounds.minY, width: 1, height: 1)
                    popover.permittedArrowDirections = [.down, .up]
                }
            } else {
                vc.modalPresentationStyle = .pageSheet
                if let sheet = vc.sheetPresentationController {
                    let previewId = UISheetPresentationController.Detent.Identifier("pdfPreview")
                    let previewDetent = UISheetPresentationController.Detent.custom(identifier: previewId) { context in
                        min(420, context.maximumDetentValue * 0.52)
                    }
                    sheet.detents = [previewDetent, .large()]
                    sheet.selectedDetentIdentifier = previewId
                    sheet.largestUndimmedDetentIdentifier = previewId
                    sheet.prefersGrabberVisible = true
                }
            }
            vc.configureReaderPanelKeyboard()
            present(vc, animated: true)
            } catch {
                moduleDelegate?.presentError(UserError(error), from: self)
            }
        }
    }
}

extension PDFViewController: PDFNavigatorDelegate {}
