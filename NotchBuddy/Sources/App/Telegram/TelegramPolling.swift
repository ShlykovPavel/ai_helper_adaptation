import Foundation

protocol TelegramSleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct SystemTelegramSleeper: TelegramSleeper {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

actor TelegramPolling {
    typealias UpdateHandler = @Sendable (TelegramUpdate) async -> Void
    typealias StatusHandler = @Sendable (TelegramConnectionStatus) -> Void

    private let api: TelegramBotAPI
    private let sleeper: any TelegramSleeper
    private let backoffSchedule: [TimeInterval]
    private let onStatusChange: StatusHandler?
    private let onUpdate: UpdateHandler?

    private(set) var status: TelegramConnectionStatus = .idle {
        didSet {
            if oldValue != status {
                onStatusChange?(status)
            }
        }
    }
    private var pollingTask: Task<Void, Never>?
    private var currentOffset: Int64? = nil
    private var consecutiveFailures = 0

    init(
        api: TelegramBotAPI,
        sleeper: any TelegramSleeper = SystemTelegramSleeper(),
        backoffSchedule: [TimeInterval] = [1, 2, 4, 8, 16, 30, 60],
        onStatusChange: StatusHandler? = nil,
        onUpdate: UpdateHandler? = nil
    ) {
        self.api = api
        self.sleeper = sleeper
        self.backoffSchedule = backoffSchedule
        self.onStatusChange = onStatusChange
        self.onUpdate = onUpdate
    }

    func start() {
        guard pollingTask == nil else { return }
        status = .polling
        consecutiveFailures = 0
        pollingTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        status = .stopped
    }

    private func nextBackoffDelay() -> TimeInterval {
        guard !backoffSchedule.isEmpty else { return 1.0 }
        let index = min(consecutiveFailures, backoffSchedule.count - 1)
        consecutiveFailures += 1
        return backoffSchedule[index]
    }

    private func runLoop() async {
        // Step 1: Call deleteWebhook before initial poll
        var webhookDeleted = false
        while !webhookDeleted {
            if Task.isCancelled {
                status = .stopped
                return
            }
            do {
                try await api.deleteWebhook(dropPendingUpdates: false)
                webhookDeleted = true
                consecutiveFailures = 0
            } catch let error as TelegramAPIError {
                switch error {
                case .unauthorized:
                    status = .unauthorized
                    return
                case .conflict:
                    status = .conflict
                    let delay = nextBackoffDelay()
                    do {
                        try await sleeper.sleep(seconds: delay)
                    } catch {
                        status = .stopped
                        return
                    }
                case .rateLimited(let retryAfter):
                    status = .backoff(seconds: retryAfter)
                    do {
                        try await sleeper.sleep(seconds: TimeInterval(retryAfter))
                    } catch {
                        status = .stopped
                        return
                    }
                default:
                    let delay = nextBackoffDelay()
                    status = .backoff(seconds: Int(delay))
                    do {
                        try await sleeper.sleep(seconds: delay)
                    } catch {
                        status = .stopped
                        return
                    }
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    status = .stopped
                    return
                }
                let delay = nextBackoffDelay()
                status = .backoff(seconds: Int(delay))
                do {
                    try await sleeper.sleep(seconds: delay)
                } catch {
                    status = .stopped
                    return
                }
            }
        }

        // Step 2: Main polling loop
        while !Task.isCancelled {
            status = .polling
            do {
                let updates = try await api.getUpdates(offset: currentOffset, timeoutSeconds: 25)
                consecutiveFailures = 0
                status = .polling
                for update in updates {
                    if Task.isCancelled { break }
                    await onUpdate?(update)
                    currentOffset = max(currentOffset ?? 0, update.updateId + 1)
                }
            } catch let error as TelegramAPIError {
                switch error {
                case .unauthorized:
                    status = .unauthorized
                    return
                case .conflict:
                    status = .conflict
                    let delay = nextBackoffDelay()
                    do {
                        try await sleeper.sleep(seconds: delay)
                    } catch {
                        status = .stopped
                        return
                    }
                case .rateLimited(let retryAfter):
                    status = .backoff(seconds: retryAfter)
                    do {
                        try await sleeper.sleep(seconds: TimeInterval(retryAfter))
                    } catch {
                        status = .stopped
                        return
                    }
                default:
                    let delay = nextBackoffDelay()
                    status = .backoff(seconds: Int(delay))
                    do {
                        try await sleeper.sleep(seconds: delay)
                    } catch {
                        status = .stopped
                        return
                    }
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    status = .stopped
                    return
                }
                let delay = nextBackoffDelay()
                status = .backoff(seconds: Int(delay))
                do {
                    try await sleeper.sleep(seconds: delay)
                } catch {
                    status = .stopped
                    return
                }
            }
        }
        status = .stopped
    }
}
