## 2026-06-06 - 10-growth-channel

Cycle: 2026-06-06-app-store-approval-launch
Verdict: weak_pass
Evidence: Apple approval, App Store link, local website/README/product evidence, screenshot assets.
Weakest assumption: Apple Watch page turning is enough to create user pull.
Decision: Generate and publish first launch distribution pack, skipping App Store / Google Play metadata and website.
Next stage: 10-growth-channel
Loop-back:

## 2026-07-19 - 01-hypothesis

Cycle: 2026-07-19-onboarding-import-sources
Verdict: pass
Evidence: iPhone and iPad simulator QA completed real EPUB imports through Wi-Fi and a local OPDS catalog; Files picker and cancel paths remained intact; full test suite passed.
Weakest assumption: Alternative import sources help enough new users to justify an extra source-selection step.
Decision: Reuse the existing flows and require every successful source to continue the same onboarding activation path.
Next stage: 10-growth-channel
Loop-back: Keep Files as the direct action if source selection creates friction or alternative paths do not complete reliably.

## 2026-07-29 - 01-hypothesis

Cycle: 2026-07-29-markdown-import
Verdict: pass
Evidence: Markdown conversion and security tests pass; generated EPUB opens through Readium; the full iPhone 17 simulator suite passed 130/130; project generation, plist validation, and diff checks passed.
Weakest assumption: Safe Markdown-to-EPUB conversion preserves enough formatting to feel like native format support.
Decision: Ship conversion at the Library import boundary and reuse the existing EPUB Reader.
Next stage: 10-growth-channel
Loop-back: Add narrowly scoped Markdown features only when real imported files demonstrate missing structure or media needs.

## 2026-07-29 - 01-hypothesis (reopened)

Cycle: 2026-07-29-markdown-import
Verdict: pass
Evidence: Review fixes independently verified: 40/40 targeted Markdown tests and 151/151 full iPhone 17 simulator tests passed; href removal, EPUB root structure, uncompressed mimetype, Readium opening, image fallback, size limits, language metadata, and staging cleanup were reviewed; plist and diff checks passed.
Weakest assumption: Safe Markdown-to-EPUB conversion preserves enough formatting to feel like native format support.
Decision: Ship the review-hardened converter and close the reopened cycle.
Next stage: 10-growth-channel
Loop-back: Add narrowly scoped format support only when real imported files demonstrate a need.
