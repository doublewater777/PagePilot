//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Picks the book shown on the home "continue reading" card.
enum ContinueReadingSelector {
    /// Prefer most-recently-opened order (`lastReadIds`); fall back to books
    /// that already have progress. Finished books are eligible (reread).
    static func select(from books: [Book], lastReadIds: [Int64]) -> Book? {
        guard !books.isEmpty else { return nil }

        var byId: [Int64: Book] = [:]
        byId.reserveCapacity(books.count)
        for book in books {
            if let id = book.id {
                byId[id.rawValue] = book
            }
        }

        for rawId in lastReadIds {
            if let book = byId[rawId] {
                return book
            }
        }

        // Fallback when MRU list is empty or stale (e.g. after reinstall).
        // `books` is typically ordered by created ascending — take the latest
        // started book, preferring still in-progress over finished.
        let started = books.filter { $0.progression > 0 }
        if let inProgress = started.last(where: { $0.progression < finishedProgressThreshold }) {
            return inProgress
        }
        return started.last
    }

    /// Progress at or above this is treated as finished for home UI.
    static let finishedProgressThreshold: Double = 0.999
}
