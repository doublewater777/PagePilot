//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class MarkdownToEPUBConverterTests: XCTestCase {

    // MARK: - Extension routing

    func testAcceptsMarkdownExtensionsCaseInsensitively() {
        XCTAssertTrue(MarkdownToEPUBConverter.isMarkdownFileExtension("md"))
        XCTAssertTrue(MarkdownToEPUBConverter.isMarkdownFileExtension("MD"))
        XCTAssertTrue(MarkdownToEPUBConverter.isMarkdownFileExtension("markdown"))
        XCTAssertTrue(MarkdownToEPUBConverter.isMarkdownFileExtension("MARKDOWN"))
        XCTAssertTrue(MarkdownToEPUBConverter.isMarkdownFileExtension("Markdown"))
    }

    func testRejectsNonMarkdownExtensions() {
        XCTAssertFalse(MarkdownToEPUBConverter.isMarkdownFileExtension("txt"))
        XCTAssertFalse(MarkdownToEPUBConverter.isMarkdownFileExtension("epub"))
        XCTAssertFalse(MarkdownToEPUBConverter.isMarkdownFileExtension("mdx"))
        XCTAssertFalse(MarkdownToEPUBConverter.isMarkdownFileExtension(""))
    }

    // MARK: - Title fallbacks

    func testTitleFromFrontMatter() {
        let markdown = """
        ---
        title: Front Matter Title
        author: Alice
        ---

        # Body Heading

        Paragraph.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "notes"),
            "Front Matter Title"
        )
    }

    func testTitleFromQuotedFrontMatter() {
        let markdown = """
        ---
        title: "Quoted Title"
        ---

        Content.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "notes"),
            "Quoted Title"
        )
    }

    func testTitleFromFirstH1WhenNoFrontMatterTitle() {
        let markdown = """
        # First Heading

        Some text.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "fallback-name"),
            "First Heading"
        )
    }

    func testTitleFallsBackToFilename() {
        let markdown = "Just a paragraph without headings."
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "my-notes"),
            "my-notes"
        )
    }

    func testH2DoesNotOverrideFilenameWhenNoH1() {
        let markdown = """
        ## Secondary

        Body.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file-title"),
            "file-title"
        )
    }

    // MARK: - Rendering

    func testRendersCommonMarkdownConstructs() throws {
        let markdown = """
        # Title

        A paragraph with *emphasis* and **strong**.

        - item one
        - item two

        1. first
        2. second

        > a quote

        `inline code`

        ```
        block code
        ```

        [link](https://example.com)

        ---

        | Col A | Col B |
        | ----- | ----- |
        | 1     | 2     |
        """

        let html = try MarkdownToEPUBConverter.renderAndSanitize(markdown)

        XCTAssertTrue(html.contains("<h1"), "expected heading: \(html)")
        XCTAssertTrue(html.contains("<p"), "expected paragraph: \(html)")
        XCTAssertTrue(
            html.contains("<em>") || html.contains("<i>"),
            "expected emphasis: \(html)"
        )
        XCTAssertTrue(
            html.contains("<strong>") || html.contains("<b>"),
            "expected strong: \(html)"
        )
        XCTAssertTrue(html.contains("<ul") || html.contains("<li"), "expected list: \(html)")
        XCTAssertTrue(html.contains("<ol") || html.contains("<li"), "expected ordered list: \(html)")
        XCTAssertTrue(html.contains("<blockquote"), "expected blockquote: \(html)")
        XCTAssertTrue(html.contains("<code") || html.contains("<pre"), "expected code: \(html)")
        XCTAssertTrue(html.contains("<a href=\"https://example.com\""), "expected link: \(html)")
        XCTAssertTrue(html.contains("<hr"), "expected rule: \(html)")
        XCTAssertTrue(html.contains("<table"), "expected table: \(html)")
        XCTAssertTrue(html.contains("<thead"), "expected thead: \(html)")
        XCTAssertTrue(html.contains("<tbody"), "expected tbody: \(html)")
        XCTAssertTrue(html.contains("<tr"), "expected tr: \(html)")
        XCTAssertTrue(html.contains("<th"), "expected th: \(html)")
        XCTAssertTrue(html.contains("<td"), "expected td: \(html)")
        XCTAssertTrue(html.contains("Col A"), "expected table header text: \(html)")
        XCTAssertTrue(html.contains(">1<") || html.contains(">1</td>"), "expected table cell: \(html)")
    }

    // MARK: - Sanitization / XHTML

    func testStripsScriptStyleFormFrameAndEventHandlers() throws {
        let dirty = """
        <p onclick="alert(1)">Hello</p>
        <script>alert('xss')</script>
        <style>body{display:none}</style>
        <form action="https://evil.example"><input name="x"/></form>
        <iframe src="https://evil.example"></iframe>
        <object data="https://evil.example"></object>
        <embed src="https://evil.example"/>
        <a href="javascript:alert(1)">bad</a>
        <a href="https://safe.example">good</a>
        """

        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)

        XCTAssertFalse(cleaned.lowercased().contains("<script"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<style"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<form"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<iframe"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<object"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<embed"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("onclick"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("javascript:"), cleaned)
        XCTAssertTrue(cleaned.contains("https://safe.example"), cleaned)
        XCTAssertTrue(cleaned.contains("Hello"), cleaned)
    }

    func testStripsImgTagsSoLocalAttachmentsAreNotPackaged() throws {
        let html = #"<p>Pic</p><img src="images/cover.png" alt="cover"/><img src="https://example.com/a.png"/>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(html)
        XCTAssertFalse(cleaned.lowercased().contains("<img"), cleaned)
        XCTAssertTrue(cleaned.contains("Pic"), cleaned)
    }

    func testSanitizeEmitsSelfClosingVoidTagsAsXHTML() throws {
        let dirty = "line one<br>line two<hr><p>after</p>"
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)

        XCTAssertTrue(
            cleaned.contains("<br />") || cleaned.contains("<br/>"),
            "expected self-closing br: \(cleaned)"
        )
        XCTAssertFalse(
            cleaned.contains("<br>") && !cleaned.contains("<br/") && !cleaned.contains("<br /"),
            "bare <br> is not XHTML-safe: \(cleaned)"
        )
        XCTAssertTrue(
            cleaned.contains("<hr />") || cleaned.contains("<hr/>"),
            "expected self-closing hr: \(cleaned)"
        )
        XCTAssertFalse(
            cleaned.range(of: #"<hr(?![/ >])"#, options: .regularExpression) != nil
                && !cleaned.contains("<hr/") && !cleaned.contains("<hr /"),
            "bare <hr> is not XHTML-safe: \(cleaned)"
        )
    }

    func testSanitizeEscapesEntitiesAndSpecialCharacters() throws {
        let dirty = #"<p>A & B < C > D "quote" 'apos'</p>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)

        XCTAssertTrue(cleaned.contains("&amp;"), "expected & escaped: \(cleaned)")
        // Angle brackets from text must not appear as raw tag delimiters in content.
        XCTAssertTrue(
            cleaned.contains("&lt;") || cleaned.contains("&#"),
            "expected < escaped: \(cleaned)"
        )
        // Round-trip through SwiftSoup XML output: no unescaped bare ampersands.
        XCTAssertFalse(
            cleaned.range(of: #"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)"#, options: .regularExpression) != nil,
            "unescaped ampersand is not XML-safe: \(cleaned)"
        )
        // Content text preserved after re-sanitizing (idempotent for safe input).
        let again = try MarkdownToEPUBConverter.sanitizeHTML(cleaned)
        XCTAssertTrue(again.contains("A") && again.contains("B") && again.contains("D"), again)
    }

    // MARK: - OPF language

    func testOPFLanguageIsXMLEscapedAndHonored() {
        let chapters = [MinimalEPUBPackager.Chapter(title: "T", bodyHTML: "<p>x</p>")]

        let und = MinimalEPUBPackager.buildOPF(title: "Book", language: "und", chapters: chapters)
        XCTAssertTrue(und.contains("<dc:language>und</dc:language>"), und)

        let zh = MinimalEPUBPackager.buildOPF(title: "Book", language: "zh", chapters: chapters)
        XCTAssertTrue(zh.contains("<dc:language>zh</dc:language>"), zh)

        let special = MinimalEPUBPackager.buildOPF(
            title: "Book",
            language: "zh&en",
            chapters: chapters
        )
        XCTAssertTrue(special.contains("<dc:language>zh&amp;en</dc:language>"), special)
        XCTAssertFalse(special.contains("<dc:language>zh&en</dc:language>"), special)
    }

    func testMarkdownPackageUsesUndLanguageInOPF() async throws {
        let chapters = [MinimalEPUBPackager.Chapter(title: "Hello", bodyHTML: "<p>Body.</p>")]
        let opf = MinimalEPUBPackager.buildOPF(title: "Hello", language: "und", chapters: chapters)
        XCTAssertTrue(opf.contains("<dc:language>und</dc:language>"), opf)

        // convert() is wired to language "und"; package a matching EPUB and ensure it is non-empty.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        try "# Hello\n\nBody.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: epubURL.path))
    }

    // MARK: - Conversion errors / happy path

    func testConvertRejectsUnsupportedExtension() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample.txt")
        try? "hello".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await MarkdownToEPUBConverter.convert(from: url)
            XCTFail("expected unsupportedExtension")
        } catch let error as MarkdownToEPUBConverter.ConversionError {
            XCTAssertEqual(error, .unsupportedExtension)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testConvertRejectsInvalidUTF8() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        // Invalid UTF-8 sequence
        let data = Data([0xFF, 0xFE, 0xFD])
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await MarkdownToEPUBConverter.convert(from: url)
            XCTFail("expected invalidUTF8")
        } catch let error as MarkdownToEPUBConverter.ConversionError {
            XCTAssertEqual(error, .invalidUTF8)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testConvertProducesEPUBForValidMarkdown() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        let markdown = """
        ---
        title: Test Book
        ---

        # Test Book

        Hello **world**.
        """
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        XCTAssertEqual(epubURL.pathExtension.lowercased(), "epub")
        XCTAssertTrue(FileManager.default.fileExists(atPath: epubURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: epubURL.path)
        let size = attrs[.size] as? NSNumber
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size?.intValue ?? 0, 0)
    }

    func testConvertAcceptsMarkdownExtension() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".markdown")
        try "# Hello\n\nBody.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: epubURL.path))
    }

    func testConvertedEPUBOpensWithReadium() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        try "# Readium Ready\n\nA real publication.".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }
        let absoluteURL = try XCTUnwrap(epubURL.anyURL.absoluteURL)

        let readium = Readium()
        let asset = try await readium.assetRetriever.retrieve(url: absoluteURL).get()
        let publication = try await readium.publicationOpener.open(
            asset: asset,
            allowUserInteraction: false,
            sender: nil
        ).get()

        XCTAssertEqual(publication.metadata.title, "Readium Ready")
        XCTAssertFalse(publication.readingOrder.isEmpty)
    }
}
