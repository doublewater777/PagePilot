# Assumptions

- Removing mail setup reduces friction for existing readers.
- The BeforeShow in-app flow provides an established interaction reference.
- A dedicated function and data collections can use the existing CloudBase environment while keeping PagePilot feedback separate.
- The riskiest dependency is provisioning and verifying the private Feishu destination.

Falsification: Feedback appears successful in the app but cannot be retrieved or delivered to the PagePilot destination.
