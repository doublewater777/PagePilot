# Results

## Status

**completed / pass** — PR review fixes independently verified.

## Observed Behavior

PagePilot accepts `.md` and `.markdown` from Files/system share and Wi-Fi transfer. Imports are case-insensitive and continue through the existing Library and Reader flow after local conversion to EPUB.

Conversion preserves ordinary Markdown structure (headings including Setext H1, paragraphs, emphasis, lists, links, block quotes, fenced code, horizontal rules, tables). Title: front matter → H1 → filename. Language: front matter `lang`/`language` → device language → `und`. Images become text placeholders; unsafe HTML/URL schemes are stripped. Sources over 50 MiB are rejected. Leading `---` is only treated as front matter when it is a closed block with simple key-value metadata.

## Acceptance Evidence (latest review-fix iteration)

Targeted:

```text
xcodebuild test -project PagePilot.xcodeproj -scheme PagePilot \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PagePilotTests/MarkdownToEPUBConverterTests
```

Full suite (required):

```text
xcodegen --spec project.yml --project . --project-root .
xcodebuild test -project PagePilot.xcodeproj -scheme PagePilot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

- Targeted `MarkdownToEPUBConverterTests`: **Executed 40 tests, with 0 failures** → `TEST SUCCEEDED` (includes href removal, ZIP structure, image fallback, and Readium open).
- Full suite: **Executed 151 tests, with 0 failures (0 unexpected)** → `TEST SUCCEEDED`.
- `plutil -lint` passed for the edited Info.plist and both localization files.
- `git diff --check` passed.
- Dependency licenses were verified from resolved packages: Ink and ReadiumZIPFoundation are MIT; both are offline at runtime. Readium already uses the same ZIPFoundation product, so the direct dependency exposes packaging APIs without adding a second SPM product.

## Defects Found During Acceptance

1. **ZIP nesting (prior):** `NSFileCoordinator.forUploading` nested payload; Readium failed with `missingFile(META-INF/container.xml)`. Fixed with ReadiumZIPFoundation root packaging + structure test + real Readium open test.
2. **PR review reopening:** packager cleanup on failure, sanitizer contracts, language/H1/front-matter/image/size edge cases — addressed in this iteration.

## User Feedback

Pending direct user feedback. This cycle establishes functional format support; it does not measure Markdown import demand.
