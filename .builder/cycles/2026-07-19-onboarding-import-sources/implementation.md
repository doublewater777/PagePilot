# Implementation

## Included

- Add an import-source chooser to the onboarding primary action.
- Reuse the existing Files picker, Wi-Fi transfer view, and OPDS feed browser.
- Add optional first-success callbacks to Wi-Fi and OPDS imports.
- Dismiss the selected source and continue onboarding with the imported Book.
- Add Chinese and English source labels.

## Excluded

- Changes to transfer protocols, OPDS parsing, or feed management.
- Multiple-book onboarding selection.
- Automatic iPhone/iPad book synchronization.

## Dependencies

- `WiFiTransferView` and `WiFiTransferViewModel`.
- `OPDSFeedListViewController` and `OPDSBrowseViewController`.
- Existing `LibraryService` import behavior and onboarding state machine.

## Handoff

The first successful Wi-Fi or OPDS import closes its modal and becomes the onboarding Publication. Normal Bookshelf callers retain their current behavior.
