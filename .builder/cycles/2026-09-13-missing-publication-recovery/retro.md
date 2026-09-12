# Retro

- Belief: the Library boundary should distinguish a missing local Publication from a Readium parsing/opening failure.
- Learning: the existing `Book.absoluteFileURL()` provides the correct stable seam, while remote Publications must bypass local existence checks.
- Decision: keep the Book record intact, fail early with an actionable message, and rely on explicit re-import or existing iCloud Sync for recovery.
- Status: completed locally; observe real-device recovery and Live Activity behavior after reinstall.
