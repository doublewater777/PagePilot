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

    /// Soft ceiling for Markdown sources (50 MiB). Checked via attributes first.
    static let maxMarkdownBytes: Int64 = 50 * 1024 * 1024

    enum ConversionError: LocalizedError, Equatable {
        case unsupportedExtension
        case cannotReadFile
        case invalidUTF8
        case fileTooLarge
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
            case .fileTooLarge:
                return NSLocalizedString("markdown_error_file_too_large", comment: "")
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
                 (.fileTooLarge, .fileTooLarge),
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

        // Fast reject via file attributes before allocating a large buffer.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attrs[.size] as? NSNumber,
           size.int64Value > maxMarkdownBytes
        {
            throw ConversionError.fileTooLarge
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

        if data.count > maxMarkdownBytes {
            throw ConversionError.fileTooLarge
        }

        guard let markdown = String(data: data, encoding: .utf8) else {
            throw ConversionError.invalidUTF8
        }

        let filename = sourceURL.deletingPathExtension().lastPathComponent
        let title = deriveTitle(from: markdown, filename: filename)
        let language = deriveLanguage(from: markdown)
        let bodyHTML = try renderAndSanitize(markdown)

        do {
            return try await MinimalEPUBPackager.package(
                title: title,
                language: language,
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
        if let frontMatterTitle = frontMatterFields(in: markdown)["title"] {
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

    // MARK: - Language

    /// Language order: front matter `lang`, then `language` (each tried for validity),
    /// then locale language code, then `und`.
    /// - Parameter localeLanguageCode: Override for tests; defaults to the device language code.
    static func deriveLanguage(
        from markdown: String,
        localeLanguageCode: String? = Locale.current.language.languageCode?.identifier
    ) -> String {
        let fields = frontMatterFields(in: markdown)
        // Try keys separately so an invalid `lang` does not block a valid `language`.
        if let raw = fields["lang"], let normalized = normalizedLanguageTag(raw) {
            return normalized
        }
        if let raw = fields["language"], let normalized = normalizedLanguageTag(raw) {
            return normalized
        }

        if let code = localeLanguageCode, let normalized = normalizedLanguageTag(code) {
            return normalized
        }

        return "und"
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
    /// Images become plain-text placeholders; no src is retained.
    /// Output uses XML syntax so void tags are self-closing XHTML.
    static func sanitizeHTML(_ html: String) throws -> String {
        let withImagePlaceholders = try replaceImagesWithPlaceholders(in: html)
        let safelist = readingSafelist()
        let outputSettings = OutputSettings()
            .syntax(syntax: .xml)
            .prettyPrint(pretty: false)
            .escapeMode(Entities.EscapeMode.xhtml)
        guard let cleaned = try clean(withImagePlaceholders, "", safelist, outputSettings) else {
            throw ConversionError.sanitizationFailed
        }
        // Defense in depth: drop hrefs whose scheme is unsafe after whitespace/control stripping
        // (e.g. `java\nscript:`, mixed case, leading spaces before `data:`).
        return try scrubUnsafeAnchorHrefs(in: cleaned)
    }

    // MARK: - Front matter / body

    /// Keys that authorize treating a leading `---` block as front matter.
    private static let frontMatterTriggerKeys: Set<String> = ["title", "lang", "language"]

    /// Shared front-matter boundary: only a leading `---` block that closes and
    /// contains at least one supported trigger field (`title`, `lang`, `language`).
    static func frontMatterFields(in markdown: String) -> [String: String] {
        guard let parsed = parseFrontMatter(markdown) else { return [:] }
        return parsed.fields
    }

    /// Body after removing a recognized front-matter block (if any).
    static func markdownBody(_ markdown: String) -> String {
        guard let parsed = parseFrontMatter(markdown) else {
            return markdown
        }
        return String(markdown[parsed.range.upperBound...])
    }

    private struct ParsedFrontMatter {
        let fields: [String: String]
        let range: Range<String.Index>
    }

    /// Parses a leading YAML-like front-matter fence.
    /// Requires: starts with `---`, newline, closing `---`, and at least one of
    /// `title` / `lang` / `language`. Other key-value lines may still be parsed
    /// once the block is recognized, but cannot alone trigger stripping.
    private static func parseFrontMatter(_ markdown: String) -> ParsedFrontMatter? {
        let text = markdown
        guard text.hasPrefix("---") else { return nil }

        let afterOpen = text.index(text.startIndex, offsetBy: 3)
        guard afterOpen < text.endIndex else { return nil }

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

        let inner = String(text[cursor ..< closeRange.lowerBound])
        let fields = parseSimpleYAMLFields(inner)
        // Only supported metadata keys authorize stripping (avoid `Note: hello` etc.).
        guard fields.keys.contains(where: { frontMatterTriggerKeys.contains($0) }) else {
            return nil
        }

        let fullRange = text.startIndex ..< closeRange.upperBound
        return ParsedFrontMatter(fields: fields, range: fullRange)
    }

    /// Very small `key: value` extractor (no YAML dependency).
    private static func parseSimpleYAMLFields(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard !key.isEmpty,
                  key.range(of: #"^[A-Za-z_][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
            else { continue }

            var value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")),
                value.count >= 2
            {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }
        return fields
    }

    /// First ATX (`# `) or Setext H1 outside fenced code blocks.
    static func firstH1(in markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        var inFence = false
        var fenceMarker: Character?

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = fenceOpenClose(trimmed) {
                if !inFence {
                    inFence = true
                    fenceMarker = fence
                } else if fenceMarker == fence {
                    inFence = false
                    fenceMarker = nil
                }
                index += 1
                continue
            }

            if inFence {
                index += 1
                continue
            }

            // ATX H1: exactly one # followed by whitespace.
            if trimmed.hasPrefix("#") {
                let withoutHash = trimmed.drop(while: { $0 == "#" })
                let hashCount = trimmed.count - withoutHash.count
                if hashCount == 1,
                   let first = withoutHash.first,
                   first.isWhitespace
                {
                    var title = String(withoutHash).trimmingCharacters(in: .whitespaces)
                    if let close = title.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
                        title = String(title[..<close.lowerBound])
                            .trimmingCharacters(in: .whitespaces)
                    }
                    if !title.isEmpty {
                        return title
                    }
                }
                index += 1
                continue
            }

            // Setext H1: text line followed by === underline.
            if !trimmed.isEmpty,
               index + 1 < lines.count
            {
                let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if underline.range(of: #"^={3,}\s*$"#, options: .regularExpression) != nil {
                    return trimmed
                }
            }

            index += 1
        }
        return nil
    }

    private static func fenceOpenClose(_ trimmed: String) -> Character? {
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }
        return trimmed.first
    }

    private static func normalizedLanguageTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Simple BCP-47-ish tag: letters, digits, hyphen; no spaces/control chars.
        guard trimmed.range(of: #"^[A-Za-z]{1,8}(-[A-Za-z0-9]{1,8})*$"#, options: .regularExpression) != nil
        else {
            return nil
        }
        return trimmed
    }

    // MARK: - Images

    /// Replaces `<img>` with a plain-text placeholder so no network/local fetch occurs.
    private static func replaceImagesWithPlaceholders(in html: String) throws -> String {
        let document = try SwiftSoup.parseBodyFragment(html)
        guard let body = document.body() else { return html }

        let images = try body.select("img")
        for img in images.array() {
            let alt = (try? img.attr("alt"))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let placeholder = alt.isEmpty ? "[Image]" : "[Image: \(alt)]"
            try img.replaceWith(TextNode(placeholder, nil))
        }
        return try body.html()
    }

    // MARK: - Anchor href scrub

    /// Removes `href` when the scheme is not http/https/mailto after stripping
    /// whitespace and control characters used to smuggle unsafe schemes.
    private static func scrubUnsafeAnchorHrefs(in html: String) throws -> String {
        let document = try SwiftSoup.parseBodyFragment(html)
        guard let body = document.body() else { return html }

        for anchor in try body.select("a").array() {
            guard anchor.hasAttr("href") else { continue }
            let href = try anchor.attr("href")
            if !isAllowedHref(href) {
                try anchor.removeAttr("href")
            }
        }

        let outputSettings = OutputSettings()
            .syntax(syntax: .xml)
            .prettyPrint(pretty: false)
            .escapeMode(Entities.EscapeMode.xhtml)
        document.outputSettings(outputSettings)
        return try body.html()
    }

    /// Allowed schemes only: http, https, mailto (case-insensitive; ignores whitespace/controls).
    static func isAllowedHref(_ href: String) -> Bool {
        let compacted = String(
            href.unicodeScalars
                .filter { scalar in
                    !CharacterSet.whitespacesAndNewlines.contains(scalar)
                        && scalar.value >= 0x20
                        && scalar.value != 0x7F
                }
                .map { Character($0) }
        )
        let trimmed = compacted.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("mailto:")
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
