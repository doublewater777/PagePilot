# Experiments

## Test Plan

Run fresh onboarding on iPhone and verify one successful import through each source:

1. Files picker.
2. Wi-Fi upload from a browser on the same network.
3. OPDS acquisition from a configured feed.

Repeat the source-selection and successful-import transition on iPad.

## Measurement

No new analytics are added. Record reproducible QA results here and collect direct support or interview feedback about import-source confusion.

## Pass Threshold

- All three iPhone paths select the imported book and reach control-target selection.
- All three iPad paths select the imported book and reach Reader.
- Canceling a source returns to onboarding without changing its state.

## Loop-back Trigger

If alternative sources cannot reliably return the imported Book, keep Files as the onboarding action and move Wi-Fi/OPDS back to Bookshelf-only entry points.
