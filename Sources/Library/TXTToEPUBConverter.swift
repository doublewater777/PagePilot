//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared

/// Converts a plain text (.txt) file into a minimal EPUB 3 package
/// that can be opened by Readium's publication opener.
///
/// Features:
/// - Automatic encoding detection (UTF-8, GBK, GB18030, Latin-1)
/// - Chapter splitting by common Chinese/English chapter patterns
/// - Proper EPUB 3 structure with navigation document
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

    /// Converts the TXT file at `sourceURL` into an EPUB file.
    /// Returns the URL of the generated `.epub` file in the temporary directory.
    static func convert(from sourceURL: URL) throws -> URL {
        let text = try readTextFile(at: sourceURL)
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let chapters = splitIntoChapters(text: text, fallbackTitle: title)
        return try buildEPUB(title: title, chapters: chapters)
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

    // MARK: - EPUB Building

    private static func buildEPUB(title: String, chapters: [Chapter]) throws -> URL {
        let epubDir = Paths.makeTemporaryURL().url
        let metaInf = epubDir.appendingPathComponent("META-INF")
        let oebps = epubDir.appendingPathComponent("OEBPS")

        let fm = FileManager.default
        try fm.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)

        // mimetype (must be first, uncompressed in a real EPUB zip, but Readium handles this)
        try "application/epub+zip".write(to: epubDir.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)

        // META-INF/container.xml
        try containerXML.write(to: metaInf.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

        // OEBPS/content.opf
        let opf = buildOPF(title: title, chapters: chapters)
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        // OEBPS/toc.xhtml (navigation document)
        let toc = buildTOC(title: title, chapters: chapters)
        try toc.write(to: oebps.appendingPathComponent("toc.xhtml"), atomically: true, encoding: .utf8)

        // OEBPS/style.css
        try styleCSS.write(to: oebps.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)

        // OEBPS/chapterXXX.xhtml
        for (index, chapter) in chapters.enumerated() {
            let xhtml = buildChapterXHTML(chapter: chapter)
            let filename = "chapter\(String(format: "%03d", index + 1)).xhtml"
            try xhtml.write(to: oebps.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }

        // Zip into .epub
        let epubURL = epubDir.appendingPathExtension("epub")
        try zipDirectory(at: epubDir, to: epubURL)

        // Clean up unzipped directory
        try? fm.removeItem(at: epubDir)

        return epubURL
    }

    // MARK: - EPUB Templates

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static func buildOPF(title: String, chapters: [Chapter]) -> String {
        let uuid = UUID().uuidString
        let date = ISO8601DateFormatter().string(from: Date())

        var manifestItems = """
            <item id="toc" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="style" href="style.css" media-type="text/css"/>
        """

        var spineItems = ""

        for (index, _) in chapters.enumerated() {
            let id = "chapter\(String(format: "%03d", index + 1))"
            let href = "\(id).xhtml"
            manifestItems += "\n        <item id=\"\(id)\" href=\"\(href)\" media-type=\"application/xhtml+xml\"/>"
            spineItems += "\n        <itemref idref=\"\(id)\"/>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:\(uuid)</dc:identifier>
            <dc:title>\(title.xmlEscaped)</dc:title>
            <dc:language>zh</dc:language>
            <dc:creator>Unknown</dc:creator>
            <meta property="dcterms:modified">\(date)</meta>
          </metadata>
          <manifest>
            \(manifestItems)
          </manifest>
          <spine>
            \(spineItems)
          </spine>
        </package>
        """
    }

    private static func buildTOC(title: String, chapters: [Chapter]) -> String {
        var navItems = ""
        for (index, chapter) in chapters.enumerated() {
            let href = "chapter\(String(format: "%03d", index + 1)).xhtml"
            navItems += "        <li><a href=\"\(href)\">\(chapter.title.xmlEscaped)</a></li>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
          <title>\(title.xmlEscaped)</title>
        </head>
        <body>
          <nav epub:type="toc">
            <h1>\(title.xmlEscaped)</h1>
            <ol>
        \(navItems)    </ol>
          </nav>
        </body>
        </html>
        """
    }

    private static func buildChapterXHTML(chapter: Chapter) -> String {
        // Convert plain text paragraphs to HTML paragraphs
        let paragraphs = chapter.content
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
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>\(chapter.title.xmlEscaped)</title>
          <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
          <h1>\(chapter.title.xmlEscaped)</h1>
          <div class="chapter-content">
            \(paragraphs)
          </div>
        </body>
        </html>
        """
    }

    private static let styleCSS = """
    body {
        font-family: -apple-system, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
        line-height: 1.8;
        padding: 1em;
    }
    h1 {
        font-size: 1.4em;
        margin-bottom: 1em;
        text-align: center;
    }
    p {
        text-indent: 2em;
        margin: 0.5em 0;
    }
    .chapter-content {
        text-align: justify;
    }
    """

    // MARK: - ZIP

    private static func zipDirectory(at sourceURL: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var zipError: Error?

        coordinator.coordinate(readingItemAt: sourceURL, options: .forUploading, error: &error) { zipURL in
            do {
                try FileManager.default.moveItem(at: zipURL, to: destinationURL)
            } catch {
                zipError = error
            }
        }

        if let error = error {
            throw ConversionError.epubCreationFailed(error)
        }
        if let zipError = zipError {
            throw ConversionError.epubCreationFailed(zipError)
        }
    }
}

// MARK: - String XML Escaping

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
