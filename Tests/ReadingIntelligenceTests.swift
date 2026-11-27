//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

@testable import PagePilot
import XCTest

final class ReadingIntelligenceTests: XCTestCase {
    func testContextBudgetEstimatesCJKHeavierThanLatin() {
        let cjk = String(repeating: "静", count: 100)
        let latin = String(repeating: "a", count: 100)
        XCTAssertGreaterThan(
            ReadingContextBudget.estimatedUnits(for: cjk),
            ReadingContextBudget.estimatedUnits(for: latin) * 3
        )
    }

    func testTrimToBudgetRespectsLimitAndSentenceBoundary() {
        let longText = (1...80)
            .map { "Sentence number \($0) explores quiet reading habits in detail." }
            .joined(separator: " ")

        let headTrimmed = ReadingContextBudget.trimToBudget(longText, maxUnits: 120, keepTail: false)
        XCTAssertFalse(headTrimmed.isEmpty)
        XCTAssertLessThanOrEqual(ReadingContextBudget.estimatedUnits(for: headTrimmed), 125)
        XCTAssertTrue(headTrimmed.hasPrefix("Sentence number 1"))
        XCTAssertTrue(headTrimmed.hasSuffix("."))

        let tailTrimmed = ReadingContextBudget.trimToBudget(longText, maxUnits: 120, keepTail: true)
        XCTAssertFalse(tailTrimmed.isEmpty)
        XCTAssertLessThanOrEqual(ReadingContextBudget.estimatedUnits(for: tailTrimmed), 125)
        XCTAssertTrue(tailTrimmed.contains("Sentence number 80"))
    }

    func testSampleChapterPreservesHeadMiddleAndTailForLongChapters() {
        let opening = "Opening scene at the misty harbor lighthouse. "
        let middle = String(repeating: "Middle chapter narrative filler text for sampling. ", count: 300)
        let closing = "Final concluding paragraph at dusk."
        let chapter = opening + middle + closing

        let sampled = ReadingContextBudget.sampleChapter(chapter, maxUnits: 900)
        XCTAssertTrue(sampled.contains("Opening scene"))
        XCTAssertTrue(sampled.contains("[...]"))
        XCTAssertTrue(sampled.contains("Final concluding paragraph"))
        XCTAssertLessThanOrEqual(ReadingContextBudget.estimatedUnits(for: sampled), 960)
    }

    func testPromptBuilderIncludesBookTitleAndSafeExcerpt() {
        let prompt = ReadingIntelligencePromptBuilder.userPrompt(
            for: .explainSelection(text: "A quiet lamp by the window.", bookTitle: "Morning Mist", chapterTitle: "Chapter 1"),
            responseLanguage: .english
        )
        XCTAssertTrue(prompt.contains("Morning Mist"))
        XCTAssertTrue(prompt.contains("Chapter 1"))
        XCTAssertTrue(prompt.contains("A quiet lamp by the window."))
    }

    @MainActor
    func testSimulationRequiresDeveloperMode() {
        let suiteName = "ReadingIntelligenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var devMode = false
        let engine = ReadingIntelligenceEngine(defaults: defaults, isDeveloperModeProvider: { devMode })

        engine.setSimulationEnabled(true)
        XCTAssertFalse(engine.isSimulationActive, "Production users must never get simulated AI when Developer Mode is off")

        devMode = true
        XCTAssertTrue(engine.isSimulationActive)
        XCTAssertTrue(engine.isFeatureAvailable)
    }

    @MainActor
    func testSimulatedStreamProducesCompleteLocalizedResponse() async throws {
        let suiteName = "ReadingIntelligenceTests.Stream.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let engine = ReadingIntelligenceEngine(defaults: defaults, isDeveloperModeProvider: { true })
        engine.setSimulationEnabled(true)

        var lastChunk = ""
        let stream = engine.stream(
            task: .recap(bookTitle: "晨雾与纸页", chapterTitle: "第四章", priorExcerpt: "清晨六点半"),
            responseLanguage: .simplifiedChinese
        )
        for try await chunk in stream {
            lastChunk = chunk
        }
        XCTAssertTrue(lastChunk.contains("晨雾与纸页"))
        XCTAssertTrue(lastChunk.contains("第四章"))
    }
}
