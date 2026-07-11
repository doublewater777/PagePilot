//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ImageIO
import UIKit

/// Loads local cover images asynchronously and caches them in memory.
///
/// Drop-in replacement for the synchronous `Data(contentsOf:)` call in
/// `SendBooksView.coverThumbnail(for:)`.  Thread-safe: all cache access is
/// serialised through the actor.
actor CoverImageLoader {

    // MARK: - Cache

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    // MARK: - Public interface

    /// Returns the cached thumbnail for `bookId` if one exists, otherwise
    /// downsamples the file at `url` asynchronously, caches it, and returns it.
    /// Returns `nil` when the file is missing or its data cannot be decoded.
    func load(url: URL, bookId: Int64, maxPixelSize: Int = 512) async -> UIImage? {
        let key = "\(bookId)-\(maxPixelSize)-\(url.path)" as NSString

        // Cache hit — no I/O needed.
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !Task.isCancelled else { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: thumbnail)

        let cost = thumbnail.bytesPerRow * thumbnail.height
        cache.setObject(image, forKey: key, cost: cost)

        return image
    }

    /// Removes all cached images (useful when the library changes on disk).
    func clearCache() {
        cache.removeAllObjects()
    }
}
