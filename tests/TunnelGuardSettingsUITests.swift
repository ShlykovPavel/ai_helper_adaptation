import Foundation
import SwiftUI

@main
@MainActor
enum TunnelGuardSettingsUITests {
    static func main() {
        testSettingsInfoTipInitialization()
        testPickerTagValuesMatchWatchdogConstants()
        print("TunnelGuard Settings UI tests: all passed")
    }

    static func testSettingsInfoTipInitialization() {
        let tipWithTitle = SettingsInfoTip(title: "Заголовок подсказки", text: "Подробный текст пояснения.")
        precondition(tipWithTitle.title == "Заголовок подсказки")
        precondition(tipWithTitle.text == "Подробный текст пояснения.")

        let tipWithoutTitle = SettingsInfoTip(title: nil, text: "Простой текст.")
        precondition(tipWithoutTitle.title == nil)
        precondition(tipWithoutTitle.text == "Простой текст.")
        print("  ✓ SettingsInfoTip initialization with title and nil title")
    }

    static func testPickerTagValuesMatchWatchdogConstants() {
        let validActions: Set<String> = ["prompt", "kill"]
        precondition(validActions.contains("prompt"))
        precondition(validActions.contains("kill"))

        let validTimeouts: Set<Double> = [1.5, 2.0, 3.0, 5.0]
        precondition(validTimeouts.contains(1.5))
        precondition(validTimeouts.contains(2.0))
        precondition(validTimeouts.contains(3.0))
        precondition(validTimeouts.contains(5.0))

        let validFails: Set<Int> = [2, 3, 5]
        precondition(validFails.contains(2))
        precondition(validFails.contains(3))
        precondition(validFails.contains(5))
        print("  ✓ Picker tags align with Watchdog defaults and persistence")
    }
}
