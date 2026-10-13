import Foundation
import AppKit
import IOKit.pwr_mgt

/// GestapoPowerGuard отвечает за предотвращение засыпания системы при блокировке экрана
/// и управление Grace Period (10-секундное окно после открытия крышки ноутбука).
@MainActor
final class GestapoPowerGuard {
    private var assertionID: IOPMAssertionID = 0
    private var isSystemSleeping: Bool = false
    private var wakeGracePeriodUntil: TimeInterval = 0.0

    var isAssertionActive: Bool {
        assertionID != 0
    }

    var isSleeping: Bool {
        isSystemSleeping
    }

    var isGracePeriodActive: Bool {
        Date().timeIntervalSince1970 < wakeGracePeriodUntil
    }

    init() {
        setupSleepWakeObservers()
    }

    deinit {
        let id = assertionID
        if id != 0 {
            IOPMAssertionRelease(id)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func setupSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        isSystemSleeping = true
    }

    @objc private func handleDidWake(_ notification: Notification) {
        isSystemSleeping = false
        activateGracePeriod(seconds: 10.0)
    }

    func activateGracePeriod(seconds: Double = 10.0) {
        wakeGracePeriodUntil = Date().timeIntervalSince1970 + seconds
    }

    func clearGracePeriod() {
        wakeGracePeriodUntil = 0.0
    }

    /// Управление системным sleep assertion.
    /// kIOPMAssertionTypePreventUserIdleSystemSleep позволяет экрану гаснуть и блокироваться,
    /// но процессор и сетевой стек продолжают непрерывно работать.
    func updateSleepAssertion(shouldHold: Bool, reason: String = "Gestapo VPN Protection Active") {
        if shouldHold {
            if assertionID == 0 {
                var newID: IOPMAssertionID = 0
                let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
                let reasonCF = reason as CFString
                let result = IOPMAssertionCreateWithName(
                    type,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reasonCF,
                    &newID
                )
                if result == kIOReturnSuccess {
                    assertionID = newID
                }
            }
        } else {
            releaseAssertion()
        }
    }

    func releaseOnTerminate() {
        releaseAssertion()
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
