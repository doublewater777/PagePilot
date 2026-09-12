# Assumptions

- The paired PagePilot Watch app is installed and runs watchOS 11.1 or later, where Apple supports launching a watchOS app from a forwarded Live Activity.
- Explicitly naming PagePilot's only ActivityAttributes type avoids the observed fallback behavior from the existing empty declaration.
- Opening the existing Watch app is sufficient because it already exposes previous, next, Double Tap, and Digital Crown page-turn controls.
- The approach is falsified if a freshly installed Watch build still shows only “Open on iPhone” on supported watchOS.
