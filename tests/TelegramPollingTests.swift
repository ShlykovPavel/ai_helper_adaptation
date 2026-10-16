import Foundation

actor TestTelegramSleeper: TelegramSleeper {
    private var _sleepDurations: [TimeInterval] = []
    var onSleep: (@Sendable (TimeInterval) async throws -> Void)?

    init(onSleep: (@Sendable (TimeInterval) async throws -> Void)? = nil) {
        self.onSleep = onSleep
    }

    var sleepDurations: [TimeInterval] { _sleepDurations }

    func setOnSleep(_ handler: (@Sendable (TimeInterval) async throws -> Void)?) {
        self.onSleep = handler
    }

    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        _sleepDurations.append(seconds)
        if let handler = onSleep {
            try await handler(seconds)
        }
    }
}

actor UpdateCollector {
    private var _received: [TelegramUpdate] = []
    var received: [TelegramUpdate] { _received }
    func add(_ u: TelegramUpdate) {
        _received.append(u)
    }
}

func runTelegramPollingTests() async {
    // 1. Initial webhook deletion is called before getUpdates
    do {
        let mock = MockTelegramHTTPTransport { method, _ in
            if method == "deleteWebhook" {
                return ["ok": true, "result": true]
            }
            if method == "getUpdates" {
                return ["ok": true, "result": []]
            }
            return ["ok": true, "result": [:]]
        }
        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper()
        let polling = TelegramPolling(api: api, sleeper: sleeper)

        await polling.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await polling.stop()

        let records = await mock.records
        precondition(!records.isEmpty, "Expected requests to be recorded")
        precondition(records[0].method == "deleteWebhook", "Expected deleteWebhook to be called first")
        precondition(records[0].body["drop_pending_updates"] as? Bool == false)
        if records.count > 1 {
            precondition(records[1].method == "getUpdates")
        }
    }

    // 2. Updates are dispatched to handler and offset is advanced to update_id + 1
    do {
        final class Counter: @unchecked Sendable {
            var value = 0
            let lock = NSLock()
            func increment() -> Int {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value
            }
        }
        let counter = Counter()

        let mock = MockTelegramHTTPTransport { method, body in
            if method == "deleteWebhook" {
                return ["ok": true, "result": true]
            }
            if method == "getUpdates" {
                let pollNum = counter.increment()
                if pollNum == 1 {
                    return [
                        "ok": true,
                        "result": [
                            [
                                "update_id": 500,
                                "message": [
                                    "message_id": 1,
                                    "chat": ["id": 11, "type": "private"],
                                    "text": "first"
                                ]
                            ],
                            [
                                "update_id": 501,
                                "message": [
                                    "message_id": 2,
                                    "chat": ["id": 11, "type": "private"],
                                    "text": "second"
                                ]
                            ]
                        ]
                    ]
                } else {
                    return ["ok": true, "result": []]
                }
            }
            return ["ok": true, "result": [:]]
        }

        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper()
        let collector = UpdateCollector()

        let polling = TelegramPolling(api: api, sleeper: sleeper) { update in
            await collector.add(update)
        }

        await polling.start()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await polling.stop()

        let received = await collector.received
        precondition(received.count == 2)
        precondition(received[0].updateId == 500)
        precondition(received[1].updateId == 501)

        let records = await mock.records
        let getUpdateCalls = records.filter { $0.method == "getUpdates" }
        precondition(getUpdateCalls.count >= 2)
        precondition(getUpdateCalls[0].body["offset"] == nil)
        precondition(getUpdateCalls[1].body["offset"] as? Int64 == 502)
    }

    // 3. 401 Unauthorized stops permanently
    do {
        let mock = MockTelegramHTTPTransport { method, _ in
            if method == "deleteWebhook" {
                return ["ok": true, "result": true]
            }
            throw TelegramAPIError.unauthorized
        }
        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper()
        let polling = TelegramPolling(api: api, sleeper: sleeper)

        await polling.start()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let status = await polling.status
        precondition(status == .unauthorized, "Status should be unauthorized on 401, got \(status)")
        let callCountBefore = await mock.records.count
        try? await Task.sleep(nanoseconds: 30_000_000)
        let callCountAfter = await mock.records.count
        precondition(callCountAfter == callCountBefore, "No further calls should be made after 401")
    }

    // 4. 409 Conflict sets status to conflict
    do {
        let mock = MockTelegramHTTPTransport { method, _ in
            if method == "deleteWebhook" {
                return ["ok": true, "result": true]
            }
            throw TelegramAPIError.conflict(description: "Conflict: another getUpdates instance active")
        }
        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper { _ in
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let polling = TelegramPolling(api: api, sleeper: sleeper)

        await polling.start()
        try? await Task.sleep(nanoseconds: 20_000_000)

        let status = await polling.status
        precondition(status == .conflict, "Status should be conflict on 409, got \(status)")
        await polling.stop()
    }

    // 5. Network error follows backoff schedule
    do {
        let mock = MockTelegramHTTPTransport { method, _ in
            if method == "deleteWebhook" {
                return ["ok": true, "result": true]
            }
            throw TelegramAPIError.networkError("Connection reset")
        }
        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper()
        let polling = TelegramPolling(api: api, sleeper: sleeper, backoffSchedule: [1, 2, 4, 8])

        await polling.start()
        try? await Task.sleep(nanoseconds: 60_000_000)
        await polling.stop()

        let sleeps = await sleeper.sleepDurations
        precondition(!sleeps.isEmpty, "Expected backoff sleeps")
        precondition(sleeps[0] == 1.0)
        if sleeps.count > 1 {
            precondition(sleeps[1] == 2.0)
        }
    }

    // 6. Clean cancellation on stop()
    do {
        let mock = MockTelegramHTTPTransport { _, _ in ["ok": true, "result": []] }
        let api = TelegramBotAPI(transport: mock)
        let sleeper = TestTelegramSleeper()
        let polling = TelegramPolling(api: api, sleeper: sleeper)

        await polling.start()
        let s1 = await polling.status
        precondition(s1 == .polling)
        await polling.stop()
        let s2 = await polling.status
        precondition(s2 == .stopped)
    }

    print("TelegramPollingTests: PASS")
}
