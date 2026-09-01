//
//  Copyright 2026 PagePilot. All rights reserved.
//

import Foundation
import XCTest
@testable import PagePilot

final class CloudSyncSupportTests: XCTestCase {
    func testBookSyncIdentifierIsStableForPublicationIdentifier() {
        let first = CloudSyncIdentifier.book(identifier: "urn:isbn:9780141439518")
        let second = CloudSyncIdentifier.book(identifier: "urn:isbn:9780141439518")

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("book-"))
    }

    func testAnnotationIdentifiersAreNamespaced() {
        XCTAssertTrue(CloudSyncIdentifier.bookmark().hasPrefix("bookmark-"))
        XCTAssertTrue(CloudSyncIdentifier.highlight().hasPrefix("highlight-"))
    }

    func testRemoteWinsWhenItIsNewerOrEqual() {
        let local = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: Date(timeIntervalSince1970: 99)
            )
        )
        XCTAssertTrue(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: local
            )
        )
        XCTAssertTrue(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: Date(timeIntervalSince1970: 101)
            )
        )
    }
}
