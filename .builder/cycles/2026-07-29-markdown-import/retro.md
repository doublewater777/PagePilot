# Retro

## What We Believed

Converting Markdown at the Library boundary would let PagePilot reuse its proven EPUB reader while keeping Markdown-specific parsing and sanitization isolated.

## What We Learned

That boundary worked: all import surfaces only need to recognize the extensions, while one converter owns title extraction, safe XHTML generation, and minimal EPUB packaging.

A non-empty archive is not evidence of a valid EPUB. The original packager's extra ZIP directory passed shallow tests but failed Readium. Opening the generated artifact through Readium is the meaningful compatibility check, so that scenario is now permanent.

## Decision

Ship the converter-backed implementation with Ink for Markdown rendering, SwiftSoup for sanitization, and ReadiumZIPFoundation for deterministic root-level EPUB packaging. Reuse the same minimal packager for TXT imports.

## Archive / Continue / Loop Back

Completed with a passing gate. Loop back if real-world Markdown relies heavily on unsupported embedded media or raw HTML, rather than broadening the initial security surface preemptively.
