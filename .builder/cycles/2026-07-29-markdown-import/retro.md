# Retro

## Status

**completed / pass** — review fixes accepted after independent targeted and full-suite verification.

## What We Believed

Converting Markdown at the Library boundary would let PagePilot reuse its proven EPUB reader while keeping Markdown-specific parsing and sanitization isolated.

## What We Learned

That boundary worked: import surfaces only need extension recognition; one converter owns title/language, safe XHTML, and minimal EPUB packaging.

A non-empty archive is not a valid EPUB. Extra ZIP directory nesting passed shallow tests and failed Readium. Opening the artifact through Readium is the compatibility check and is permanent.

PR review also showed: front-matter fences must require key-value metadata so leading horizontal rules are not swallowed; ATX H1 needs a space after `#` and must ignore fenced code; images should degrade to text rather than vanish silently; size limits and staging cleanup matter for robustness.

Local test evidence does not create a GitHub merge gate. A permanent pull-request CI workflow keeps the full suite visible to reviewers and prevents an empty check set from blocking guarded landing.

## Dependencies

- **Ink**: offline parse only; no network runtime.
- **ReadiumZIPFoundation**: packaging only; explicit direct dependency across all XcodeGen configs.
- Disclose pinned versions and MIT licenses in the PR description.

## Decision

Keep the converter-backed design and ship the review fixes.

## Archive / Continue / Loop Back

Completed. Loop back only if real-world Markdown requires scoped support for embedded media or raw HTML beyond the current security surface.
