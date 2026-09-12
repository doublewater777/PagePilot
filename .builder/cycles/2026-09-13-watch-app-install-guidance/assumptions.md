# Assumptions

- The iPhone Watch app URL scheme (`bridge://`) opens the Watch app on iOS 17 without needing a query-scheme declaration for `open(_:)`.
- A single primary button plus the existing skip action is enough guidance; no extra sheet or step-by-step flow is needed.
- Falsifier: tapping the button does not open the Watch app on a real device, or users still tap the Smart Stack activity expecting controls before installing.
