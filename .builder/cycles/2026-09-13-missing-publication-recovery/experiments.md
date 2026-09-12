# Experiments

- Run `BookFileAvailabilityTests` on the iPhone 17 simulator.
- Pass threshold: missing local Publication throws `LibraryError.bookNotFound`; existing local Publication and remote Publication URL pass.
- Build for an iPad simulator to ensure the shared Library path remains valid on iPad.
- Inspect the built `PagePilot.app/Info.plist` and embedded Live Activity extension.
- Loop back if any validation fails or a real device still reports `unsupportedTarget` after reinstalling the regenerated build.
