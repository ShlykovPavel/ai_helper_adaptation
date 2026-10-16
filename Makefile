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
		test_tunnelguard_hook_gate.TestAgentPIDDetection \
		test_tunnelguard_hook_gate.TestShellWrapperFailClosed \
		test_tunnelguard_hook_gate.TestTunnelGuardGateE2E.test_e2e_deny_payload_schema

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

