import Foundation

struct WatchColdStartCommandBuffer: Equatable, Sendable {
    private(set) var pendingCommand: PageCommand?

    mutating func storeIfEmpty(_ command: PageCommand) {
        guard pendingCommand == nil else { return }
        pendingCommand = command
    }

    mutating func takeIfReachable(_ isReachable: Bool) -> PageCommand? {
        guard isReachable else { return nil }
        defer { pendingCommand = nil }
        return pendingCommand
    }

    mutating func clear() {
        pendingCommand = nil
    }
}
