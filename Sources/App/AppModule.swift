//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit

/// Base module delegate, that sub-modules' delegate can extend.
/// Provides basic shared functionalities.
protocol ModuleDelegate: AnyObject {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController)
    func presentError<T: UserErrorConvertible>(_ error: T, from viewController: UIViewController)
}

/// Main application module, it:
/// - owns the sub-modules (library, reader, etc.)
/// - orchestrates the communication between its sub-modules, through the modules' delegates.
final class AppModule {
    // App modules
    var library: LibraryModuleAPI!
    var reader: ReaderModuleAPI!
    var home: HomeModuleAPI!

    weak var tabBarController: UITabBarController?

    let readium: Readium

    private let books: BookRepository

    fileprivate lazy var documentPickerDelegate = DocumentPickerDelegate(module: self)

    init() throws {
        let file = Paths.library.appendingPath("database.db", isDirectory: false)
        let db = try Database(file: file.url)
        print("Created database at \(file.path)")

        let bookmarks = BookmarkRepository(db: db)
        let highlights = HighlightRepository(db: db)

        readium = Readium()
        books = BookRepository(db: db)

        library = LibraryModule(
            delegate: self,
            books: books,
            readium: readium
        )

        reader = ReaderModule(
            delegate: self,
            books: books,
            bookmarks: bookmarks,
            highlights: highlights,
            readium: readium
        )

        home = HomeModule(
            delegate: self,
            books: books
        )

        // Set Readium 2's logging minimum level.
        ReadiumEnableLog(withMinimumSeverityLevel: .debug)
    }

}

fileprivate final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    weak var module: AppModule?

    init(module: AppModule) {
        self.module = module
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let module = module else { return }
        guard let absoluteURL = url.anyURL.absoluteURL else { return }
        let vc = module.home.rootViewController

        Task {
            do {
                try await module.library.importPublication(from: absoluteURL, sender: vc, progress: { _ in })
            } catch {
                module.presentError(UserError(error), from: vc)
            }
        }
    }
}

extension AppModule: ModuleDelegate {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let dismissButton = UIAlertAction(title: NSLocalizedString("ok_button", comment: "Alert button"), style: .cancel)
            alert.addAction(dismissButton)
            viewController.present(alert, animated: true)
        }
    }

    func presentError<T: UserErrorConvertible>(_ error: T, from viewController: UIViewController) {
        viewController.alert(error)
    }
}

extension AppModule: LibraryModuleDelegate {
    func libraryDidSelectPublication(_ publication: Publication, book: Book) {
        reader.presentPublication(publication: publication, book: book, in: library.rootViewController)
    }
}

extension AppModule: ReaderModuleDelegate {}

extension AppModule: HomeModuleDelegate {
    func homeDidSelectContinueReading(bookId: Book.Id) {
        Task { @MainActor in
            let nav = home.rootViewController
            do {
                guard let book = try await books.get(bookId) else { return }
                guard let pub = try await library.openBook(book, sender: nav) else { return }
                reader.presentPublication(publication: pub, book: book, in: nav)
            } catch {
                presentError(UserError(error), from: nav)
            }
        }
    }

    func homeDidSelectGoToLibrary() {
        tabBarController?.selectedIndex = 1
    }
}
