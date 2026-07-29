# Results

## Observed Behavior

PagePilot now accepts `.md` and `.markdown` files from Files/system share and Wi-Fi transfer. Imports are case-insensitive and continue through the existing Library and Reader flow after local conversion to EPUB.

The conversion preserves ordinary Markdown structure, including headings, paragraphs, emphasis, lists, links, block quotes, fenced code, horizontal rules, and tables. It derives the publication title from front matter, then the first H1, then the filename. Unsafe raw HTML, unsafe URL schemes, images, and local attachments are removed.

## Acceptance Evidence

- Regenerated the SPM project with `xcodegen --spec project.yml --project . --project-root .`.
- Ran `xcodebuild test -project PagePilot.xcodeproj -scheme PagePilot -destination 'platform=iOS Simulator,name=iPhone 17'`.
- Result: 130 tests executed, 0 failures.
- A permanent integration test opens the generated EPUB with Readium's real asset retriever and publication opener.
- `plutil -lint` passed for the iPhone Info.plist and both edited localization files.
- `git diff --check` passed.
- All six XcodeGen configurations declare Ink 0.6.0 and ReadiumZIPFoundation 3.0.1 consistently.

## Defect Found During Acceptance

The first implementation produced a non-empty archive but nested the EPUB payload under an extra directory. The initial unit assertion did not detect this. Independent Readium opening failed with `missingFile(path: "META-INF/container.xml")`.

The packager was replaced with direct ZIP entry creation at the archive root, with uncompressed `mimetype` first. The real Readium opening test now guards this contract and passes.

## User Feedback

Pending direct user feedback. This cycle establishes functional format support and compatibility with the existing Reader; it does not measure Markdown import demand.
