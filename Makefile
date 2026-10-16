.PHONY: test test-tunnelguard test-tunnelguard-safe test-tunnelguard-swift-safe \
        test-tunnelguard-phase2-safe test-tunnelguard-phase3-safe test-tunnelguard-watchdog \
        test-tunnelguard-state-sync test-tunnelguard-python-safe test-tunnelguard-all test-tunnelguard-dangerous \
        build build-release release-build release \
        package dist

# Безопасный набор — используется по умолчанию. Не запускает тесты,
# которые намеренно посылают SIGKILL дочерним процессам.
test: test-tunnelguard-safe

test-tunnelguard: test-tunnelguard-safe

test-tunnelguard-safe: test-tunnelguard-swift-safe test-tunnelguard-phase2-safe test-tunnelguard-phase3-safe test-tunnelguard-watchdog test-tunnelguard-state-sync test-tunnelguard-python-safe

test-tunnelguard-swift-safe:
	./scripts/test-tunnelguard-phase1-safe.sh

test-tunnelguard-phase2-safe:
	./scripts/test-tunnelguard-phase2-safe.sh

test-tunnelguard-phase3-safe:
	./scripts/test-tunnelguard-phase3-safe.sh

test-tunnelguard-watchdog:
	./scripts/test-tunnelguard-watchdog.sh

test-tunnelguard-state-sync:
	./scripts/test-tunnelguard-state-sync.sh

test-tunnelguard-python-safe:
	PYTHONPATH=tests python3 -m unittest -v \
		test_tunnelguard_hook_gate.TestTunnelGuardHookVPNCheck \
		test_tunnelguard_hook_gate.TestTunnelGuardAppActiveCheck \
		test_tunnelguard_hook_gate.TestSplitTunnelAndExtendedInterfaces \
		test_tunnelguard_hook_gate.TestAgentPIDDetection \
		test_tunnelguard_hook_gate.TestShellWrapperFailClosed \
		test_tunnelguard_hook_gate.TestTunnelGuardGateE2E.test_e2e_deny_payload_schema \
		test_tunnelguard_hook_gate.TestTunnelGuardGateE2E.test_e2e_vpn_drop_ignored_when_app_offline \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario1_app_offline_no_state_file_clean_exit \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario1_app_offline_pid_dead_clean_exit \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario1_app_online_but_disabled_in_settings_clean_exit \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario1_agent_not_in_protected_targets_clean_exit \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario2_split_tunnel_antigravity_gemini_active \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario2_split_tunnel_claude_active \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario3_extended_interface_cscotun0_cisco \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario3_extended_interface_ppp0_point_to_point \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario3_extended_interface_tun0_openvpn \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario4_vpn_down_deny_payload_schema \
		test_tunnelguard_hook_gate.TestTunnelGuardL1GateScenariosE2E.test_e2e_scenario5_hook_script_generation_and_permissions

# Полный набор. Включает process-kill тесты и запускается только
# явной командой; перед запуском убедитесь, что это отдельное окружение.
test-tunnelguard-all:
	./scripts/test-tunnelguard.sh

test-tunnelguard-dangerous: test-tunnelguard-all

build:
	xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy \
		-configuration Debug -destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO build

build-release:
	./scripts/build-release.sh

release-build: build-release

release: build-release

package:
	./scripts/package.sh

dist:
	./scripts/package.sh

