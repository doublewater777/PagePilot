# Assumptions

- A missing local Publication is the direct cause when Readium reports `FileSystemError.fileNotFound` for a Book that remains in the database.
- `Book.absoluteFileURL()` is the canonical container-safe resolver for local Publication URLs.
- A clear recovery message is more useful than exposing the nested Readium error.
- The idea is falsified if an existing local Publication is blocked, a remote URL is treated as missing, or the check still returns `openFailed` for an absent local file.
- Evidence: the supplied device log, repository history for the cleanup race, and the current `openBook()` implementation.
