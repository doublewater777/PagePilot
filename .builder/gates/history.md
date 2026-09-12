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

## 2026-09-13 - 01-hypothesis

Cycle: 2026-09-13-missing-publication-recovery
Verdict: pass
Evidence: The supplied `fileNotFound` trace maps to a missing local Publication; focused tests cover missing, existing, and remote URLs; the regenerated app and extension contain Live Activity support metadata.
Weakest assumption: Previously uploaded CKAssets remain available when users try iCloud recovery.
Decision: Fail before Readium with `bookNotFound`, keep the Book record, and guide the user to re-import or iCloud Sync.
Next stage: 10-growth-channel
Loop-back: Add an explicit in-alert sync action only if observed recovery friction justifies the extra coupling.

## 2026-09-13 - 01-hypothesis (Watch Live Activity launch)

Cycle: 2026-09-13-watch-live-activity-launch
Verdict: pass
Evidence: Apple documents the Watch launch attribute key for forwarded Live Activities; the embedded Watch plist regression test fails for the prior empty declaration and passes for the explicit PagePilot attribute type.
Weakest assumption: the updated companion Watch app will be installed alongside the iPhone build on the user's paired device.
Decision: Launch the existing Watch app from the Smart Stack card and reuse its page-turn controls.
Next stage: 10-growth-channel
Loop-back: Consider direct interactive Live Activity buttons only if opening the Watch app remains too slow or unreliable in observed use.

## 2026-09-13 - 01-hypothesis (Watch cold-start control)

Cycle: 2026-09-13-watch-cold-start-control
Verdict: pass
Evidence: The first-command buffer is covered by focused tests; the full iPhone 17 simulator suite passes 238/238; the iPad mini build includes the rebuilt Watch app.
Weakest assumption: five seconds covers normal paired-device WCSession activation after a Live Activity launch.
Decision: show an explicit connecting state and replay at most one early page-turn command when transport becomes reachable.
Next stage: 10-growth-channel
Loop-back: Revisit the grace period or delayed-command behavior if paired-device testing shows longer activation or surprising turns.

## 2026-09-13 - 01-hypothesis (Reading Live Activity background retention)

Cycle: 2026-09-13-reading-live-activity-background
Verdict: pass
Evidence: Focused lifecycle tests fail on the old background finish path and pass after the split; focused Live Activity suites pass 20/20 and the full simulator suite passes 241/241.
Weakest assumption: ActivityKit retains the existing visual reading activity correctly through real lock-screen and app-switching sessions.
Decision: preserve the Watch reading session and Live Activity across backgrounding; end them only when the visual Reader disappears.
Next stage: 10-growth-channel
Loop-back: Reconsider if a retained activity ever survives an actual Reader dismissal on device.
