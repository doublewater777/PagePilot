# Implementation

- Validate local Publication existence through `Book.absoluteFileURL()` before calling Readium.
- Log the Book title, stored URL, and resolved URL when the local Publication is absent.
- Return the existing `LibraryError.bookNotFound` with actionable localized recovery text.
- Add focused regression tests for missing, existing, and remote Publication URLs.
- Regenerate the local Xcode project from `Integrations/SPM/project.yml` so the main app plist settings and Live Activity extension are present.
- Do not mutate CloudKit behavior or automatically remove affected Books.
