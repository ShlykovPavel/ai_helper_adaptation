import Foundation

@main
enum HubPageTunnelGuardTests {
    static func main() {
        testHubPageTunnelGuardIntegration()
    }

    // Verifies that HubPage has .tunnelGuard registered in notchPages and routing
    static func testHubPageTunnelGuardIntegration() {
        assert(HubPage.notchPages.contains(.tunnelGuard), "HubPage.notchPages must contain .tunnelGuard")
        assert(HubPage.tunnelGuard.settingsSection == "tunnelGuard", "settingsSection for .tunnelGuard must be 'tunnelGuard'")
        assert(HubPage.forSettings("tunnelGuard") == .tunnelGuard, "HubPage.forSettings('tunnelGuard') must return .tunnelGuard")
        assert(HubPage.tunnelGuard.title == "TunnelGuard", "title must be 'TunnelGuard'")
        assert(HubPage.tunnelGuard.symbol == "shield.checkered", "symbol must be 'shield.checkered'")
        print("✅ testHubPageTunnelGuardIntegration passed")
    }
}

func testHubPageTunnelGuardIntegration() {
    HubPageTunnelGuardTests.testHubPageTunnelGuardIntegration()
}
