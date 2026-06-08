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
}
