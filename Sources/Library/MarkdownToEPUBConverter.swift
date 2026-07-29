//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import Ink
import SwiftSoup

/// Converts a Markdown (.md / .markdown) file into a minimal EPUB 3 package
/// that reuses the existing Readium import/open path.
final class MarkdownToEPUBConverter {

    enum ConversionError: LocalizedError, Equatable {
        case unsupportedExtension
        case cannotReadFile
        case invalidUTF8
        case sanitizationFailed
        case epubCreationFailed(String)
        case invalidOutputURL

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension:
                return NSLocalizedString("markdown_error_unsupported_extension", comment: "")
            case .cannotReadFile:
                return NSLocalizedString("markdown_error_cannot_read", comment: "")
            case .invalidUTF8:
                return NSLocalizedString("markdown_error_encoding", comment: "")
            case .sanitizationFailed:
                return NSLocalizedString("markdown_error_sanitization", comment: "")
            case .epubCreationFailed(let detail):
                return String(
                    format: NSLocalizedString("markdown_error_conversion", comment: ""),
                    detail
                )
            case .invalidOutputURL:
                return NSLocalizedString("markdown_error_invalid_output", comment: "")
            }
        }

        static func == (lhs: ConversionError, rhs: ConversionError) -> Bool {
            switch (lhs, rhs) {
            case (.unsupportedExtension, .unsupportedExtension),
                 (.cannotReadFile, .cannotReadFile),
                 (.invalidUTF8, .invalidUTF8),
                 (.sanitizationFailed, .sanitizationFailed),
                 (.invalidOutputURL, .invalidOutputURL):
                return true
            case let (.epubCreationFailed(a), .epubCreationFailed(b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Public

    static func isMarkdownFileExtension(_ pathExtension: String) -> Bool {
        let ext = pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// Converts the Markdown file at `sourceURL` into an EPUB file.
    /// Returns the URL of the generated `.epub` in the temporary directory.
    static func convert(from sourceURL: URL) async throws -> URL {
        guard isMarkdownFileExtension(sourceURL.pathExtension) else {
            throw ConversionError.unsupportedExtension
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw ConversionError.cannotReadFile
        }

        guard !data.isEmpty else {
            throw ConversionError.cannotReadFile
        }

        guard let markdown = String(data: data, encoding: .utf8) else {
            throw ConversionError.invalidUTF8
        }

        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let title = deriveTitle(from: markdown, filename: filename)
        let bodyHTML = try renderAndSanitize(markdown)

        do {
            return try await MinimalEPUBPackager.package(
                title: title,
                language: "und",
                chapters: [
                    .init(title: title, bodyHTML: bodyHTML),
                ]
            )
        } catch let error as MinimalEPUBPackager.PackagerError {
            switch error {
            case .epubCreationFailed(let underlying):
                throw ConversionError.epubCreationFailed(underlying.localizedDescription)
            }
        } catch {
            throw ConversionError.epubCreationFailed(error.localizedDescription)
        }
    }

    // MARK: - Title

    /// Title order: front matter `title` → first H1 → filename.
    static func deriveTitle(from markdown: String, filename: String) -> String {
        if let frontMatterTitle = frontMatterTitle(in: markdown) {
            let trimmed = frontMatterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let heading = firstH1(in: markdownBody(markdown)) {
            let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return filename
    }

    // MARK: - Render + Sanitize

    /// Renders Markdown to HTML, then sanitizes to a safe XHTML fragment.
    static func renderAndSanitize(_ markdown: String) throws -> String {
        let body = markdownBody(markdown)
        let html = MarkdownParser().html(from: body)
        return try sanitizeHTML(html)
    }

    /// Keeps only safe reading tags/attributes; strips scripts, styles, forms,
    /// frames, embeds, event handlers, and unsafe URL schemes.
    /// Output uses XML syntax so void tags are self-closing XHTML.
    static func sanitizeHTML(_ html: String) throws -> String {
        let safelist = readingSafelist()
        let outputSettings = OutputSettings()
            .syntax(syntax: .xml)
            .prettyPrint(pretty: false)
            .escapeMode(Entities.EscapeMode.xhtml)
        guard let cleaned = try clean(html, "", safelist, outputSettings) else {
            throw ConversionError.sanitizationFailed
        }
        return cleaned
    }

    // MARK: - Front matter / body

    private static func markdownBody(_ markdown: String) -> String {
        guard let range = frontMatterRange(in: markdown) else {
            return markdown
        }
        return String(markdown[range.upperBound...])
    }

    private static func frontMatterTitle(in markdown: String) -> String? {
        guard let range = frontMatterRange(in: markdown) else {
            return nil
        }

        let block = String(markdown[range])
        let lines = block.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("title:") else { continue }
            var value = String(trimmed.dropFirst("title:".count))
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")),
                value.count >= 2
            {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    /// Returns the range of a leading YAML front-matter block including delimiters.
    private static func frontMatterRange(in markdown: String) -> Range<String.Index>? {
        let text = markdown
        guard text.hasPrefix("---") else { return nil }

        let afterOpen = text.index(text.startIndex, offsetBy: 3)
        guard afterOpen < text.endIndex else { return nil }

        // Require a newline right after the opening ---
        var cursor = afterOpen
        if text[cursor] == "\r" {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == "\n" else { return nil }
        cursor = text.index(after: cursor)

        guard let closeRange = text.range(
            of: #"\n---[ \t]*(\r?\n|$)"#,
            options: .regularExpression,
            range: cursor ..< text.endIndex
        ) else {
            return nil
        }

        return text.startIndex ..< closeRange.upperBound
    }

    private static func firstH1(in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            // Exactly one leading # for H1 (not ##)
            let withoutHash = trimmed.drop(while: { $0 == "#" })
            let hashCount = trimmed.count - withoutHash.count
            guard hashCount == 1 else {
                if hashCount > 1 { continue }
                continue
            }
            var title = String(withoutHash).trimmingCharacters(in: .whitespaces)
            // Strip optional trailing ATX closing hashes
            if let close = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
                title = String(title[..<close.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }
            return title.isEmpty ? nil : title
        }
        return nil
    }

    // MARK: - Safelist

    private static func readingSafelist() -> Whitelist {
        // Built from none() so scripts/styles/forms/frames/objects stay out.
        let list = Whitelist.none()
        do {
            _ = try list
                .addTags(
                    "a", "b", "blockquote", "br", "caption", "cite", "code",
                    "col", "colgroup", "dd", "del", "div", "dl", "dt", "em",
                    "h1", "h2", "h3", "h4", "h5", "h6", "hr", "i", "li",
                    "ol", "p", "pre", "q", "s", "small", "span", "strong",
                    "sub", "sup", "table", "tbody", "td", "tfoot", "th",
                    "thead", "tr", "u", "ul"
                )
                .addAttributes("a", "href", "title")
                .addAttributes("th", "colspan", "rowspan", "scope", "align")
                .addAttributes("td", "colspan", "rowspan", "align")
                .addAttributes("col", "span")
                .addAttributes("colgroup", "span")
                .addProtocols("a", "href", "http", "https", "mailto")
        } catch {
            // Whitelist mutations are effectively infallible for fixed tags.
        }
        return list
    }
}
