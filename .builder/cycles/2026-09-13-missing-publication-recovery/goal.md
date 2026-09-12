# Goal

- User problem: a Book can remain visible in the Bookshelf after its local Publication file has disappeared, and opening it only shows a generic Readium failure.
- Target user: PagePilot readers with an existing Bookshelf, especially installations affected by the former orphan-cleanup race.
- Desired behavior: fail before Readium, preserve the Book record, and explain that the Publication must be re-imported or may be recoverable through iCloud Sync.
- Success: deterministic tests distinguish missing local files from existing local files and remote URLs; the generated app still supports Live Activities.
- Out of scope: restoring a CKAsset during `openBook()`, deleting Book records automatically, and resolving unrelated concurrency warnings.
