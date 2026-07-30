//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Decides whether a file on disk is an orphan that can be safely deleted.
///
/// Extracted from `LibraryService.cleanOrphanedFiles()` so the comparison
/// rules — standardized absolute URLs instead of raw `Book.url` strings, and
/// a creation-date grace period — are unit-testable.
enum OrphanedFilePolicy {
    /// Minimum age before an unreferenced file may be deleted. Files younger
    /// than this may belong to an import whose database row was not yet part
    /// of the snapshot the cleanup ran against.
    static let defaultGracePeriod: TimeInterval = 24 * 60 * 60

    /// Standardized absolute URLs of every book file in `books`.
    ///
    /// Resolving through `Book.absoluteFileURL()` (instead of comparing raw
    /// `Book.url` strings to `lastPathComponent`) keeps percent-escaped
    /// names such as `My%20Book.epub` matching the literal on-disk
    /// `My Book.epub`.
    static func referencedBookFileURLs(for books: [Book]) -> Set<URL> {
        Set(
            books
                .compactMap { try? $0.absoluteFileURL() }
                .compactMap { $0?.standardizedFileURL }
        )
    }

    /// Standardized absolute URLs of every cover file in `books`.
    static func referencedCoverURLs(for books: [Book]) -> Set<URL> {
        Set(books.compactMap { $0.cover?.url.standardizedFileURL })
    }

    /// Returns true when `fileURL` is referenced by no book and is older than
    /// `gracePeriod`. A nil `creationDate` cannot prove the file is young, so
    /// it is treated as old.
    static func isOrphan(
        fileURL: URL,
        referencedURLs: Set<URL>,
        creationDate: Date?,
        now: Date,
        gracePeriod: TimeInterval = OrphanedFilePolicy.defaultGracePeriod
    ) -> Bool {
        if referencedURLs.contains(fileURL.standardizedFileURL) {
            return false
        }
        if let creationDate, now.timeIntervalSince(creationDate) < gracePeriod {
            return false
        }
        return true
    }
}
