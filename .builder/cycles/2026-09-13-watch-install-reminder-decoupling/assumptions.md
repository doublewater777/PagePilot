# Assumptions

- Watch app installation is a device fact owned by `WCSession`; onboarding state must not gate the reminder.
- Dismissing the tip is per-Reader-session only; the next reading session re-evaluates device state.
- Falsifier: readers find the recurring tip noisy even though the Watch app is still missing.
