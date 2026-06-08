//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit

/// Loads local cover images asynchronously and caches them in memory.
///
/// Drop-in replacement for the synchronous `Data(contentsOf:)` call in
/// `SendBooksView.coverThumbnail(for:)`.  Thread-safe: all cache access is
/// serialised through the actor.
actor CoverImageLoader {

    // MARK: - Cache

    private let cache = NSCache<NSNumber, UIImage>()

    // MARK: - Public interface

    /// Returns the cached image for `bookId` if one exists, otherwise loads
    /// the file at `url` from disk asynchronously, caches it, and returns it.
    /// Returns `nil` when the file is missing or its data cannot be decoded.
    func load(url: URL, bookId: Int64) async -> UIImage? {
        let key = NSNumber(value: bookId)

        // Cache hit — no I/O needed.
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Off-task disk read so we never block the caller's actor.
        let image = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return UIImage?.none }
            return UIImage(data: data)
        }.value

        if let image {
            cache.setObject(image, forKey: key)
        }

        return image
    }

    /// Removes all cached images (useful when the library changes on disk).
    func clearCache() {
        cache.removeAllObjects()
    }
}
