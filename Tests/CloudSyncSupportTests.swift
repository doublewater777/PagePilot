//
//  Copyright 2026 PagePilot. All rights reserved.
//

import Foundation
import ReadiumShared
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

    func testCloudSyncRequiresBothEnabledPreferenceAndProAccess() {
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: false, hasProAccess: false))
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: true, hasProAccess: false))
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: false, hasProAccess: true))
        XCTAssertTrue(CloudSyncAccessPolicy.canSync(isEnabled: true, hasProAccess: true))
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

    func testCloudLocatorJSONRoundTrips() throws {
        let locator = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.25, totalProgression: 0.5)
        )

        let decoded = try XCTUnwrap(
            CloudSyncStore.decodeLocator(locator.jsonString())
        )

        XCTAssertEqual(decoded, locator)
    }

    func testPortableSourceURLConvertsLocalSandboxPathToRelative() {
        let staleLocalURL = "file:///var/mobile/Containers/Data/Application/E18C15C4-3C91-4495-BDF0-C2B1840A55B5/Documents/Statement_202607%201.pdf"
        let portable = CloudSyncStore.portableSourceURL(from: staleLocalURL)
        XCTAssertEqual(portable, "Statement_202607%201.pdf")
    }

    func testPortableSourceURLPreservesRelativeURL() {
        let relative = "MyBook.epub"
        let portable = CloudSyncStore.portableSourceURL(from: relative)
        XCTAssertEqual(portable, "MyBook.epub")
    }

    func testPortableSourceURLPreservesRemoteURL() {
        let remote = "https://example.com/books/sample.epub"
        let portable = CloudSyncStore.portableSourceURL(from: remote)
        XCTAssertEqual(portable, remote)
    }

    func testPortableSourceURLRejectsArbitraryLocalFileOutsideDocuments() {
        let nonDocLocal = "file:///private/var/tmp/temp_book.epub"
        let portable = CloudSyncStore.portableSourceURL(from: nonDocLocal)
        XCTAssertNil(portable)
    }
}
