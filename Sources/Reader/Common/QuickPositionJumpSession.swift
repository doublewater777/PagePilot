struct QuickPositionJumpSession {
    enum State: Equatable {
        case idle
        case preparing
        case previewing
        case cancellationArmed
        case committing
    }

    private(set) var state: State = .idle
    private(set) var generation = 0

    mutating func beginPreparing() -> Bool {
        guard state == .idle else { return false }
        state = .preparing
        return true
    }

    mutating func beginPreview() -> Bool {
        guard state == .preparing else { return false }
        state = .previewing
        return true
    }

    mutating func setCancellationArmed(_ armed: Bool) {
        guard state == .previewing || state == .cancellationArmed else { return }
        state = armed ? .cancellationArmed : .previewing
    }

    mutating func beginCommit() -> Int? {
        guard state == .previewing else { return nil }
        state = .committing
        return generation
    }

    mutating func interruptCommit() {
        guard state == .committing else { return }
        generation &+= 1
        state = .idle
    }

    func acceptsCompletion(for token: Int) -> Bool {
        state == .committing && generation == token
    }

    mutating func reset() {
        generation &+= 1
        state = .idle
    }
}
