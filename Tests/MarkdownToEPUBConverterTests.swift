//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumZIPFoundation
import SwiftSoup
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

    func testTitleFromSetextH1() {
        let markdown = """
        Setext Title
        ============

        Body.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file"),
            "Setext Title"
        )
    }

    func testATXH1RequiresWhitespaceAfterHash() {
        let markdown = """
        #NoSpace

        Body.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file"),
            "file"
        )
    }

    func testFencedCodeHashIsNotTitle() {
        let markdown = """
        ```
        # Not A Title
        ```

        Real paragraph.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "code-notes"),
            "code-notes"
        )
    }

    // MARK: - Language

    func testLanguageFromFrontMatterLang() {
        let markdown = """
        ---
        lang: fr
        ---

        Content.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveLanguage(from: markdown, localeLanguageCode: "en"),
            "fr"
        )
    }

    func testLanguageFromFrontMatterLanguageKey() {
        let markdown = """
        ---
        language: ja-JP
        ---

        Content.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveLanguage(from: markdown, localeLanguageCode: "en"),
            "ja-JP"
        )
    }

    func testInvalidFrontMatterLanguageFallsBackToLocale() {
        let markdown = """
        ---
        language: not a tag!!!
        ---

        Content.
        """
        let result = MarkdownToEPUBConverter.deriveLanguage(
            from: markdown,
            localeLanguageCode: "de"
        )
        XCTAssertEqual(result, "de")
    }

    func testInvalidLangDoesNotBlockValidLanguage() {
        let markdown = """
        ---
        lang: !!!bad!!!
        language: fr
        ---

        Content.
        """
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveLanguage(from: markdown, localeLanguageCode: "en"),
            "fr"
        )
    }

    func testLanguageFallsBackToUndWhenLocaleUnavailable() {
        let markdown = "No front matter."
        let result = MarkdownToEPUBConverter.deriveLanguage(
            from: markdown,
            localeLanguageCode: nil
        )
        XCTAssertEqual(result, "und")
    }

    func testConvertOPFUsesFrontMatterLanguage() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        let markdown = """
        ---
        title: Lang Book
        lang: es
        ---

        # Lang Book

        Hola.
        """
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let archive = try await Archive(url: epubURL, accessMode: .read)
        let opfEntry = try await archive.get("OEBPS/content.opf")
        let entry = try XCTUnwrap(opfEntry, "missing OEBPS/content.opf in \(epubURL.path)")

        var opfData = Data()
        _ = try await archive.extract(entry, skipCRC32: true) { chunk in
            opfData.append(chunk)
        }
        let opf = try XCTUnwrap(String(data: opfData, encoding: .utf8))
        XCTAssertTrue(opf.contains("<dc:language>es</dc:language>"), opf)
    }

    // MARK: - Front matter boundaries

    func testLeadingHorizontalRuleIsNotFrontMatter() {
        let markdown = """
        ---

        Paragraph after a rule.

        ---

        More text.
        """
        XCTAssertTrue(MarkdownToEPUBConverter.frontMatterFields(in: markdown).isEmpty)
        let body = MarkdownToEPUBConverter.markdownBody(markdown)
        XCTAssertTrue(body.hasPrefix("---"), "leading HR must remain: \(body)")
        XCTAssertTrue(body.contains("Paragraph after a rule."), body)
    }

    func testUnclosedFrontMatterIsIgnored() {
        let markdown = """
        ---
        title: Never Closed

        # Heading

        Body.
        """
        XCTAssertTrue(MarkdownToEPUBConverter.frontMatterFields(in: markdown).isEmpty)
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file"),
            "Heading"
        )
    }

    func testMalformedFrontMatterWithoutKeyValueIsIgnored() {
        let markdown = """
        ---
        just some free text
        not key value
        ---

        # Real
        """
        XCTAssertTrue(MarkdownToEPUBConverter.frontMatterFields(in: markdown).isEmpty)
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file"),
            "Real"
        )
    }

    func testUnrelatedKeyValueDoesNotTriggerFrontMatterStrip() {
        // Leading HR + prose that looks like YAML but lacks title/lang/language.
        let markdown = """
        ---
        Note: hello
        author: Alice
        ---

        # Real Heading

        Body remains.
        """
        XCTAssertTrue(
            MarkdownToEPUBConverter.frontMatterFields(in: markdown).isEmpty,
            "unrelated keys must not authorize front-matter strip"
        )
        let body = MarkdownToEPUBConverter.markdownBody(markdown)
        XCTAssertTrue(body.hasPrefix("---"), "body must keep leading ---: \(body)")
        XCTAssertTrue(body.contains("Note: hello"), body)
        XCTAssertEqual(
            MarkdownToEPUBConverter.deriveTitle(from: markdown, filename: "file"),
            "Real Heading"
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

    func testStripsStyleAttributes() throws {
        let dirty = #"<p style="color:red" class="x">Styled</p>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)
        XCTAssertFalse(cleaned.lowercased().contains("style="), cleaned)
        XCTAssertTrue(cleaned.contains("Styled"), cleaned)
    }

    func testRejectsUnsafeHREFVariants() throws {
        let dirty = """
        <a href="JavaScript:alert(1)">mixed</a>
        <a href="java\nscript:alert(1)">newline</a>
        <a href="java\tscript:alert(1)">tab</a>
        <a href=" data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">data</a>
        <a href="https://safe.example">ok</a>
        """
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)
        let document = try SwiftSoup.parseBodyFragment(cleaned)
        guard let body = document.body() else {
            return XCTFail("missing body: \(cleaned)")
        }

        for label in ["mixed", "newline", "tab", "data"] {
            let anchors = try body.select("a").array().filter { (try? $0.text()) == label }
            XCTAssertFalse(anchors.isEmpty, "missing anchor text \(label): \(cleaned)")
            for anchor in anchors {
                XCTAssertFalse(
                    anchor.hasAttr("href"),
                    "\(label) must not keep href: \((try? anchor.outerHtml()) ?? "")"
                )
            }
        }

        let safe = try body.select("a").array().filter { (try? $0.text()) == "ok" }
        XCTAssertEqual(safe.count, 1, cleaned)
        let href = try safe[0].attr("href")
        XCTAssertEqual(href, "https://safe.example", cleaned)
    }

    func testMarkdownPipelineStripsDangerousLinkURLs() throws {
        let markdown = """
        [mixed](JavaScript:alert(1))
        [data](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)
        [ok](https://safe.example/path)
        """
        let cleaned = try MarkdownToEPUBConverter.renderAndSanitize(markdown)
        let document = try SwiftSoup.parseBodyFragment(cleaned)
        guard let body = document.body() else {
            return XCTFail("missing body: \(cleaned)")
        }

        for label in ["mixed", "data"] {
            let anchors = try body.select("a").array().filter { (try? $0.text()) == label }
            // Ink may render as bare text if URL is invalid, or as <a> without href after scrub.
            for anchor in anchors {
                XCTAssertFalse(
                    anchor.hasAttr("href"),
                    "\(label): \((try? anchor.outerHtml()) ?? "")"
                )
            }
        }

        let safe = try body.select("a").array().filter { (try? $0.text()) == "ok" }
        XCTAssertFalse(safe.isEmpty, cleaned)
        XCTAssertEqual(try safe[0].attr("href"), "https://safe.example/path", cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("javascript:"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("data:text/html"), cleaned)
    }

    func testLocalImageBecomesPlaceholderWithoutSrc() throws {
        let html = #"<p>Before</p><img src="images/cover.png" alt="cover photo"/><p>After</p>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(html)
        XCTAssertFalse(cleaned.lowercased().contains("<img"), cleaned)
        XCTAssertFalse(cleaned.contains("images/cover.png"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("src="), cleaned)
        XCTAssertTrue(cleaned.contains("[Image: cover photo]"), cleaned)
    }

    func testRemoteImageBecomesPlaceholderWithoutSrc() throws {
        let html = #"<img src="https://example.com/a.png" alt="remote"/>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(html)
        XCTAssertFalse(cleaned.lowercased().contains("<img"), cleaned)
        XCTAssertFalse(cleaned.contains("https://example.com"), cleaned)
        XCTAssertTrue(cleaned.contains("[Image: remote]"), cleaned)
    }

    func testImageWithEmptyAltBecomesGenericPlaceholder() throws {
        let html = #"<img src="local.png" alt=""/>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(html)
        XCTAssertTrue(cleaned.contains("[Image]"), cleaned)
        XCTAssertFalse(cleaned.contains("local.png"), cleaned)
    }

    func testMarkdownImageSyntaxBecomesPlaceholder() throws {
        let markdown = """
        # Pics

        ![cover](images/local-cover.png)

        ![remote](https://cdn.example.com/photo.jpg)
        """
        let cleaned = try MarkdownToEPUBConverter.renderAndSanitize(markdown)
        XCTAssertTrue(cleaned.contains("[Image: cover]"), cleaned)
        XCTAssertTrue(cleaned.contains("[Image: remote]"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("<img"), cleaned)
        XCTAssertFalse(cleaned.lowercased().contains("src="), cleaned)
        XCTAssertFalse(cleaned.contains("images/local-cover.png"), cleaned)
        XCTAssertFalse(cleaned.contains("cdn.example.com"), cleaned)
        XCTAssertFalse(cleaned.contains("https://"), cleaned)
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
    }

    func testSanitizeEscapesEntitiesAndSpecialCharacters() throws {
        let dirty = #"<p>A & B < C > D "quote" 'apos'</p>"#
        let cleaned = try MarkdownToEPUBConverter.sanitizeHTML(dirty)

        XCTAssertTrue(cleaned.contains("&amp;"), "expected & escaped: \(cleaned)")
        XCTAssertTrue(
            cleaned.contains("&lt;") || cleaned.contains("&#"),
            "expected < escaped: \(cleaned)"
        )
        XCTAssertFalse(
            cleaned.range(of: #"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;|#x[0-9A-Fa-f]+;)"#, options: .regularExpression) != nil,
            "unescaped ampersand is not XML-safe: \(cleaned)"
        )
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

    // MARK: - EPUB structure

    func testEPUBZipStructureHasUncompressedMimetypeFirst() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        try "# Structure\n\nChapter body.".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let epubURL = try await MarkdownToEPUBConverter.convert(from: url)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let archive = try await Archive(url: epubURL, accessMode: .read)
        let entries = try await archive.entries()
        XCTAssertFalse(entries.isEmpty, "archive should not be empty")

        let first = try XCTUnwrap(entries.first)
        XCTAssertEqual(first.path, "mimetype")
        XCTAssertFalse(first.isCompressed, "mimetype must be stored uncompressed")

        let paths = Set(entries.map(\.path))
        XCTAssertTrue(paths.contains("META-INF/container.xml"), "\(paths)")
        XCTAssertTrue(paths.contains("OEBPS/content.opf"), "\(paths)")
        XCTAssertTrue(paths.contains("OEBPS/chapter001.xhtml"), "\(paths)")
        XCTAssertTrue(paths.contains("OEBPS/style.css"), "\(paths)")
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

    func testConvertRejectsEmptyFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await MarkdownToEPUBConverter.convert(from: url)
            XCTFail("expected cannotReadFile for empty input")
        } catch let error as MarkdownToEPUBConverter.ConversionError {
            XCTAssertEqual(error, .cannotReadFile)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testConvertRejectsInvalidUTF8() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
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

    func testConvertRejectsFileTooLarge() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".md")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(MarkdownToEPUBConverter.maxMarkdownBytes + 1))
        try handle.close()

        do {
            _ = try await MarkdownToEPUBConverter.convert(from: url)
            XCTFail("expected fileTooLarge")
        } catch let error as MarkdownToEPUBConverter.ConversionError {
            XCTAssertEqual(error, .fileTooLarge)
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
