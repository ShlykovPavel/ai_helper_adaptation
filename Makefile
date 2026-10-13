.PHONY: test test-gestapo test-gestapo-safe test-gestapo-swift-safe \
        test-gestapo-python-safe test-gestapo-all test-gestapo-dangerous build

# Безопасный набор — используется по умолчанию. Не запускает тесты,
# которые намеренно посылают SIGKILL дочерним процессам.
test: test-gestapo-safe

test-gestapo: test-gestapo-safe

test-gestapo-safe: test-gestapo-swift-safe test-gestapo-phase3-safe test-gestapo-python-safe

test-gestapo-swift-safe:
	./scripts/test-gestapo-phase1-safe.sh

test-gestapo-phase3-safe:
	./scripts/test-gestapo-phase3-safe.sh

test-gestapo-python-safe:
	PYTHONPATH=tests python3 -m unittest -v \
		test_gestapo_hook_gate.TestGestapoHookVPNCheck \
		test_gestapo_hook_gate.TestAgentPIDDetection \
		test_gestapo_hook_gate.TestShellWrapperFailClosed \
		test_gestapo_hook_gate.TestGestapoGateE2E.test_e2e_deny_payload_schema

# Полный исторический набор. Включает process-kill тесты и запускается только
# явной командой; перед запуском убедитесь, что это отдельное окружение.
test-gestapo-all:
	./scripts/test-gestapo.sh

test-gestapo-dangerous: test-gestapo-all

build:
	xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy \
		-configuration Debug -destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO build
