//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class PilotOwlMascotTests: XCTestCase {
    func testEmptyLibraryAlwaysResolvesIdleMood() {
        let mood = MascotMoodPolicy.resolve(
            todaySeconds: 45 * 60,
            dailyGoalMinutes: 30,
            streakDays: 5,
            hour: 23,
            hasBooks: false
        )
        XCTAssertEqual(mood, .idle)
    }

    func testGoalReachedTakesPriorityOverNightOwlAndReading() {
        let nightGoalMood = MascotMoodPolicy.resolve(
            todaySeconds: 30 * 60,
            dailyGoalMinutes: 30,
            streakDays: 4,
            hour: 23,
            hasBooks: true
        )
        XCTAssertEqual(nightGoalMood, .celebrating)

        let dayGoalMood = MascotMoodPolicy.resolve(
            todaySeconds: 40 * 60,
            dailyGoalMinutes: 30,
            streakDays: 1,
            hour: 14,
            hasBooks: true
        )
        XCTAssertEqual(dayGoalMood, .celebrating)
    }

    func testNightHoursResolveNightOwlWhenGoalNotReached() {
        for nightHour in [22, 23, 0, 1, 4] {
            let mood = MascotMoodPolicy.resolve(
                todaySeconds: 10 * 60,
                dailyGoalMinutes: 30,
                streakDays: 2,
                hour: nightHour,
                hasBooks: true
            )
            XCTAssertEqual(mood, .nightOwl, "Hour \(nightHour) should resolve nightOwl")
        }
    }

    func testDaytimeActiveReadingAndIdleResolution() {
        let readingMood = MascotMoodPolicy.resolve(
            todaySeconds: 5 * 60,
            dailyGoalMinutes: 30,
            streakDays: 0,
            hour: 10,
            hasBooks: true
        )
        XCTAssertEqual(readingMood, .reading)

        let idleMood = MascotMoodPolicy.resolve(
            todaySeconds: 30,
            dailyGoalMinutes: 30,
            streakDays: 3,
            hour: 9,
            hasBooks: true
        )
        XCTAssertEqual(idleMood, .idle)
    }

    func testAllMoodAssetNamesAreUniqueAndNonEmpty() {
        let names = MascotMood.allCases.map(\.assetName)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testTapGreetingsCycleDeterministicallyAcrossAllMoods() {
        for mood in MascotMood.allCases {
            let g0 = MascotMoodPolicy.tapGreeting(for: mood, tapCount: 0)
            let g1 = MascotMoodPolicy.tapGreeting(for: mood, tapCount: 1)
            let g2 = MascotMoodPolicy.tapGreeting(for: mood, tapCount: 2)
            let g3 = MascotMoodPolicy.tapGreeting(for: mood, tapCount: 3)
            XCTAssertFalse(g0.isEmpty)
            XCTAssertEqual(g0, g3)
            XCTAssertNotEqual(g0, g1)
            XCTAssertNotEqual(g1, g2)
        }
    }
}
