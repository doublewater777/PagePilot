# Experiments

- Unit-test the command buffer's first-command, reachability, and timeout behavior.
- Build the Watch target and run the iPhone 17 simulator test suite.
- Real-device check: launch from the Live Activity, immediately tap once, and confirm exactly one page turn occurs after connection.
- Pass threshold: no misleading “open iPhone” error during the startup grace period and no replay burst.
- Loop back if connection commonly takes longer than five seconds or the delayed single command feels surprising.
