//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Free-tier highlight quota: count global highlights, gate only creates.
enum NotesQuota {
    /// Soft warning starts when free usage reaches this many after a successful add.
    static let warningThreshold = 16

    enum AddDecision: Equatable {
        case allow
        /// Still allowed; `remaining` free slots left after this add.
        case allowWithWarning(remaining: Int)
        case blocked(limit: Int)
    }

    /// Evaluate whether a free or Pro user may create one more highlight.
    /// - Parameter currentCount: existing highlight count before the new insert.
    static func evaluateAdd(currentCount: Int, hasProAccess: Bool) -> AddDecision {
        if hasProAccess {
            return .allow
        }

        let limit = ProPurchaseManager.freeHighlightLimit
        if currentCount >= limit {
            return .blocked(limit: limit)
        }

        let remainingAfter = limit - currentCount - 1
        let usedAfter = currentCount + 1
        // Warn only while free slots remain; the final free add stays a normal success toast.
        if usedAfter >= warningThreshold, remainingAfter > 0 {
            return .allowWithWarning(remaining: remainingAfter)
        }
        return .allow
    }
}
