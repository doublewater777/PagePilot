# Experiments

## Automated Acceptance

1. Convert a representative Markdown fixture containing headings, emphasis, strong text, ordered/unordered lists, a block quote, fenced and inline code, a link, a rule, and a table.
2. Assert the generated body preserves the corresponding semantic elements.
3. Convert hostile Markdown containing script tags, event-handler attributes, and `javascript:` links; assert active content is absent.
4. Route mixed-case `.md` and `.markdown` extensions through Markdown conversion.
5. Run the complete PagePilot test suite and build the app for `platform=iOS Simulator,name=iPhone 17`.

## Manual Acceptance

- Import a fixture through Files and confirm it appears in the Bookshelf and opens in the Reader.
- Repeat through onboarding if a clean-install scenario is practical.
- Upload the same fixture through Wi-Fi transfer.
- Confirm headings, lists, quotes, code, links, and table content are legible in light and dark Reader themes.

## Pass Threshold

All automated acceptance checks pass, the simulator build succeeds, and at least one real `.md` import opens in the Reader without raw Markdown syntax or active HTML.

## Loop-back Trigger

Loop back to implementation design if Readium rejects the generated EPUB/XHTML, if sanitization removes ordinary prose structure, or if the added dependency cannot be pinned and built reproducibly.
