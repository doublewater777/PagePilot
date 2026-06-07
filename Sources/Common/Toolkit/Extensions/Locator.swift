//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared

extension Locator: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let json = try decoder.singleValueContainer().decode(String.self)
        guard let locator = try Locator(legacyJSONString: json) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid Locator JSON string."
                )
            )
        }
        self = locator
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(jsonString())
    }
}
