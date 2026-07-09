//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import XCTest
@testable import PagePilot

final class ContinueReadingSelectorTests: XCTestCase {
    func testPrefersMostRecentlyReadOverCreatedOrder() {
        let older = makeBook(id: 1, title: "Older", progression: 0.2)
        let newer = makeBook(id: 2, title: "Newer", progression: 0.5)
        // Repository order: older first (created ascending)
        let books = [older, newer]

        let selected = ContinueReadingSelector.select(from: books, lastReadIds: [1, 2])
        XCTAssertEqual(selected?.id?.rawValue, 1)
    }

    func testSkipsDeletedIdsInMruList() {
        let book = makeBook(id: 2, title: "Alive", progression: 0.3)
        let selected = ContinueReadingSelector.select(from: [book], lastReadIds: [99, 2])
        XCTAssertEqual(selected?.id?.rawValue, 2)
    }

    func testIncludesFinishedBookWhenMostRecent() {
        let finished = makeBook(id: 1, title: "Done", progression: 1.0)
        let other = makeBook(id: 2, title: "Other", progression: 0.4)

        let selected = ContinueReadingSelector.select(
            from: [finished, other],
            lastReadIds: [1, 2]
        )
        XCTAssertEqual(selected?.id?.rawValue, 1)
        XCTAssertGreaterThanOrEqual(
            selected?.progression ?? 0,
            ContinueReadingSelector.finishedProgressThreshold
        )
    }

    func testFallbackPrefersInProgressWhenMruEmpty() {
        let finished = makeBook(id: 1, title: "Done", progression: 1.0)
        let mid = makeBook(id: 2, title: "Mid", progression: 0.4)
        let untouched = makeBook(id: 3, title: "New", progression: 0)

        let selected = ContinueReadingSelector.select(
            from: [finished, mid, untouched],
            lastReadIds: []
        )
        XCTAssertEqual(selected?.id?.rawValue, 2)
    }

    func testFallbackUsesFinishedWhenNoInProgress() {
        let finishedA = makeBook(id: 1, title: "A", progression: 1.0)
        let finishedB = makeBook(id: 2, title: "B", progression: 1.0)

        let selected = ContinueReadingSelector.select(
            from: [finishedA, finishedB],
            lastReadIds: []
        )
        XCTAssertEqual(selected?.id?.rawValue, 2)
    }

    func testReturnsNilWhenNothingStarted() {
        let a = makeBook(id: 1, title: "A", progression: 0)
        let b = makeBook(id: 2, title: "B", progression: 0)

        let selected = ContinueReadingSelector.select(from: [a, b], lastReadIds: [])
        XCTAssertNil(selected)
    }

    func testReturnsNilForEmptyLibrary() {
        XCTAssertNil(ContinueReadingSelector.select(from: [], lastReadIds: [1]))
    }

    // MARK: - Helpers

    private func makeBook(id: Int64, title: String, progression: Double) -> Book {
        var book = Book(
            id: Book.Id(rawValue: id),
            identifier: "test-\(id)",
            title: title,
            authors: "Author",
            type: "application/epub+zip",
            url: AnyURL(string: "https://example.com/\(id).epub")!
        )
        book.progression = progression
        return book
    }
}
