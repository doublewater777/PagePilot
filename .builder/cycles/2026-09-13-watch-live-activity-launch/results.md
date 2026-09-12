# Results

- The focused Watch-plist regression test passes after failing against the empty array.
- The iPhone 17 simulator suite passes 235/235, and the PagePilot scheme builds successfully for the iPad mini simulator.
- The generated Watch app and its copy embedded in the iPhone app both contain `["ReadingLiveActivityAttributes"]`.
- Real-device launch behavior requires reinstalling the updated Watch app because the relevant declaration belongs to the Watch binary.
