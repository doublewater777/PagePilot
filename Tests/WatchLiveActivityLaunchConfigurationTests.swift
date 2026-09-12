import Foundation
import XCTest

final class WatchLiveActivityLaunchConfigurationTests: XCTestCase {
    func testWatchAppCanLaunchForReadingLiveActivity() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let watchInfoURL = repositoryURL
            .appendingPathComponent("WatchRemote/Info.plist")

        let info = try XCTUnwrap(NSDictionary(contentsOf: watchInfoURL))
        let attributeTypes = try XCTUnwrap(
            info["WKSupportsLiveActivityLaunchAttributeTypes"] as? [String]
        )

        XCTAssertEqual(attributeTypes, ["ReadingLiveActivityAttributes"])
    }
}
