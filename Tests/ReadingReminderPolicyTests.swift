import XCTest
@testable import PagePilot

final class ReadingReminderPolicyTests: XCTestCase {
    func testTriggerComponentsCarriesHourAndMinuteOnly() {
        let comps = ReadingReminderPolicy.triggerComponents(hour: 20, minute: 30)
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertNil(comps.year)
        XCTAssertNil(comps.month)
        XCTAssertNil(comps.day)
    }

    func testIdentifierIsStable() {
        XCTAssertEqual(ReadingReminderPolicy.identifier, "pagepilot.reading.reminder")
    }
}
