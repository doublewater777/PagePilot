//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared
import ReadiumZIPFoundation

/// Builds a minimal EPUB 3 package from pre-rendered XHTML chapter bodies.
/// Used by TXT and Markdown converters so package structure stays in one place.
enum MinimalEPUBPackager {

    struct Chapter {
        let title: String
        /// Safe XHTML fragment for the chapter body (not re-escaped).
        let bodyHTML: String
    }

    enum PackagerError: Error {
        case epubCreationFailed(Error)
    }

    /// Creates a temporary `.epub` and returns its file URL.
    /// - Parameter language: BCP 47 language tag written to `dc:language` (XML-escaped).
    static func package(title: String, language: String, chapters: [Chapter]) async throws -> URL {
        let epubDir = Paths.makeTemporaryURL().url
        // Always remove the staging directory on success or failure.
        defer { try? FileManager.default.removeItem(at: epubDir) }

        let metaInf = epubDir.appendingPathComponent("META-INF")
        let oebps = epubDir.appendingPathComponent("OEBPS")
        let fm = FileManager.default

        try fm.createDirectory(at: metaInf, withIntermediateDirectories: true)
        try fm.createDirectory(at: oebps, withIntermediateDirectories: true)

        try "application/epub+zip".write(
            to: epubDir.appendingPathComponent("mimetype"),
            atomically: true,
            encoding: .utf8
        )
        try containerXML.write(
            to: metaInf.appendingPathComponent("container.xml"),
            atomically: true,
            encoding: .utf8
        )

        let opf = buildOPF(title: title, language: language, chapters: chapters)
        try opf.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)

        let toc = buildTOC(title: title, chapters: chapters)
        try toc.write(to: oebps.appendingPathComponent("toc.xhtml"), atomically: true, encoding: .utf8)

        try styleCSS.write(to: oebps.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)

        for (index, chapter) in chapters.enumerated() {
            let xhtml = buildChapterXHTML(chapter: chapter)
            let filename = "chapter\(String(format: "%03d", index + 1)).xhtml"
            try xhtml.write(to: oebps.appendingPathComponent(filename), atomically: true, encoding: .utf8)
        }

        let epubURL = epubDir.appendingPathExtension("epub")
        do {
            try await zipDirectory(at: epubDir, to: epubURL)
        } catch {
            // Do not leave a partial/corrupt EPUB on disk.
            try? fm.removeItem(at: epubURL)
            throw error
        }

        return epubURL
    }

    // MARK: - Templates

    private static let containerXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    /// Builds the package OPF document. Internal for unit tests.
    static func buildOPF(title: String, language: String, chapters: [Chapter]) -> String {
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
            <dc:language>\(language.xmlEscaped)</dc:language>
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
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
          <title>\(chapter.title.xmlEscaped)</title>
          <link rel="stylesheet" type="text/css" href="style.css"/>
        </head>
        <body>
          <div class="chapter-content">
            \(chapter.bodyHTML)
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
    h1, h2, h3, h4, h5, h6 {
        margin: 1em 0 0.5em;
        line-height: 1.3;
    }
    h1 {
        font-size: 1.4em;
        text-align: center;
    }
    h2 { font-size: 1.25em; }
    h3 { font-size: 1.1em; }
    p {
        text-indent: 2em;
        margin: 0.5em 0;
    }
    .chapter-content {
        text-align: justify;
    }
    ul, ol {
        margin: 0.5em 0;
        padding-left: 1.5em;
    }
    li { margin: 0.25em 0; }
    blockquote {
        margin: 0.75em 0;
        padding-left: 1em;
        border-left: 3px solid #ccc;
        color: #555;
    }
    pre {
        font-family: ui-monospace, Menlo, monospace;
        font-size: 0.9em;
        background: #f5f5f5;
        padding: 0.75em;
        overflow-x: auto;
        white-space: pre-wrap;
    }
    code {
        font-family: ui-monospace, Menlo, monospace;
        font-size: 0.9em;
    }
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 0.75em 0;
    }
    th, td {
        border: 1px solid #ddd;
        padding: 0.4em 0.6em;
    }
    hr {
        border: none;
        border-top: 1px solid #ccc;
        margin: 1.5em 0;
    }
    a { color: #007aff; }
    """

    // MARK: - ZIP

    /// Packs `sourceURL` contents at the ZIP root (not under a parent folder).
    /// Writes `mimetype` first with store-only compression to satisfy EPUB OCF.
    private static func zipDirectory(at sourceURL: URL, to destinationURL: URL) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        do {
            let archive = try await Archive(url: destinationURL, accessMode: .create)

            // EPUB OCF: mimetype must be the first entry and must not be compressed.
            try await archive.addEntry(
                with: "mimetype",
                relativeTo: sourceURL,
                compressionMethod: .none
            )

            var relativePaths: [String] = []
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
            guard let enumerator = fm.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                throw PackagerError.epubCreationFailed(
                    NSError(
                        domain: "MinimalEPUBPackager",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not enumerate EPUB staging directory"]
                    )
                )
            }

            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true else { continue }
                let relative = relativePath(of: fileURL, to: sourceURL)
                guard relative != "mimetype", !relative.isEmpty else { continue }
                relativePaths.append(relative)
            }

            // Stable, deterministic order after mimetype.
            relativePaths.sort()

            for path in relativePaths {
                try await archive.addEntry(
                    with: path,
                    relativeTo: sourceURL,
                    compressionMethod: .deflate
                )
            }
        } catch let error as PackagerError {
            throw error
        } catch {
            throw PackagerError.epubCreationFailed(error)
        }
    }

    private static func relativePath(of fileURL: URL, to baseURL: URL) -> String {
        let base = baseURL.standardizedFileURL.path
        let full = fileURL.standardizedFileURL.path
        guard full.hasPrefix(base + "/") else {
            return fileURL.lastPathComponent
        }
        return String(full.dropFirst(base.count + 1))
    }
}

// MARK: - String XML Escaping

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
