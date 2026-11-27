//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Availability State

enum ReadingIntelligenceAvailability: Equatable {
    case available
    case simulated
    case unavailable(reason: String)

    var isUsable: Bool {
        switch self {
        case .available, .simulated:
            return true
        case .unavailable:
            return false
        }
    }

    var isSimulated: Bool {
        self == .simulated
    }
}

// MARK: - Quote Sample & Intelligence Tasks

struct ReadingQuoteSample: Equatable, Sendable {
    let text: String
    let note: String?
    let bookTitle: String
    let chapterTitle: String?
}

enum ReadingIntelligenceTask: Equatable, Sendable {
    case explainSelection(text: String, bookTitle: String, chapterTitle: String?)
    case translateSelection(text: String, targetLanguage: AppLanguage, bookTitle: String)
    case recap(bookTitle: String, chapterTitle: String?, priorExcerpt: String)
    case chapterSummary(bookTitle: String, chapterTitle: String?, chapterExcerpt: String)
    case quoteInsights(quotes: [ReadingQuoteSample])

    var localizedTitle: String {
        switch self {
        case .explainSelection:
            return NSLocalizedString("ai_explain_title", comment: "")
        case .translateSelection:
            return NSLocalizedString("ai_translate_title", comment: "")
        case .recap:
            return NSLocalizedString("ai_recap_title", comment: "")
        case .chapterSummary:
            return NSLocalizedString("ai_chapter_summary_title", comment: "")
        case .quoteInsights:
            return NSLocalizedString("ai_quote_insights_title", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .explainSelection:
            return "sparkles"
        case .translateSelection:
            return "character.bubble"
        case .recap:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .chapterSummary:
            return "text.document"
        case .quoteInsights:
            return "lightbulb.max"
        }
    }
}

// MARK: - Token-Safe Context Window Budget

/// Keeps prompts safely inside Apple Intelligence's ~4,096-token on-device context window
/// (reserving headroom for system instructions and streamed output).
enum ReadingContextBudget {
    /// Weighted character units (~1 unit ≈ 1 token).
    static func estimatedUnits(for text: String) -> Int {
        var total = 0.0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x2E80 {
                // CJK / full-width characters consume ~1.3–1.6 tokens each.
                total += 1.45
            } else {
                // Latin characters average ~0.28–0.35 tokens each.
                total += 0.34
            }
        }
        return Int(ceil(total))
    }

    /// Normalizes whitespace and trims text to fit within `maxUnits`, preferring sentence/paragraph breaks.
    static func trimToBudget(_ raw: String, maxUnits: Int, keepTail: Bool = false) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty, maxUnits > 0 else { return "" }
        if estimatedUnits(for: cleaned) <= maxUnits {
            return cleaned
        }

        let characters = Array(cleaned)
        if keepTail {
            var acc = 0.0
            var startIndex = characters.count
            for idx in stride(from: characters.count - 1, through: 0, by: -1) {
                acc += unitWeight(characters[idx])
                if Int(ceil(acc)) > maxUnits {
                    break
                }
                startIndex = idx
            }
            let slice = String(characters[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return snapStartToBoundary(slice)
        } else {
            var acc = 0.0
            var endIndex = 0
            for idx in 0..<characters.count {
                acc += unitWeight(characters[idx])
                if Int(ceil(acc)) > maxUnits {
                    break
                }
                endIndex = idx + 1
            }
            let slice = String(characters[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            return snapEndToBoundary(slice)
        }
    }

    /// Samples head, middle, and tail of a long chapter so the on-device model sees the full arc.
    static func sampleChapter(_ raw: String, maxUnits: Int = 2400) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "" }
        if estimatedUnits(for: cleaned) <= maxUnits {
            return cleaned
        }

        let chars = Array(cleaned)
        let count = chars.count
        let partBudget = max(200, maxUnits / 3)

        let head = trimToBudget(String(chars[..<min(count, count / 2)]), maxUnits: partBudget, keepTail: false)
        let midStart = max(0, count / 2 - count / 6)
        let midEnd = min(count, count / 2 + count / 6)
        let middle = trimToBudget(String(chars[midStart..<midEnd]), maxUnits: partBudget, keepTail: false)
        let tail = trimToBudget(String(chars[max(0, count / 2)...]), maxUnits: partBudget, keepTail: true)

        return [head, "[...]", middle, "[...]", tail]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func unitWeight(_ char: Character) -> Double {
        let isCJK = char.unicodeScalars.contains { $0.value >= 0x2E80 }
        return isCJK ? 1.45 : 0.34
    }

    private static func snapEndToBoundary(_ text: String) -> String {
        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
        guard let lastIdx = text.lastIndex(where: { terminators.contains($0) }) else {
            return text
        }
        let distance = text.distance(from: text.startIndex, to: lastIdx)
        guard distance > text.count / 2 else { return text }
        return String(text[...lastIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func snapStartToBoundary(_ text: String) -> String {
        let terminators: Set<Character> = ["。", "！", "？", ".", "!", "?", "\n"]
        guard let firstIdx = text.firstIndex(where: { terminators.contains($0) }) else {
            return text
        }
        let nextIdx = text.index(after: firstIdx)
        guard nextIdx < text.endIndex, text.distance(from: text.startIndex, to: firstIdx) < text.count / 3 else {
            return text
        }
        return String(text[nextIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Prompt Builder

enum ReadingIntelligencePromptBuilder {
    static func systemInstructions(for language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return "你是 PagePilot 的端侧静谧阅读助手。回答需克制、清晰、忠于原文，使用简体中文输出，避免冗长客套话，不使用 Markdown 代码块。"
        case .english:
            return "You are PagePilot's calm on-device reading companion. Respond concisely, clearly, and faithfully to the passage in English, without filler or markdown code blocks."
        case .spanish:
            return "Eres el asistente sereno de lectura de PagePilot. Responde con claridad, concisión y fidelidad al texto en español, sin rellenos ni bloques de código."
        case .french:
            return "Vous êtes le compagnon de lecture apaisé de PagePilot. Répondez clairement, avec concision et fidélité au texte en français, sans remplissage."
        case .german:
            return "Du bist der ruhige Lesebegleiter von PagePilot. Antworte klar, prägnant und textgetreu auf Deutsch, ohne Füllwörter."
        }
    }

    static func userPrompt(for task: ReadingIntelligenceTask, responseLanguage: AppLanguage) -> String {
        switch task {
        case let .explainSelection(text, bookTitle, chapterTitle):
            let safe = ReadingContextBudget.trimToBudget(text, maxUnits: 1400)
            let chapterNote = chapterTitle.map { " (\($0))" } ?? ""
            return """
            Book: \(bookTitle)\(chapterNote)
            Selected passage:
            \"\(safe)\"

            Explain this passage in \(languageDisplayName(responseLanguage)):
            1. Core meaning in plain, vivid words (2–3 sentences).
            2. Context, subtext, or notable term/allusion if any (1–2 concise bullets).
            """

        case let .translateSelection(text, targetLanguage, bookTitle):
            let safe = ReadingContextBudget.trimToBudget(text, maxUnits: 1400)
            return """
            Book: \(bookTitle)
            Passage:
            \"\(safe)\"

            Translate the passage naturally into \(languageDisplayName(targetLanguage)), preserving its literary tone. Then add 1–2 short notes on any key idioms or nuances.
            """

        case let .recap(bookTitle, chapterTitle, priorExcerpt):
            let safe = ReadingContextBudget.trimToBudget(priorExcerpt, maxUnits: 2100, keepTail: true)
            let chapterNote = chapterTitle.map { " — \($0)" } ?? ""
            return """
            Book: \(bookTitle)\(chapterNote)
            Text just before the reader's current position:
            \(safe)

            Write a spoiler-free "Story / Context So Far" recap in \(languageDisplayName(responseLanguage)) in exactly 3 concise bullet points so the reader can pick up effortlessly. Only reference events or ideas present in the excerpt above.
            """

        case let .chapterSummary(bookTitle, chapterTitle, chapterExcerpt):
            let safe = ReadingContextBudget.sampleChapter(chapterExcerpt, maxUnits: 2300)
            let chapterNote = chapterTitle.map { " — \($0)" } ?? ""
            return """
            Book: \(bookTitle)\(chapterNote)
            Chapter text:
            \(safe)

            Provide a calm chapter overview in \(languageDisplayName(responseLanguage)):
            - Start with a 1-sentence core takeaway.
            - Follow with 3 concise bullet points covering the main arguments, turning points, or motifs.
            """

        case let .quoteInsights(quotes):
            let formatted: String = quotes.prefix(12).enumerated().map { idx, quote -> String in
                let trimmed = ReadingContextBudget.trimToBudget(quote.text, maxUnits: 160)
                let notePart = quote.note.flatMap { $0.isEmpty ? nil : " [Note: \($0)]" } ?? ""
                return "\(idx + 1). [\(quote.bookTitle)] \"\(trimmed)\"\(notePart)"
            }.joined(separator: "\n")
            let safeQuotes = ReadingContextBudget.trimToBudget(formatted, maxUnits: 2200)
            return """
            Reader's highlighted excerpts:
            \(safeQuotes)

            Synthesize these highlights in \(languageDisplayName(responseLanguage)):
            - Identify 2–3 recurring themes or threads connecting these passages.
            - Offer one quiet reflection question to carry into future reading.
            """
        }
    }

    private static func languageDisplayName(_ lang: AppLanguage) -> String {
        switch lang {
        case .simplifiedChinese: return "Simplified Chinese"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }
}

// MARK: - Publication Excerpt Extractor (Readium)

enum ReadingExcerptExtractor {
    /// Extracts up to `maxUnits` of text strictly BEFORE `currentLocator` (zero spoilers).
    static func extractPriorContext(
        from publication: Publication,
        currentLocator: Locator?,
        maxUnits: Int = 2100
    ) async -> String {
        guard let locator = currentLocator,
              let content = publication.content(from: locator) else {
            return await extractCurrentChapter(from: publication, currentLocator: currentLocator, maxUnits: maxUnits)
        }

        let iterator = content.iterator()
        var reversedChunks: [String] = []
        var accumulatedUnits = 0
        var steps = 0
        let maxSteps = 120

        while steps < maxSteps, accumulatedUnits < maxUnits {
            steps += 1
            guard let element = try? await iterator.previous() else { break }
            if let text = (element as? TextualContentElement)?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                reversedChunks.append(text)
                accumulatedUnits += ReadingContextBudget.estimatedUnits(for: text)
            }
        }

        if !reversedChunks.isEmpty {
            let joined = reversedChunks.reversed().joined(separator: "\n\n")
            return ReadingContextBudget.trimToBudget(joined, maxUnits: maxUnits, keepTail: true)
        }

        // Reader is at the very opening of the chapter/book — extract opening paragraphs instead.
        return await extractCurrentChapter(from: publication, currentLocator: currentLocator, maxUnits: min(1400, maxUnits))
    }

    /// Extracts text from the current reading-order resource (chapter), sampling if very long.
    static func extractCurrentChapter(
        from publication: Publication,
        currentLocator: Locator?,
        maxUnits: Int = 2400
    ) async -> String {
        let targetHref = currentLocator?.href ?? publication.readingOrder.first?.url()
        let startLocator: Locator? = {
            guard let href = targetHref else { return currentLocator }
            let link = publication.readingOrder.first { $0.url().isEquivalentTo(href) }
            return Locator(
                href: href,
                mediaType: link?.mediaType ?? currentLocator?.mediaType ?? .html
            )
        }()

        guard let content = publication.content(from: startLocator) else {
            return ""
        }

        let iterator = content.iterator()
        var chunks: [String] = []
        var totalChars = 0
        let maxRawChars = 36_000
        var steps = 0
        let maxSteps = 450

        while steps < maxSteps, totalChars < maxRawChars {
            steps += 1
            guard let element = try? await iterator.next() else { break }
            if let targetHref, !element.locator.href.isEquivalentTo(targetHref), !chunks.isEmpty {
                break
            }
            if let text = (element as? TextualContentElement)?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                chunks.append(text)
                totalChars += text.count
            }
        }

        let raw = chunks.joined(separator: "\n\n")
        return ReadingContextBudget.sampleChapter(raw, maxUnits: maxUnits)
    }
}

// MARK: - Reading Intelligence Engine

@MainActor
final class ReadingIntelligenceEngine: ObservableObject {
    static let shared = ReadingIntelligenceEngine()

    static let simulationPreferenceKey = "debug_simulate_apple_intelligence"
    static let launchArgumentSimulate = "-SimulateAppleIntelligence"

    @Published private(set) var simulationEnabled: Bool

    private let defaults: UserDefaults
    private let isDeveloperModeProvider: () -> Bool

    init(
        defaults: UserDefaults = .standard,
        isDeveloperModeProvider: @escaping () -> Bool = { ProPurchaseManager.shared.isDeveloperModeEnabled }
    ) {
        self.defaults = defaults
        self.isDeveloperModeProvider = isDeveloperModeProvider
        self.simulationEnabled = defaults.bool(forKey: Self.simulationPreferenceKey)
    }

    /// Simulation is ONLY active when Developer Mode is enabled (or via launch argument),
    /// ensuring production users in China mainland or unsupported devices never see mock output.
    var isSimulationActive: Bool {
        if ProcessInfo.processInfo.arguments.contains(Self.launchArgumentSimulate) {
            return true
        }
        return isDeveloperModeProvider() && simulationEnabled
    }

    func setSimulationEnabled(_ enabled: Bool) {
        simulationEnabled = enabled
        defaults.set(enabled, forKey: Self.simulationPreferenceKey)
        objectWillChange.send()
    }

    /// Evaluates true native hardware/OS/region availability via Apple's `SystemLanguageModel.default`.
    var nativeAvailability: ReadingIntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: NSLocalizedString("ai_status_device_not_eligible", comment: ""))
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: NSLocalizedString("ai_status_not_enabled", comment: ""))
                case .modelNotReady:
                    return .unavailable(reason: NSLocalizedString("ai_status_model_not_ready", comment: ""))
                @unknown default:
                    return .unavailable(reason: NSLocalizedString("ai_status_unavailable", comment: ""))
                }
            }
        }
        #endif
        return .unavailable(reason: NSLocalizedString("ai_status_os_unsupported", comment: ""))
    }

    /// Effective availability driving UI entry points.
    /// Returns `.unavailable` silently on unsupported hardware / China mainland / iOS < 26.
    var effectiveAvailability: ReadingIntelligenceAvailability {
        let native = nativeAvailability
        if native == .available {
            return .available
        }
        if isSimulationActive {
            return .simulated
        }
        return native
    }

    /// Single source of truth for showing or hiding every Apple Intelligence entry point in the app.
    var isFeatureAvailable: Bool {
        effectiveAvailability.isUsable
    }

    /// Streams generated text chunks for a reading intelligence task.
    func stream(
        task: ReadingIntelligenceTask,
        responseLanguage: AppLanguage = AppAppearancePreferences.language
    ) -> AsyncThrowingStream<String, Error> {
        let availability = effectiveAvailability

        if availability == .simulated {
            return simulatedStream(for: task, language: responseLanguage)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *), availability == .available {
            return foundationModelsStream(for: task, language: responseLanguage)
        }
        #endif

        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: ReadingIntelligenceError.unavailable)
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, *)
    private func foundationModelsStream(
        for task: ReadingIntelligenceTask,
        language: AppLanguage
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = ReadingIntelligencePromptBuilder.systemInstructions(for: language)
        let prompt = ReadingIntelligencePromptBuilder.userPrompt(for: task, responseLanguage: language)

        return AsyncThrowingStream { continuation in
            let runner = Task {
                do {
                    let session = LanguageModelSession(model: .default, instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: Self.mapGenerationError(error))
                } catch {
                    continuation.finish(throwing: ReadingIntelligenceError.failed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                runner.cancel()
            }
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> ReadingIntelligenceError {
        switch error {
        case .exceededContextWindowSize:
            return .contextTooLong
        case .guardrailViolation, .refusal:
            return .guardrailBlocked
        case .assetsUnavailable:
            return .modelNotReady
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguage
        default:
            return .failed(error.localizedDescription)
        }
    }
    #endif

    // MARK: - Developer Simulation Stream (for testing without Apple Intelligence hardware)

    private func simulatedStream(
        for task: ReadingIntelligenceTask,
        language: AppLanguage
    ) -> AsyncThrowingStream<String, Error> {
        let fullText = Self.simulatedResponseText(for: task, language: language)
        return AsyncThrowingStream { continuation in
            let runner = Task {
                var current = ""
                let units = Array(fullText)
                let step = language == .simplifiedChinese ? 3 : 6
                var index = 0
                while index < units.count {
                    if Task.isCancelled { break }
                    let next = min(units.count, index + step)
                    current.append(contentsOf: units[index..<next])
                    continuation.yield(current)
                    index = next
                    try? await Task.sleep(nanoseconds: 24_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                runner.cancel()
            }
        }
    }

    static func simulatedResponseText(for task: ReadingIntelligenceTask, language: AppLanguage) -> String {
        let isZH = language == .simplifiedChinese
        switch task {
        case let .explainSelection(text, bookTitle, _):
            let preview = String(text.prefix(26))
            if isZH {
                return """
                这段出自《\(bookTitle)》的文字以「\(preview)…」为切入点，刻画了人物在静谧语境下的内心转向与留白张力。

                • 语境深意：作者借日常细节反衬情绪节奏，让读者在放慢阅读速度时体察隐含态度。
                • 阅读提示：可留意前后段落中反复出现的意象呼应，这往往是本章情绪收束的伏笔。
                """
            } else {
                return """
                In \(bookTitle), this passage (“\(preview)…”) slows the narrative cadence to highlight a quiet shift in perspective rather than overt action.

                • Subtext: Everyday sensory details carry the emotional weight, inviting the reader to notice what remains unsaid.
                • Reading cue: Watch how this motif echoes later in the chapter as the tone resolves.
                """
            }

        case let .translateSelection(text, targetLanguage, _):
            let preview = String(text.prefix(48))
            if targetLanguage == .simplifiedChinese {
                return """
                「\(preview)」——（端侧文学语境译文示例）文字在柔和光影与留白之间缓缓铺展，保留了原文克制而沉静的叙述韵律。

                • 措辞注解：译文优先保留了句式的呼吸感与书面语色彩，避免生硬直译。
                """
            } else {
                return """
                “\(preview)” — (On-device literary translation preview) Rendered with the calm cadence and understated imagery of the original line.

                • Nuance note: Preserves sentence rhythm and subtle tone rather than translating word-for-word.
                """
            }

        case let .recap(bookTitle, chapterTitle, _):
            let ch = chapterTitle ?? (isZH ? "当前章节" : "current chapter")
            if isZH {
                return """
                • 此前脉络：《\(bookTitle)》在「\(ch)」之前已铺陈核心场景与人物立场，节奏逐步收紧。
                • 关键细节：上一节留下的对话与意象线索正引导当前段落的转折，尚未揭晓后续发展。
                • 无剧透衔接：接下来直接沿着眼前这一页继续阅读，即可自然接上思路。
                """
            } else {
                return """
                • Where you left off: Earlier in \(bookTitle) (\(ch)), the setting and central tension were quietly established.
                • Key thread: A subtle exchange from the preceding pages sets up the reflection you are reading now.
                • Ready to resume: Pick up right at the current line with zero spoilers ahead.
                """
            }

        case let .chapterSummary(bookTitle, chapterTitle, _):
            let ch = chapterTitle ?? bookTitle
            if isZH {
                return """
                本节（\(ch)）围绕核心意象展开递进式叙述，在克制的笔触中完成了关键观点的铺垫。

                • 核心主线：以具体观察切入，逐步过渡到更深层的主题思考。
                • 关键转折：中段通过对比凸显人物或观点的内在张力。
                • 章节余韵：结尾以留白收束，为下一章的推进埋下自然过渡。
                """
            } else {
                return """
                \(ch) builds steadily from concrete observation toward a quieter thematic turn.

                • Core focus: Grounds the section in tactile detail before widening the lens.
                • Key shift: Uses contrast midway through to clarify the central tension.
                • Closing note: Ends on an open cadence that bridges cleanly into the next chapter.
                """
            }

        case let .quoteInsights(quotes):
            let count = quotes.count
            let books = Array(Set(quotes.map(\.bookTitle))).prefix(2).joined(separator: " / ")
            if isZH {
                return """
                从你收藏的 \(count) 条书摘（\(books)）中，可以看到两条清晰的阅读主线：

                • 主题共鸣：你格外偏爱描写「专注、时间节律与静谧观察」的句子，注重文字背后的留白感。
                • 思路连接：不同章节的高亮共同指向一种「慢下来再理解」的阅读习惯。
                • 延伸思考：下次翻开书时，不妨留意这些句子在当下生活里对应的一个小瞬间。
                """
            } else {
                return """
                Across your \(count) saved highlights (\(books)), two recurring threads stand out:

                • Shared theme: You gravitate toward passages about calm attention, craft, and the rhythm of unhurried time.
                • Reading pattern: Your notes favor concise observations that double as anchors after closing the book.
                • Question to carry forward: Which of these lines best reflects what you want to notice this week?
                """
            }
        }
    }
}

// MARK: - Localized Errors

enum ReadingIntelligenceError: LocalizedError, Equatable {
    case unavailable
    case contextTooLong
    case guardrailBlocked
    case modelNotReady
    case unsupportedLanguage
    case emptyContext
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return NSLocalizedString("ai_error_unavailable", comment: "")
        case .contextTooLong:
            return NSLocalizedString("ai_error_context_too_long", comment: "")
        case .guardrailBlocked:
            return NSLocalizedString("ai_error_guardrail", comment: "")
        case .modelNotReady:
            return NSLocalizedString("ai_status_model_not_ready", comment: "")
        case .unsupportedLanguage:
            return NSLocalizedString("ai_error_unsupported_language", comment: "")
        case .emptyContext:
            return NSLocalizedString("ai_error_empty_context", comment: "")
        case .failed(let message):
            return message
        }
    }
}
