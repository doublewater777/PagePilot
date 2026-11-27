//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit
import XCTest
@testable import PagePilot

final class PagePilotRedesignTests: XCTestCase {

    // MARK: - ReaderPaperPreset

    func testPaperPresetRoundTripMatchingForAllFourPresets() {
        for preset in ReaderPaperPreset.allCases {
            var prefs = EPUBPreferences()
            preset.apply(to: &prefs)

            let matchedLight = ReaderPaperPreset.matching(preferences: prefs, systemStyle: .light)
            let matchedDark = ReaderPaperPreset.matching(preferences: prefs, systemStyle: .dark)

            XCTAssertEqual(matchedLight, preset, "Preset \(preset) should round-trip in light system style")
            XCTAssertEqual(matchedDark, preset, "Preset \(preset) should round-trip in dark system style")
        }
    }

    func testPaperPresetCycleOrderCoversAllCases() {
        var current = ReaderPaperPreset.morningPaper
        var visited: [ReaderPaperPreset] = []
        for _ in 0..<ReaderPaperPreset.allCases.count {
            visited.append(current)
            current = current.next()
        }
        XCTAssertEqual(visited, ReaderPaperPreset.allCases)
        XCTAssertEqual(current, .morningPaper)
    }

    func testPaperPresetResolvesDefaultSystemStyleWhenPreferencesEmpty() {
        let empty = EPUBPreferences()
        XCTAssertEqual(ReaderPaperPreset.matching(preferences: empty, systemStyle: .light), .morningPaper)
        XCTAssertEqual(ReaderPaperPreset.matching(preferences: empty, systemStyle: .dark), .midnightInk)
    }

    func testPaperPresetReturnsNilForUnrecognizedCustomBackground() {
        var custom = EPUBPreferences()
        custom.backgroundColor = ReadiumNavigator.Color(color: SwiftUI.Color.green)
        XCTAssertNil(ReaderPaperPreset.matching(preferences: custom, systemStyle: .light))
    }

    // MARK: - HandsFreeReadingState

    func testHandsFreeModeKeepsWatchAndVolumeActiveWhileShieldingCanvas() {
        var state = HandsFreeReadingState()
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.shouldKeepScreenAwake)
        XCTAssertFalse(state.blocksCanvasTouch)
        XCTAssertTrue(state.allowsWatchPageTurn)
        XCTAssertTrue(state.allowsVolumeKeyPageTurn)

        XCTAssertTrue(state.toggle())
        XCTAssertTrue(state.isEnabled)
        XCTAssertTrue(state.shouldKeepScreenAwake)
        XCTAssertTrue(state.blocksCanvasTouch)
        XCTAssertTrue(state.allowsWatchPageTurn)
        XCTAssertTrue(state.allowsVolumeKeyPageTurn)

        state.disable()
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.shouldKeepScreenAwake)
        XCTAssertFalse(state.blocksCanvasTouch)
    }

    // MARK: - LaunchToReaderPolicy

    func testLaunchToReaderPolicyOnlyFiresWhenCleanLaunchAndEnabled() {
        XCTAssertTrue(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: true,
                launchDirectlyEnabled: true,
                hasIncomingURL: false,
                hasDebugTabOverride: false,
                alreadyConsumedThisLaunch: false
            )
        )

        XCTAssertFalse(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: false,
                launchDirectlyEnabled: true,
                hasIncomingURL: false,
                hasDebugTabOverride: false,
                alreadyConsumedThisLaunch: false
            )
        )

        XCTAssertFalse(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: true,
                launchDirectlyEnabled: false,
                hasIncomingURL: false,
                hasDebugTabOverride: false,
                alreadyConsumedThisLaunch: false
            )
        )

        XCTAssertFalse(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: true,
                launchDirectlyEnabled: true,
                hasIncomingURL: true,
                hasDebugTabOverride: false,
                alreadyConsumedThisLaunch: false
            )
        )

        XCTAssertFalse(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: true,
                launchDirectlyEnabled: true,
                hasIncomingURL: false,
                hasDebugTabOverride: true,
                alreadyConsumedThisLaunch: false
            )
        )

        XCTAssertFalse(
            LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
                hasSeenOnboarding: true,
                launchDirectlyEnabled: true,
                hasIncomingURL: false,
                hasDebugTabOverride: false,
                alreadyConsumedThisLaunch: true
            )
        )
    }

    // MARK: - ReadingTimeEstimator

    func testReadingTimeEstimatorComputesSensibleMinutesAndBounds() {
        // 4 remaining positions * 45s = 180s = 3 minutes
        XCTAssertEqual(ReadingTimeEstimator.remainingMinutes(currentPosition: 1, targetEndPosition: 4), 3)
        // Last position still returns minimum 1 minute
        XCTAssertEqual(ReadingTimeEstimator.remainingMinutes(currentPosition: 10, targetEndPosition: 10), 1)
        // Invalid bounds return nil
        XCTAssertNil(ReadingTimeEstimator.remainingMinutes(currentPosition: 0, targetEndPosition: 10))
        XCTAssertNil(ReadingTimeEstimator.remainingMinutes(currentPosition: 12, targetEndPosition: 10))
    }

    // MARK: - QuotePostcardPayload

    func testQuotePostcardPayloadSanitizesAuthorAndEmptyNote() {
        let payload = QuotePostcardPayload(
            quote: "  Hello world  \n",
            note: "   ",
            bookTitle: "Sample Book",
            author: "Unknown",
            chapterTitle: "  Chapter 1 "
        )

        XCTAssertEqual(payload.quote, "Hello world")
        XCTAssertNil(payload.note)
        XCTAssertNil(payload.author)
        XCTAssertEqual(payload.chapterTitle, "Chapter 1")
    }

    // MARK: - DeskShelfFilter

    func testDeskShelfFilterClassifiesBooksByProgression() {
        let unread = Book(title: "A", type: "application/epub+zip", url: AnyURL(string: "a.epub")!)
        var reading = Book(title: "B", type: "application/epub+zip", url: AnyURL(string: "b.epub")!)
        reading.progression = 0.42
        var finished = Book(title: "C", type: "application/epub+zip", url: AnyURL(string: "c.epub")!)
        finished.progression = ContinueReadingSelector.finishedProgressThreshold

        XCTAssertTrue(DeskShelfFilter.all.matches(unread))
        XCTAssertTrue(DeskShelfFilter.all.matches(reading))
        XCTAssertTrue(DeskShelfFilter.all.matches(finished))

        XCTAssertTrue(DeskShelfFilter.unread.matches(unread))
        XCTAssertFalse(DeskShelfFilter.unread.matches(reading))

        XCTAssertTrue(DeskShelfFilter.reading.matches(reading))
        XCTAssertFalse(DeskShelfFilter.reading.matches(unread))
        XCTAssertFalse(DeskShelfFilter.reading.matches(finished))

        XCTAssertTrue(DeskShelfFilter.finished.matches(finished))
        XCTAssertFalse(DeskShelfFilter.finished.matches(reading))
    }
}
