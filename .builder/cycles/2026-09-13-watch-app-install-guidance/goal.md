# Goal

- User problem: a reader whose paired Watch does not have PagePilot installed only gets passive text in the first Reader tip, and tapping the Smart Stack Live Activity later falls back to an unhelpful system label.
- Target user: iPhone readers with a paired Apple Watch but without the PagePilot Watch app installed.
- Desired behavior: the install-state tip offers a primary action that opens the iPhone Watch app, where PagePilot can be installed.
- Success: the install state shows the action in all five supported localizations, the Watch app URL constant stays in place, and the regression tests pass.
- Out of scope: changing the Live Activity layout, the unavailable-system fallback text, or the guide trigger timing.
