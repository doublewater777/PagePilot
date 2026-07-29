//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CryptoKit
import Foundation
import ReadiumShared

/// Converts a plain text (.txt) file into a minimal EPUB 3 package
/// that can be opened by Readium's publication opener.
///
/// Features:
/// - Automatic encoding detection (UTF-8, GBK, GB18030, Latin-1)
/// - Chapter splitting by common Chinese/English chapter patterns
/// - Proper EPUB 3 structure with navigation document
/// - Deterministic `dc:identifier` from source file bytes so re-imports can dedupe
final class TXTToEPUBConverter {

    enum ConversionError: LocalizedError {
        case cannotReadFile
        case cannotDetectEncoding
        case epubCreationFailed(Error)
        case invalidOutputURL

        var errorDescription: String? {
            switch self {
            case .cannotReadFile:
                return NSLocalizedString("txt_error_cannot_read", comment: "")
            case .cannotDetectEncoding:
                return NSLocalizedString("txt_error_encoding", comment: "")
            case .epubCreationFailed(let error):
                return String(format: NSLocalizedString("txt_error_conversion", comment: ""), error.localizedDescription)
            case .invalidOutputURL:
                return NSLocalizedString("txt_error_invalid_output", comment: "")
            }
        }
    }

    // MARK: - Public

    /// Stable publication identifier for a TXT source, derived from raw file bytes.
    static func contentIdentifier(for sourceURL: URL) throws -> String {
        let data = try Data(contentsOf: sourceURL)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "urn:pagepilot:txt:\(hex)"
    }

    /// Converts the TXT file at `sourceURL` into an EPUB file.
    /// Returns the URL of the generated `.epub` file in the temporary directory.
    ///
    /// - Parameter identifier: Optional stable identifier. When omitted, derived
    ///   from the source file contents so identical re-imports share an id.
    static func convert(from sourceURL: URL, identifier: String? = nil) async throws -> URL {
        let text = try readTextFile(at: sourceURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let chapters = splitIntoChapters(text: text, fallbackTitle: title)
        let packagerChapters = chapters.map { chapter in
            MinimalEPUBPackager.Chapter(
                title: chapter.title,
                bodyHTML: plainTextBodyHTML(title: chapter.title, content: chapter.content)
            )
        }
        let resolvedIdentifier = try identifier ?? contentIdentifier(for: sourceURL)

        do {
            return try await MinimalEPUBPackager.package(
                title: title,
                language: "zh",
                chapters: packagerChapters,
                identifier: resolvedIdentifier
            )
        } catch let error as MinimalEPUBPackager.PackagerError {
            switch error {
            case .epubCreationFailed(let underlying):
                throw ConversionError.epubCreationFailed(underlying)
            }
        } catch {
            throw ConversionError.epubCreationFailed(error)
        }
    }

    // MARK: - Encoding Detection & Reading

    private static func readTextFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ConversionError.cannotReadFile
        }

        // Try encodings in order of likelihood
        let encodings: [String.Encoding] = [
            .utf8,
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue))),
            .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))),
            .unicode,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
            .windowsCP1252,
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }

        // Last resort: try system auto-detection
        var usedEncoding: String.Encoding = .utf8
        if let text = try? String(contentsOf: url, usedEncoding: &usedEncoding) {
            return text
        }

        throw ConversionError.cannotDetectEncoding
    }

    // MARK: - Chapter Splitting

    private struct Chapter {
        let title: String
        let content: String
    }

    /// Common chapter heading patterns for Chinese and English novels.
    private static let chapterPatterns: [NSRegularExpression] = {
        let patterns = [
            // Chinese: 第X章, 第X节, 第X回, 第X卷
            #"^第[零一二三四五六七八九十百千万\d]+[章节回卷集部篇].*"#,
            // Chinese: 章节 + number
            #"^[章节卷集]\s*[零一二三四五六七八九十百千万\d].*"#,
            // English: Chapter X, CHAPTER X
            #"^[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\s+[\dIVXLCDMivxlcdm]+.*"#,
            // Numbered: 1. Title, 1、Title, 1：Title
            #"^\d{1,4}[.、：:]\s*.+"#,
            // Separator lines: === or ---
            #"^[=\-]{4,}\s*$"#,
            // Volume: Vol. X, Book X, Part X
            #"^(Vol\.|Volume|Book|Part)\s+[\dIVXLCDMivxlcdm]+.*"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .anchorsMatchLines) }
    }()

    private static func splitIntoChapters(text: String, fallbackTitle: String) -> [Chapter] {
        let lines = text.components(separatedBy: .newlines)

        // Find chapter boundaries
        var boundaries: [(index: Int, title: String)] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 100 else { continue }

            for pattern in chapterPatterns {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if pattern.firstMatch(in: trimmed, range: range) != nil {
                    boundaries.append((index, trimmed))
                    break
                }
            }
        }

        // If no chapters found or too few, split by size
        if boundaries.count < 2 {
            return splitBySize(lines: lines, fallbackTitle: fallbackTitle)
        }

        // Build chapters from boundaries
        var chapters: [Chapter] = []

        // Content before first chapter heading
        if boundaries[0].index > 0 {
            let preambleLines = Array(lines[0..<boundaries[0].index])
            let preambleContent = preambleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !preambleContent.isEmpty {
                chapters.append(Chapter(
                    title: NSLocalizedString("txt_chapter_preface", comment: ""),
                    content: preambleContent
                ))
            }
        }

        // Each chapter
        for i in 0..<boundaries.count {
            let start = boundaries[i].index
            let end = (i + 1 < boundaries.count) ? boundaries[i + 1].index : lines.count
            let chapterLines = Array(lines[(start + 1)..<end])
            let content = chapterLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            if !content.isEmpty || i == 0 {
                chapters.append(Chapter(title: boundaries[i].title, content: content))
            }
        }

        return chapters.isEmpty ? [Chapter(title: fallbackTitle, content: text)] : chapters
    }

    /// Fallback: split into chunks of ~5000 characters each.
    private static func splitBySize(lines: [String], fallbackTitle: String, chunkSize: Int = 5000) -> [Chapter] {
        let fullText = lines.joined(separator: "\n")
        guard fullText.count > chunkSize else {
            return [Chapter(title: fallbackTitle, content: fullText)]
        }

        var chapters: [Chapter] = []
        var currentContent = ""
        var chapterIndex = 1

        for line in lines {
            currentContent += line + "\n"
            if currentContent.count >= chunkSize {
                let title = String(format: NSLocalizedString("txt_chapter_number", comment: ""), chapterIndex)
                chapters.append(Chapter(
                    title: title,
                    content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
                currentContent = ""
                chapterIndex += 1
            }
        }

        // Remaining content
        let remaining = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            let title = String(format: NSLocalizedString("txt_chapter_number", comment: ""), chapterIndex)
            chapters.append(Chapter(title: title, content: remaining))
        }

        return chapters
    }

    // MARK: - Body HTML

    private static func plainTextBodyHTML(title: String, content: String) -> String {
        let paragraphs = content
            .components(separatedBy: .newlines)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    return ""
                }
                return "<p>\(trimmed.xmlEscaped)</p>"
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n    ")

        return """
        <h1>\(title.xmlEscaped)</h1>
            \(paragraphs)
        """
    }
}
