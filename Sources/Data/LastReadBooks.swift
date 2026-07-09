//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Tracks which books were opened most recently (MRU order).
/// Used by the bookshelf sort and the home "continue reading" card.
enum LastReadBooks {
    static let userDefaultsKey = "lastReadBookIds"
    static let didChange = Notification.Name("LastReadBookIdsDidChange")

    static var orderedIds: [Int64] {
        UserDefaults.standard.array(forKey: userDefaultsKey) as? [Int64] ?? []
    }

    /// Moves `id` to the front of the MRU list and notifies observers.
    static func record(id: Int64) {
        var list = orderedIds
        // Already most-recent — skip write/notify (common during page turns).
        if list.first == id { return }
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
        }
        list.insert(id, at: 0)
        UserDefaults.standard.set(list, forKey: userDefaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
