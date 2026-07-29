# Implementation

## Chosen Design

Convert Markdown at the existing `LibraryService.importPublication` boundary, then reuse the normal EPUB storage, database, Reader, progress, highlight, and Watch Page Turn paths.

Pipeline:

```text
.md / .markdown
  → security-scoped local read (max 50 MiB)
  → front-matter parse (title / lang|language only when valid key-value block)
  → Markdown parser (Ink, offline)
  → semantic HTML fragment
  → image placeholders + strict sanitization + XHTML (XML syntax)
  → shared minimal EPUB packager (root-level ZIP, uncompressed mimetype first)
  → existing Readium import/open path
```

This keeps Markdown out of the Reader layer and avoids a second navigation implementation.

## Implementation Scope

1. Add a pinned Swift Package dependency for a small, offline Markdown-to-HTML parser (Ink 0.6.0). No network at runtime.
2. Extract the reusable EPUB packaging portion of `TXTToEPUBConverter` so TXT behavior remains unchanged and Markdown can provide a sanitized semantic XHTML body without duplicating the package builder.
3. Add `MarkdownToEPUBConverter`:
   - Accept `.md` and `.markdown`, case-insensitively.
   - Require readable UTF-8 input under 50 MiB; return localized conversion errors.
   - Render common Markdown constructs.
   - Use SwiftSoup to allow only safe reading tags and attributes.
   - Remove scripts, styles, forms, frames, embedded objects, event attributes, and unsafe URL schemes.
   - Replace images with plain-text `[Image: alt]` / `[Image]` placeholders (no packaging, no fetch).
   - Derive title: front matter `title` → first ATX/Setext H1 (outside fences) → filename.
   - Derive language: front matter `lang`/`language` → device language code → `und`.
4. Route Markdown before Readium format sniffing in `LibraryService`.
5. Register Markdown in `iPhone/Info.plist` for `.md` and `.markdown` Open In/share handling using `net.daringfireball.markdown`.
6. Add `.md` and `.markdown` to Wi-Fi transfer's server allowlist and HTML file input.
7. Update onboarding's supported-format copy in English and Simplified Chinese.
8. Package with explicit **ReadiumZIPFoundation** (readium/ZIPFoundation ≥ 3.0.1): root entries, `mimetype` first and uncompressed; staging dir cleaned on all failure paths.
9. Focused unit tests: rendering, sanitization contracts, title/language, front-matter boundaries, size limits, ZIP structure, and real Readium open.

## PR Review Reopening (this iteration)

Review feedback reopened the cycle for minimal fixes:

- P0: packager cleanup + enumerator failure; sanitizer contract tests; ZIP structure assertions.
- P1: language priority; Setext/ATX H1 rules; image placeholders.
- P2: 50 MiB limit; front-matter only when key-value present; cycle docs + dependency disclosure.

## Dependencies (disclose in PR)

| Package | Role | Network | License (upstream) |
| --- | --- | --- | --- |
| Ink 0.6.0 | Offline Markdown → HTML | None at runtime | MIT |
| SwiftSoup (existing) | HTML sanitization / XHTML | None | MIT |
| ReadiumZIPFoundation 3.0.1 (readium/ZIPFoundation) | EPUB ZIP packaging only | None | MIT (ZIPFoundation lineage) |

Pinned versions are declared in all six XcodeGen configs. Do not rely on invisible transitive ZIP APIs for packaging.

## Non-goals

- No new Reader format module.
- No Markdown editor or source view.
- No remote rendering API.
- No local attachment traversal or image packaging.
- No opportunistic refactor outside import/conversion code.

## Handoff Constraints

- Follow `AGENTS.md`; respond in Chinese and keep the diff surgical.
- Do not modify version/build numbers.
- Do not commit or push.
- Preserve all unrelated user changes.
- Generate the Xcode project from `Integrations/SPM/project.yml` only for verification; generated `project.yml` and `.xcodeproj` remain ignored.
- Return changed files, test/build commands, and any known limitation.
