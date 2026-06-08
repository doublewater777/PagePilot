import Foundation

final class ThrottledCommandQueue {
    typealias SendHandler = (PageCommand, @escaping () -> Void) -> Void

    private let interval: TimeInterval
    private let sendHandler: SendHandler
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()

    private var lastDispatchTime: Date?
    private var lastCompletionTime: Date?
    private var queuedCommand: PageCommand?
    private var dispatchWorkItem: DispatchWorkItem?
    private var isCommandInFlight = false

    init(
        interval: TimeInterval = 0.2,
        queue: DispatchQueue = .main,
        sendHandler: @escaping SendHandler
    ) {
        self.interval = interval
        self.queue = queue
        self.sendHandler = sendHandler
        queue.setSpecific(key: queueKey, value: true)
    }

    func enqueue(_ command: PageCommand) {
        queuedCommand = command
        dispatchNextIfNeeded()
    }

    private func dispatchNextIfNeeded() {
        guard queuedCommand != nil else { return }
        guard !isCommandInFlight else { return }

        let now = Date()
        let earliest = earliestNextDispatchTime()

        if now >= earliest {
            dispatchWorkItem?.cancel()
            dispatchWorkItem = nil

            let command = queuedCommand!
            queuedCommand = nil
            send(command)
        } else {
            if dispatchWorkItem == nil {
                let delay = earliest.timeIntervalSince(now)
                let item = DispatchWorkItem { [weak self] in
                    self?.dispatchWorkItem = nil
                    self?.dispatchNextIfNeeded()
                }
                dispatchWorkItem = item
                queue.asyncAfter(deadline: .now() + delay, execute: item)
            }
        }
    }

    private func earliestNextDispatchTime() -> Date {
        let dispatchGate = (lastDispatchTime ?? .distantPast).addingTimeInterval(interval)
        let completionGate = lastCompletionTime ?? .distantPast
        return max(dispatchGate, completionGate)
    }

    private func send(_ command: PageCommand) {
        lastDispatchTime = Date()
        isCommandInFlight = true
        sendHandler(command) { [weak self] in
            guard let self else { return }
            // If we are already on the target queue, call handleCompletion
            // synchronously to avoid an extra async hop that can cause test
            // races and to ensure the queued command is dispatched promptly.
            if DispatchQueue.getSpecific(key: self.queueKey) != nil {
                self.handleCompletion()
            } else {
                self.queue.async { self.handleCompletion() }
            }
        }
    }

    private func handleCompletion() {
        lastCompletionTime = Date()
        isCommandInFlight = false
        dispatchNextIfNeeded()
    }
}
