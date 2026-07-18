//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit

/// The Library module handles the presentation of the bookshelf, and the publications' management.
protocol LibraryModuleAPI {
    var delegate: LibraryModuleDelegate? { get }

    /// Root navigation controller containing the Library.
    /// Can be used to present the library to the user.
    var rootViewController: UINavigationController { get }

    /// Imports a new publication to the library, either from:
    /// - a local file URL
    /// - a remote URL which will be streamed
    @discardableResult
    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController?,
        progress: @escaping (Double) -> Void
    ) async throws -> Book

    /// Opens a book for reading and presents it to the user.
    func openBook(_ book: Book, sender: UIViewController) async throws -> Publication?
}

protocol LibraryModuleDelegate: ModuleDelegate {
    /// Called when the user tap on a publication in the library.
    func libraryDidSelectPublication(_ publication: Publication, book: Book)
}

final class LibraryModule: LibraryModuleAPI {
    weak var delegate: LibraryModuleDelegate?

    private let lcp: LCPModuleAPI
    private let library: LibraryService
    private let factory: LibraryFactory
    private var subscriptions = Set<AnyCancellable>()

    init(
        delegate: LibraryModuleDelegate?,
        books: BookRepository,
        opdsFeeds: OPDSFeedRepository,
        readium: Readium
    ) {
        lcp = LCPModule(readium: readium)
        library = LibraryService(books: books, readium: readium, lcp: lcp)
        factory = LibraryFactory(libraryService: library, opdsFeeds: opdsFeeds)
        self.delegate = delegate
    }

    private(set) lazy var rootViewController: UINavigationController = {
        let nav = UINavigationController(rootViewController: libraryViewController)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemGroupedBackground
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        return nav
    }()

    private lazy var libraryViewController: LibraryViewController = {
        let library: LibraryViewController = factory.make()
        library.libraryDelegate = delegate
        return library
    }()

    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController?,
        progress: @escaping (Double) -> Void
    ) async throws -> Book {
        try await library.importPublication(from: url, sender: sender, progress: progress)
    }

    func openBook(_ book: Book, sender: UIViewController) async throws -> Publication? {
        try await library.openBook(book, sender: sender)
    }
}

extension LibraryModuleAPI {
    @discardableResult
    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController? = nil,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> Book {
        try await importPublication(from: url, sender: sender, progress: progress)
    }
}
