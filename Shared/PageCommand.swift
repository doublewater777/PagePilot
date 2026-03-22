import Foundation

/// Watch 和 iPhone 共用的翻页命令
enum PageCommand: String, Codable {
    case next
    case prev

    private enum CodingKeys {
        static let action = "action"
        static let direction = "direction"
    }

    var message: [String: Any] {
        [CodingKeys.action: "turnPage", CodingKeys.direction: self.rawValue]
    }
}
