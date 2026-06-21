import ReadiumNavigator
import XCTest
@testable import PagePilot

final class ReaderEditingActionsTests: XCTestCase {
    func testEPUBConfigurationUsesNativeActionsOnly() {
        let actions = ReaderEditingActions.epubConfiguration

        XCTAssertEqual(actions.count, 4)
        XCTAssertEqual(actions, [.copy, .share, .lookup, .translate])
    }
}