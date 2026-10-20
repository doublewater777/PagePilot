//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif
import Foundation

struct ReadingLiveActivityAttributes: Codable {
    struct ContentState: Codable, Hashable {
        let title: String
        let progression: Double
    }

    let sessionID: String
    let startedAt: Date
}

#if !targetEnvironment(macCatalyst)
extension ReadingLiveActivityAttributes: ActivityAttributes {}
#endif
