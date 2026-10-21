import Foundation
import AppKit

/// Окружение для изолированного тестирования TunnelGuard.
/// Гарантирует изоляцию от рабочего состояния системы:
/// - Отдельный временный каталог для `tunnelguard-state.json`
/// - Изолированный `UserDefaults(suiteName: ...)`
/// - Автоматическая очистка временных файлов и настроек при tearDown/deinit
/// - Фабричный метод `makeWatchdog(...)`
final class TunnelGuardTestContext {
    let tempDirectoryURL: URL
    let suiteName: String
    let defaults: UserDefaults
    let stateFileURL: URL
    private var isCleanedUp: Bool = false

    init(prefix: String = "tg-test") {
        let uniqueId = UUID().uuidString
        self.suiteName = "\(prefix)-\(uniqueId)"
        guard let customDefaults = UserDefaults(suiteName: self.suiteName) else {
            fatalError("Could not create isolated UserDefaults with suiteName: \(self.suiteName)")
        }
        self.defaults = customDefaults
        self.tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(uniqueId)", isDirectory: true)
        self.stateFileURL = self.tempDirectoryURL.appendingPathComponent("tunnelguard-state.json")
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    deinit {
        tearDown()
    }

    func tearDown() {
        guard !isCleanedUp else { return }
        isCleanedUp = true
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDirectoryURL)
    }

    @MainActor
    func makeWatchdog(
        powerGuard: TunnelGuardPowerGuard = TunnelGuardPowerGuard(),
        networkWorker: TunnelGuardNetworkWorker = TunnelGuardNetworkWorker()
    ) -> TunnelGuardWatchdog {
        TunnelGuardWatchdog(
            powerGuard: powerGuard,
            networkWorker: networkWorker,
            settingsDefaults: defaults,
            stateDirectoryURL: tempDirectoryURL
        )
    }
}
