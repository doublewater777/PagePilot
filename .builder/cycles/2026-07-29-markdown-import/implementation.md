# Implementation

## Chosen Design

Convert Markdown at the existing `LibraryService.importPublication` boundary, then reuse the normal EPUB storage, database, Reader, progress, highlight, and Watch Page Turn paths.

Pipeline:

```text
.md / .markdown
  → security-scoped local read
  → Markdown parser
  → semantic HTML fragment
  → strict sanitization + XHTML normalization
  → shared minimal EPUB packager
  → existing Readium import/open path
```

This keeps Markdown out of the Reader layer and avoids a second navigation implementation.

## Implementation Scope

1. Add a pinned Swift Package dependency for a small, offline Markdown-to-HTML parser. Prefer Ink for its direct HTML output and compact integration; do not fetch or render through a network service.
2. Extract the reusable EPUB packaging portion of `TXTToEPUBConverter` so TXT behavior remains unchanged and Markdown can provide a sanitized semantic XHTML body without duplicating the package builder.
3. Add `MarkdownToEPUBConverter`:
   - Accept `.md` and `.markdown`, case-insensitively.
   - Require readable UTF-8 input; return localized conversion errors.
   - Render common Markdown constructs.
   - Use SwiftSoup to allow only safe reading tags and attributes.
   - Remove scripts, styles, forms, frames, embedded objects, event attributes, and unsafe URL schemes.
   - Do not package local sibling images in this increment.
   - Derive the Book title from front matter `title`, otherwise the first H1, otherwise the filename.
4. Route Markdown before Readium format sniffing in `LibraryService`.
5. Register Markdown in `iPhone/Info.plist` for `.md` and `.markdown` Open In/share handling using `net.daringfireball.markdown`.
6. Add `.md` and `.markdown` to Wi-Fi transfer's server allowlist and HTML file input.
7. Update onboarding's supported-format copy in English and Simplified Chinese.
8. Add focused unit tests for rendering, sanitization, title fallback, extension routing, and conversion errors.

## Non-goals

- No new Reader format module.
- No Markdown editor or source view.
- No remote rendering API.
- No local attachment traversal.
- No opportunistic refactor outside import/conversion code.

## Handoff Constraints

- Follow `AGENTS.md`; respond in Chinese and keep the diff surgical.
- Do not modify version/build numbers.
- Do not commit or push.
- Preserve all unrelated user changes.
- Generate the Xcode project from `Integrations/SPM/project.yml` only for verification; generated `project.yml` and `.xcodeproj` remain ignored.
- Return changed files, test/build commands, and any known limitation.
