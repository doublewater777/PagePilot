//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class CoverImageLoaderTests: XCTestCase {

    // MARK: - Helpers

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverImageLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
        tmpDir = nil
        try super.tearDownWithError()
    }

    /// Writes a minimal 1×1 PNG to a temp file and returns its URL.
    private func makeImageFile(named name: String = "cover.png") throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        let image = UIImage(systemName: "book")!
        let data = image.pngData()!
        try data.write(to: url)
        return url
    }

    // MARK: - Cycle 1: returns image for valid URL

    func testLoadsImageFromDisk() async throws {
        let url = try makeImageFile()
        let loader = CoverImageLoader()

        let image = await loader.load(url: url, bookId: 1)

        XCTAssertNotNil(image, "Expected a UIImage for a valid cover file")
    }

    // MARK: - Cycle 2: cache hit — second call returns same object, no extra I/O

    func testSecondLoadReturnsCachedImage() async throws {
        let url = try makeImageFile()
        let loader = CoverImageLoader()

        let first = await loader.load(url: url, bookId: 42)
        // Delete the file — a cache miss would now return nil
        try FileManager.default.removeItem(at: url)

        let second = await loader.load(url: url, bookId: 42)

        XCTAssertNotNil(second, "Expected cached image even after the file is deleted")
        XCTAssertTrue(first === second, "Expected the exact same UIImage instance from cache")
    }

    // MARK: - Cycle 3: missing file returns nil gracefully

    func testMissingFileReturnsNil() async {
        let missingURL = tmpDir.appendingPathComponent("does_not_exist.png")
        let loader = CoverImageLoader()

        let image = await loader.load(url: missingURL, bookId: 99)

        XCTAssertNil(image, "Expected nil for a file that does not exist")
    }

    func testLargeCoverIsDownsampledBeforeReturningThumbnail() async throws {
        let url = tmpDir.appendingPathComponent("large-cover.png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 2100))
        let data = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1500, height: 2100))
        }
        try data.write(to: url)

        let loader = CoverImageLoader()
        let image = await loader.load(url: url, bookId: 100, maxPixelSize: 160)

        XCTAssertNotNil(image, "Expected the large cover to decode as a thumbnail")
        let pixelWidth = image.map { $0.size.width * $0.scale } ?? 0
        let pixelHeight = image.map { $0.size.height * $0.scale } ?? 0
        XCTAssertLessThanOrEqual(
            max(pixelWidth, pixelHeight),
            160,
            "Notes thumbnails must not retain a full-resolution cover in memory"
        )
    }

    func testChangedCoverURLDoesNotReuseCachedImageForSameBook() async throws {
        let firstURL = try makeImageFile(named: "first.png")
        let secondURL = tmpDir.appendingPathComponent("second.png")
        let secondImage = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        try secondImage.pngData()!.write(to: secondURL)

        let loader = CoverImageLoader()
        let first = await loader.load(url: firstURL, bookId: 101)
        let second = await loader.load(url: secondURL, bookId: 101)

        XCTAssertFalse(first === second, "A changed cover URL must not return the stale cached thumbnail")
    }

    func testTruncatedCoverReturnsNil() async throws {
        let url = tmpDir.appendingPathComponent("truncated.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)

        let image = await CoverImageLoader().load(url: url, bookId: 102)

        XCTAssertNil(image, "A malformed cover must fail without retaining a partial image")
    }
}
