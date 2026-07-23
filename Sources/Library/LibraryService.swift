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

/// The Library service is used to:
///
/// - Import new publications (`Book` in the database).
/// - Remove existing publications from the bookshelf.
/// - Open publications for presentation in a navigator.
final class LibraryService: Loggable {
    private let books: BookRepository
    private let readium: Readium
    private let lcp: LCPModuleAPI

    init(books: BookRepository, readium: Readium, lcp: LCPModuleAPI) {
        self.books = books
        self.readium = readium
        self.lcp = lcp
    }

    func allBooks() -> AnyPublisher<[Book], Error> {
        books.all()
    }

    // MARK: Opening

    /// Opens the Readium 2 Publication for the given `book`.
    func openBook(_ book: Book, sender: UIViewController) async throws -> Publication? {
        let (pub, _) = try await openPublication(at: book.absoluteURL(), allowUserInteraction: true, sender: sender)
        guard try checkIsReadable(publication: pub) else {
            return nil
        }
        return pub
    }

    /// Opens the Readium 2 Publication at the given `url`.
    private func openPublication(
        at url: AbsoluteURL,
        allowUserInteraction: Bool,
        sender: UIViewController?
    ) async throws -> (Publication, Format) {
        do {
            let asset = try await readium.assetRetriever.retrieve(url: url).get()

            let publication = try await readium.publicationOpener.open(
                asset: asset,
                allowUserInteraction: allowUserInteraction,
                sender: sender
            ).get()

            return (publication, asset.format)

        } catch {
            throw LibraryError.openFailed(error)
        }
    }

    /// Checks if the publication is not still locked by a DRM.
    private func checkIsReadable(publication: Publication) throws -> Bool {
        guard !publication.isRestricted else {
            if let error = publication.protectionError {
                throw LibraryError.publicationIsRestricted(error)
            } else {
                return false
            }
        }

        return true
    }

    // MARK: Importation

    /// Imports a bunch of publications.
    func importPublications(from sourceURLs: [URL], sender: UIViewController) async throws {
        try await ensureCanImport(additionalBookCount: sourceURLs.count)

        for url in sourceURLs {
            guard let url = url.anyURL.absoluteURL else {
                continue
            }
            try await importPublication(from: url, sender: sender, progress: { _ in })
        }
    }

    ///
    /// Imports the publication at the given `url` to the bookshelf.
    ///
    /// If the `url` is a local file URL, the publication is copied to
    /// Documents/ first.
    ///
    /// DRM services are used to fulfill the publication, in case the URL
    /// locates a licensing document.
    @discardableResult
    func importPublication(
        from url: AbsoluteURL,
        sender: UIViewController? = nil,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> Book {
        try await ensureCanImport(additionalBookCount: 1)

        // Necessary to read URL exported from the Files app, for example.
        let shouldRelinquishAccess = url.url.startAccessingSecurityScopedResource()
        defer {
            if shouldRelinquishAccess {
                url.url.stopAccessingSecurityScopedResource()
            }
        }

        var url = url

        // Convert TXT files to EPUB before importing
        if let file = url.fileURL, file.url.pathExtension.lowercased() == "txt" {
            let epubURL = try TXTToEPUBConverter.convert(from: file.url)
            guard let converted = epubURL.anyURL.absoluteURL else {
                throw LibraryError.importFailed(TXTToEPUBConverter.ConversionError.invalidOutputURL)
            }
            url = converted
        }

        if let file = url.fileURL {
            url = try await fulfillIfNeeded(file, progress: progress)
        }

        let (pub, format) = try await openPublication(at: url, allowUserInteraction: false, sender: sender)
        let title = pub.metadata.title ?? url.url.deletingPathExtension().lastPathComponent
        let coverPath = try await importCover(of: pub)

        var movedFileURL: FileURL?
        if let file = url.fileURL {
            let moved = try moveToDocuments(
                from: file,
                title: title,
                format: format
            )
            movedFileURL = moved
            url = moved
        }

        do {
            return try await insertBook(
                at: url,
                publication: pub,
                mediaType: format.mediaType,
                title: title,
                coverPath: coverPath
            )
        } catch {
            // Compensating cleanup: DB insert failed, remove the files we
            // just wrote so nothing orphaned remains.
            if let movedFileURL {
                try? FileManager.default.removeItem(at: movedFileURL.url)
            }
            if let coverPath,
               let coverURL = Paths.covers.appendingPath(coverPath, isDirectory: false).url as URL?
            {
                try? FileManager.default.removeItem(at: coverURL)
            }
            throw error
        }
    }

    /// Fast-fail UX check: rejects obviously over-limit batches before any
    /// work begins. The atomic guarantee is in `BookRepository.addIfWithinLimit`.
    private func ensureCanImport(additionalBookCount: Int) async throws {
        guard additionalBookCount > 0, !ProPurchaseManager.shared.hasProAccess else {
            return
        }

        let currentBookCount = try await books.count()
        guard currentBookCount + additionalBookCount <= ProPurchaseManager.freeBookLimit else {
            throw LibraryError.bookLimitReached
        }
    }

    /// Fulfills the given `url` if it's a DRM license file.
    private func fulfillIfNeeded(_ url: FileURL, progress: @escaping (Double) -> Void) async throws -> FileURL {
        guard lcp.canFulfill(url) else {
            return url
        }

        do {
            let pub = try await lcp.fulfill(url, progress: progress)
            return pub.localURL
        } catch {
            throw LibraryError.downloadFailed(error)
        }
    }

    /// Moves the given `sourceURL` to the user Documents/ directory.
    private func moveToDocuments(from source: FileURL, title: String, format: Format) throws -> FileURL {
        let destination = Paths.makeDocumentURL(title: title, format: format)

        do {
            // If the source file is part of the app folder, we can move it. Otherwise we make a
            // copy, to avoid deleting files from iCloud, for example.
            if Paths.isAppFile(at: source) {
                try FileManager.default.moveItem(at: source.url, to: destination.url)
            } else {
                try FileManager.default.copyItem(at: source.url, to: destination.url)
            }
            return destination
        } catch {
            throw LibraryError.importFailed(error)
        }
    }

    /// Imports the publication cover and return its path relative to the Covers/ folder.
    private func importCover(of publication: Publication) async throws -> String? {
        do {
            guard let cover = try await publication.cover().get()?.pngData() else {
                return nil
            }
            let coverURL = Paths.covers.appendingUniquePathComponent()

            try cover.write(to: coverURL.url)
            return coverURL.lastPathSegment
        } catch {
            throw LibraryError.importFailed(error)
        }
    }

    /// Inserts the given `book` in the bookshelf.
    private func insertBook(
        at url: AbsoluteURL,
        publication: Publication,
        mediaType: MediaType?,
        title: String,
        coverPath: String?
    ) async throws -> Book {
        // Makes the URL relative to the Documents/ folder if possible.
        let url: AnyURL = Paths.documents.relativize(url)?.anyURL ?? url.anyURL

        let book = Book(
            identifier: publication.metadata.identifier,
            title: title,
            authors: publication.metadata.authors
                .map(\.name)
                .joined(separator: ", "),
            type: mediaType?.string ?? MediaType.binary.string,
            url: url,
            coverPath: coverPath
        )

        do {
            let id = try await books.addIfWithinLimit(
                book,
                limit: ProPurchaseManager.freeBookLimit,
                hasProAccess: ProPurchaseManager.shared.hasProAccess
            )
            return Book(
                id: id,
                identifier: book.identifier,
                title: book.title,
                authors: book.authors,
                type: book.type,
                url: url,
                coverPath: book.coverPath,
                locator: book.locator,
                created: book.created,
                preferencesJSON: book.preferencesJSON
            )
        } catch {
            throw LibraryError.importFailed(error)
        }
    }

    // MARK: Removing

    func remove(_ book: Book) async throws {
        guard let id = book.id else {
            throw LibraryError.bookDeletionFailed(nil)
        }

        let bookFileURL = try? book.absoluteURL().fileURL
        let coverURL = book.cover?.url

        // Move book file and cover to a temporary Trash location before
        // touching the database. If the DB delete fails we move them back.
        var trashedBookURL: URL?
        if let bookFileURL, Paths.documents.isParent(of: bookFileURL) {
            let trash = Paths.temporary.appendingPath("Trash", isDirectory: true)
            try? FileManager.default.createDirectory(at: trash.url, withIntermediateDirectories: true)
            let dest = trash.appendingUniquePathComponent(bookFileURL.lastPathSegment)
            try? FileManager.default.moveItem(at: bookFileURL.url, to: dest.url)
            trashedBookURL = dest.url
        }

        var trashedCoverURL: URL?
        if let coverURL, (try? coverURL.checkResourceIsReachable()) ?? false {
            let trash = Paths.temporary.appendingPath("Trash", isDirectory: true)
            try? FileManager.default.createDirectory(at: trash.url, withIntermediateDirectories: true)
            let dest = trash.appendingUniquePathComponent()
            try? FileManager.default.moveItem(at: coverURL, to: dest.url)
            trashedCoverURL = dest.url
        }

        do {
            try await books.remove(id)
            // DB delete succeeded; purge the trashed files.
            if let trashedBookURL { try? FileManager.default.removeItem(at: trashedBookURL) }
            if let trashedCoverURL { try? FileManager.default.removeItem(at: trashedCoverURL) }
        } catch {
            // DB delete failed; restore files from trash.
            if let trashedBookURL, let bookFileURL {
                try? FileManager.default.moveItem(at: trashedBookURL, to: bookFileURL.url)
            }
            if let trashedCoverURL, let coverURL {
                try? FileManager.default.moveItem(at: trashedCoverURL, to: coverURL)
            }
            throw LibraryError.bookDeletionFailed(error)
        }
    }

    /// Scans Documents/ and Covers/ for files not referenced by any Book row
    /// and removes them. Call at app launch to clean up historical orphans
    /// left by crashed imports or failed deletes.
    func cleanOrphanedFiles() async {
        do {
            let allBooks = try await books.allOnce()
            let usedBookFiles = Set(allBooks.compactMap { $0.url })
            let usedCovers = Set(allBooks.compactMap { $0.coverPath })

            cleanOrphans(in: Paths.documents.url, usedRelativePaths: usedBookFiles)
            cleanOrphans(in: Paths.covers.url, usedRelativePaths: usedCovers)
        } catch {
            // Best-effort cleanup; don't crash on failure.
        }
    }

    private func cleanOrphans(in directory: URL, usedRelativePaths: Set<String>) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in entries {
            let name = file.lastPathComponent
            if !usedRelativePaths.contains(name) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

private extension Book {
    func absoluteURL() throws -> AbsoluteURL {
        guard let url = AnyURL(string: url) else {
            throw LibraryError.bookNotFound
        }

        switch url {
        case let .absolute(url):
            return url

        case let .relative(relativeURL):
            // Path relative to Documents/.
            guard let url = Paths.documents.resolve(relativeURL) else {
                throw LibraryError.bookNotFound
            }
            return url
        }
    }
}
