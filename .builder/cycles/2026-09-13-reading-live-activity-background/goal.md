# Goal

- User problem: the reading Live Activity should only exist while the Watch can act as a page-turn remote; a backgrounded app has no pages to turn.
- Target user: readers who background the app or lock the screen mid-session.
- Desired behavior: backgrounding ends the reading session, stats, and Live Activity; foregrounding starts a fresh session.
- Success: the background notification finishes the session without celebrating the daily goal, foregrounding restarts it, and no separate foreground-stats pause/resume state remains.
- Out of scope: audiobook Live Activities, background reading progress tracking, or direct interactive controls in the Live Activity.
