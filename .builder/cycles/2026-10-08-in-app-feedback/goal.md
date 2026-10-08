# In-App Feedback

Stage: 10-growth-channel.
Target users: PagePilot readers reporting problems or suggestions.
Problem: The current feedback entry requires a configured mail app and separate category selection.
Desired behavior: Write a message in PagePilot and submit it directly, using the BeforeShow interaction flow.
Success: A valid message reaches the dedicated PagePilot Feishu group; blank/over-limit messages cannot submit; failures preserve the draft and allow retry; layout works on iPhone and iPad.
Scope: Feedback UI, localized copy, dedicated submission function, Feishu delivery, and privacy disclosure.

User decision: Create a separate PagePilot feedback service and a new destination in Feishu.
