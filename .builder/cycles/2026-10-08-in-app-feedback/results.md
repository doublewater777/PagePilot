# Results

- Backend tests: 5/5 passed, including notification receipt and failure isolation.
- iPhone 18 Pro Max / iOS 27: build and focused tests passed 3/3; editor input, submit states and return to settings after submission verified.
- iPad mini / iPadOS 27: build, portrait and landscape layouts passed. Narrow-window resizing did not take effect in Device Hub and remains unverified.
- Dedicated `pagepilotFeedback` function is Active. Separate collections and private Feishu group `PagePilot 反馈` use the existing CloudBase environment and Feishu bot; BeforeShow functions were not modified.
- Production feedback `31664031-5f5c-45ba-a9cf-3d0b5075838a` returned `ok: true`, `notificationDelivered: true`. Delivery is checked against Feishu's API response.
- Local HTTP verification required a source-server connection override with normal TLS verification; no global network settings were changed.
- Screenshots are saved under `evidence/` for iPhone input and iPad portrait/landscape.
- 2026-10-09 Toast follow-up: iPhone 18 Pro Max build passed; an actual successful submission displayed the bottom Toast and returned after 2 seconds. Screenshot: `evidence/iphone18-feedback-toast.jpg`. Failure Toast is implemented with a 3-second timeout and preserved input, but was not manually exercised; iPad Toast layout was not re-tested.
- Reader behavior and feedback completion rate: no production evidence yet.
