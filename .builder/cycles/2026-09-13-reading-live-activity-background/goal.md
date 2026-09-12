# Goal

- User problem: entering the Lock Screen, Home Screen, or another app immediately removes the reading Live Activity.
- Target user: readers who want the Lock Screen, Dynamic Island, and paired Watch to keep reflecting the active reading session.
- Desired behavior: backgrounding preserves the Live Activity; leaving the visual Reader or ending the reading session still ends it.
- Success: background notification no longer invokes the Reader session finish path, and foregrounding cannot restart a session that already ended.
- Out of scope: audiobook Live Activities, background reading progress tracking, or direct interactive controls in the Live Activity.
