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

    func testCloudSyncPreferenceUsesInjectedDefaults() throws {
        let suiteName = "CloudSyncSupportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(CloudSyncPreferences.isEnabled(in: defaults))

        CloudSyncPreferences.setEnabled(false, in: defaults, postNotification: false)
        XCTAssertFalse(CloudSyncPreferences.isEnabled(in: defaults))

        CloudSyncPreferences.setEnabled(true, in: defaults, postNotification: false)
        XCTAssertTrue(CloudSyncPreferences.isEnabled(in: defaults))
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
