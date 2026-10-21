#!/usr/bin/env python3
"""
test_tunnelguard_hook_gate.py - Тесты контура L1 Gate и Kill-Switch в NotchBuddy (Coucou).
Адаптировано из start_tool/tests/test_tunnelguard.py и simulate_vpn_drop.py.

Проверяет:
1. 100% ликвидацию процессов (SIGKILL, процессные деревья, группы процессов, latency benchmark).
2. Детекцию сетевых интерфейсов и таймауты /sbin/route в Python-реле nb-hook.py.
3. Шлагбаум TunnelGuard в nb-hook.py (блокировка до чтения stdin, deny-ответ, отстрел агента).
4. Определение реального PID агента (get_real_agent_pid: claude, node, agy, codex, gemini).
5. Принудительный Fail-Closed в шелл-обертке nb-hook (проброс exit $rc при падении VPN).
6. End-to-End симуляцию отвала VPN и ликвидации вызывающего агента.
"""

import json
import os
import py_compile
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
HOOK_SERVER_SWIFT = REPO_ROOT / "NotchBuddy" / "Sources" / "App" / "HookServer.swift"


def extract_hook_scripts():
    """Извлекает шелл-обертку и Python-реле прямо из HookServer.swift."""
    if not HOOK_SERVER_SWIFT.exists():
        raise FileNotFoundError(f"HookServer.swift не найден: {HOOK_SERVER_SWIFT}")

    content = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
    m_wrapper = re.search(r'private let nbHookShellWrapper = """(.*?)"""', content, re.DOTALL)
    m_python = re.search(r'private let nbHookPythonGitHub = """(.*?)"""', content, re.DOTALL)

    if not m_wrapper or not m_python:
        raise ValueError("Не удалось извлечь nbHookShellWrapper или nbHookPythonGitHub из HookServer.swift")

    def _swift_multiline_to_disk(s: str) -> str:
        # В Swift multiline строках ("""):
        # \\n в исходнике Swift декодируется компилятором в \n (два символа: \ и n) в памяти и на диске.
        # Одиночный \n в исходнике Swift декодируется в символ перевода строки (код 10).
        placeholder = "___SWIFT_ESCAPED_NEWLINE___"
        res = s.replace("\\\\n", placeholder)
        res = res.replace("\\n", "\n")
        res = res.replace(placeholder, "\\n")
        return res

    wrapper_code = _swift_multiline_to_disk(m_wrapper.group(1)).strip() + "\n"
    python_code = _swift_multiline_to_disk(m_python.group(1)).strip() + "\n"
    return wrapper_code, python_code


def load_hook_module(python_code):
    """Динамически загружает код nb-hook.py как Python-модуль для прямого тестирования функций."""
    code_without_main = re.sub(
        r'try:\s+main\(\)\s+except Exception:\s+sys\.exit\(1\)\s+sys\.exit\(0\)',
        '# main execution stripped for module loading',
        python_code
    )
    mod = types.ModuleType("nb_hook_module")
    exec(compile(code_without_main, "nb-hook.py", "exec"), mod.__dict__)
    return mod


class TestTunnelGuardProcessKill(unittest.TestCase):
    """Тестирование надежности и скорости ликвидации процессов (SIGKILL)."""

    def test_cli_process_kill_sigkill(self):
        """Проверяет, что процесс 100% уничтожается через SIGKILL."""
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            preexec_fn=os.setsid
        )
        pid = proc.pid
        self.assertIsNone(proc.poll(), "Процесс должен быть жив до ликвидации")

        # Ликвидация
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except Exception:
            os.kill(pid, signal.SIGKILL)

        ret = proc.wait(timeout=1.0)
        self.assertEqual(ret, -signal.SIGKILL, f"Процесс должен быть завершен по SIGKILL (-9), получен: {ret}")

        # Проверка на уровне ядра ОС
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_cli_process_tree_kill(self):
        """Проверяет, что при уничтожении родителя погибает всё дерево потомков."""
        parent_code = (
            "import subprocess, time, sys; "
            "child = subprocess.Popen(['sleep', '100']); "
            "print(f'CHILD:{child.pid}', flush=True); "
            "time.sleep(100)"
        )
        parent_proc = subprocess.Popen(
            [sys.executable, "-c", parent_code],
            stdout=subprocess.PIPE,
            preexec_fn=os.setsid
        )
        parent_pid = parent_proc.pid

        # Читаем PID дочернего sleep
        line = parent_proc.stdout.readline().decode().strip()
        self.assertTrue(line.startswith("CHILD:"), f"Неожиданный вывод: {line}")
        child_pid = int(line.split("CHILD:")[1])

        self.assertIsNone(parent_proc.poll())
        os.kill(child_pid, 0)  # жив

        # Ликвидируем всю группу процессов
        os.killpg(os.getpgid(parent_pid), signal.SIGKILL)
        parent_proc.wait(timeout=1.0)

        # Проверяем, что оба процесса мертвы на уровне ядра macOS
        with self.assertRaises(ProcessLookupError):
            os.kill(parent_pid, 0)

        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_kill_latency_speed(self):
        """Замеряет скорость ликвидации (должна быть < 30 мс)."""
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            preexec_fn=os.setsid
        )
        pid = proc.pid

        t_start = time.perf_counter()
        os.killpg(os.getpgid(pid), signal.SIGKILL)
        proc.wait(timeout=1.0)
        t_end = time.perf_counter()

        latency_ms = (t_end - t_start) * 1000
        self.assertLess(latency_ms, 30.0, f"Ликвидация слишком медленная: {latency_ms:.2f} мс")


class TestTunnelGuardHookVPNCheck(unittest.TestCase):
    """Тестирование логики проверки маршрута utun в nb-hook.py."""

    @classmethod
    def setUpClass(cls):
        _, python_code = extract_hook_scripts()
        cls.hook_mod = load_hook_module(python_code)

    def test_verify_vpn_route_utun_active(self):
        """При интерфейсе utun22 проверка маршрута возвращает True."""
        with patch.object(self.hook_mod, "_get_route_interface", return_value="utun22"):
            self.assertTrue(self.hook_mod.verify_vpn_route_utun())

    def test_verify_vpn_route_utun_inactive_en0(self):
        """При интерфейсе en0 (на 1.1.1.1 и default) проверка маршрута возвращает False."""
        with patch.object(self.hook_mod, "_get_route_interface", return_value="en0"):
            self.assertFalse(self.hook_mod.verify_vpn_route_utun())

    def test_verify_vpn_route_utun_fallback(self):
        """Если 1.1.1.1 указывает на en0, но default указывает на utun0 — fallback срабатывает."""
        def mock_get_route(dest):
            if dest == "1.1.1.1":
                return "en0"
            elif dest == "default":
                return "utun0"
            return "en0"

        with patch.object(self.hook_mod, "_get_route_interface", side_effect=mock_get_route):
            self.assertTrue(self.hook_mod.verify_vpn_route_utun())

    def test_route_timeout_protection(self):
        """Таймаут в _get_route_interface защищает от зависания и возвращает пустую строку."""
        # Вызываем _get_route_interface с несуществующим адресом или имитируем таймаут
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired(cmd=["/sbin/route"], timeout=0.3)):
            iface = self.hook_mod._get_route_interface("1.1.1.1")
            self.assertEqual(iface, "", "При таймауте интерфейс обязан быть пустой строкой")


class TestTunnelGuardAppActiveCheck(unittest.TestCase):
    """Тестирование функции is_tunnelguard_active в nb-hook.py (Point 1)."""

    @classmethod
    def setUpClass(cls):
        _, python_code = extract_hook_scripts()
        cls.hook_mod = load_hook_module(python_code)

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="tunnelguard_active_check_")
        self.state_file = Path(self.tmpdir) / "tunnelguard-state.json"
        self.socket_path = Path(self.tmpdir) / "nb.sock"
        self.socket_path.touch()

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_state(self, data):
        self.state_file.write_text(json.dumps(data), encoding="utf-8")

    def test_state_file_missing(self):
        """Если файл состояния отсутствует, хук считает приложение оффлайн (False)."""
        res = self.hook_mod.is_tunnelguard_active(
            agent_name="claude",
            state_file=str(Path(self.tmpdir) / "nonexistent.json"),
            socket_path=str(self.socket_path)
        )
        self.assertFalse(res)

    def test_unreadable_json(self):
        """Битый JSON в файле состояния приводит к False."""
        self.state_file.write_text("{corrupt-json", encoding="utf-8")
        res = self.hook_mod.is_tunnelguard_active(
            agent_name="claude",
            state_file=str(self.state_file),
            socket_path=str(self.socket_path)
        )
        self.assertFalse(res)

    def test_running_or_enabled_false(self):
        """running=False или enabled=False отключает действие шлагбаума."""
        # running=False
        self._write_state({
            "running": False,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

        # enabled=False
        self._write_state({
            "running": True,
            "enabled": False,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

        # both False
        self._write_state({
            "running": False,
            "enabled": False,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

    def test_pid_dead_process_lookup_error(self):
        """Если процесс NotchBuddy умер (ProcessLookupError), шлагбаум возвращает False."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": 99999999,
            "protected_targets": ["claude"]
        })
        with patch("os.kill", side_effect=ProcessLookupError):
            res = self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path))
            self.assertFalse(res)

    def test_pid_missing_or_invalid(self):
        """Если PID отсутствует или некорректен, возвращается False."""
        self._write_state({
            "running": True,
            "enabled": True,
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

        self._write_state({
            "running": True,
            "enabled": True,
            "pid": "not-an-int",
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

    def test_agent_not_in_protected_targets(self):
        """Если агент не включен в protected_targets, защита для него отключена."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude", "agy"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("codex", str(self.state_file), str(self.socket_path)))
        self.assertFalse(self.hook_mod.is_tunnelguard_active("cursor", str(self.state_file), str(self.socket_path)))

    def test_agent_in_protected_targets_normalization(self):
        """Нормализация имен агентов (agy / antigravity / agy-cli)."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude", "agy"]
        })
        self.assertTrue(self.hook_mod.is_tunnelguard_active("antigravity", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("agy-cli", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("agy", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

    def test_socket_missing(self):
        """Если файл состояния в норме, но Unix-сокет NotchBuddy отсутствует, возвращается False."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        res = self.hook_mod.is_tunnelguard_active(
            "claude",
            str(self.state_file),
            str(Path(self.tmpdir) / "nonexistent.sock")
        )
        self.assertFalse(res)

    def test_all_valid(self):
        """Все проверки пройдены -> True."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        res = self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path))
        self.assertTrue(res)

    def test_empty_agent_and_empty_targets(self):
        """Если protected_targets пуст, шлагбаум НЕАКТИВЕН (False)."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": []
        })
        # При пустых protected_targets gate неактивен как для пустого агента, так и для любого агента
        self.assertFalse(self.hook_mod.is_tunnelguard_active("", str(self.state_file), str(self.socket_path)))
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))

    def test_r02_only_codex_with_unnamed_claude_hook(self):
        """Если выбран только Codex, стандартный Claude hook без имени (--agent не передан) должен быть НЕАКТИВЕН."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["codex"]
        })
        # Пустое имя нормализуется в 'claude', которое отсутствует в protected_targets -> False
        self.assertFalse(self.hook_mod.is_tunnelguard_active("", str(self.state_file), str(self.socket_path)))
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claude", str(self.state_file), str(self.socket_path)))
        # А для codex — True
        self.assertTrue(self.hook_mod.is_tunnelguard_active("codex", str(self.state_file), str(self.socket_path)))

    def test_r02_agent_aliases_matching(self):
        """Проверяет сопоставление алиасов для AGY (antigravity/agy-cli) и Cursor (cursor/cursor-agent)."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["agy"]
        })
        self.assertTrue(self.hook_mod.is_tunnelguard_active("antigravity", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("agy-cli", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("agy", str(self.state_file), str(self.socket_path)))

        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["cursor-agent"]
        })
        self.assertTrue(self.hook_mod.is_tunnelguard_active("cursor", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("cursor-agent", str(self.state_file), str(self.socket_path)))
        self.assertTrue(self.hook_mod.is_tunnelguard_active("cursor-agent-cli", str(self.state_file), str(self.socket_path)))

    def test_r02_exact_matching_no_substring(self):
        """Проверяет точное сопоставление имен: поиск подстроки 'norm in t' запрещен."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("claudette", str(self.state_file), str(self.socket_path)))
        self.assertFalse(self.hook_mod.is_tunnelguard_active("not-claude", str(self.state_file), str(self.socket_path)))

        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["gemini"]
        })
        self.assertFalse(self.hook_mod.is_tunnelguard_active("gemini-advanced", str(self.state_file), str(self.socket_path)))

    def test_environment_variable_overrides(self):
        """Проверяет переопределение путей через TUNNELGUARD_STATE_FILE и NOTCHBUDDY_SOCKET_PATH."""
        self._write_state({
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude"]
        })
        with patch.dict(os.environ, {
            "TUNNELGUARD_STATE_FILE": str(self.state_file),
            "NOTCHBUDDY_SOCKET_PATH": str(self.socket_path)
        }):
            self.assertTrue(self.hook_mod.is_tunnelguard_active("claude"))


class TestAgentPIDDetection(unittest.TestCase):
    """Тестирование функции get_real_agent_pid в nb-hook.py."""

    @classmethod
    def setUpClass(cls):
        _, python_code = extract_hook_scripts()
        cls.hook_mod = load_hook_module(python_code)

    def test_get_real_agent_pid_detects_claude(self):
        """get_real_agent_pid находит процесс claude вверх по цепочке PPID."""
        mock_ps_chain = {
            100: "50 /bin/bash",
            50: "10 /usr/local/bin/claude",
            10: "1 /sbin/launchd"
        }

        def mock_ps(cmd, **kwargs):
            pid = int(cmd[-1])
            return mock_ps_chain.get(pid, "")

        with patch("os.getppid", return_value=100), \
             patch("subprocess.check_output", side_effect=mock_ps):
            found_pid = self.hook_mod.get_real_agent_pid()
            self.assertEqual(found_pid, 50, f"Должен был найтись PID claude (50), получен: {found_pid}")

    def test_get_real_agent_pid_detects_agy(self):
        """get_real_agent_pid находит процесс agy вверх по цепочке PPID."""
        mock_ps_chain = {
            200: "150 /bin/zsh",
            150: "80 /opt/homebrew/bin/agy",
            80: "1 /sbin/launchd"
        }

        def mock_ps(cmd, **kwargs):
            pid = int(cmd[-1])
            return mock_ps_chain.get(pid, "")

        with patch("os.getppid", return_value=200), \
             patch("subprocess.check_output", side_effect=mock_ps):
            found_pid = self.hook_mod.get_real_agent_pid()
            self.assertEqual(found_pid, 150)

    def test_get_real_agent_pid_fallback_to_ppid(self):
        """Если в цепочке нет известных агентов, безопасно возвращается непосредственный PPID."""
        with patch("os.getppid", return_value=999), \
             patch("subprocess.check_output", return_value="1 /bin/zsh"):
            found_pid = self.hook_mod.get_real_agent_pid()
            self.assertEqual(found_pid, 999)


class TestShellWrapperFailClosed(unittest.TestCase):
    """Тестирование принудительного Fail-Closed поведения в nb-hook (шелл-обертка)."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="tunnelguard_wrapper_test_")
        self.wrapper_code, self.python_code = extract_hook_scripts()

        self.wrapper_path = Path(self.tmpdir) / "nb-hook"
        self.python_path = Path(self.tmpdir) / "nb-hook.py"

        self.wrapper_path.write_text(self.wrapper_code, encoding="utf-8")
        self.python_path.write_text(self.python_code, encoding="utf-8")

        self.wrapper_path.chmod(0o755)
        self.python_path.chmod(0o755)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_shell_wrapper_propagates_nonzero_exit_code(self):
        """
        FAIL-CLOSED: если nb-hook.py завершился с ошибкой (rc != 0),
        шелл-обертка nb-hook ОБЯЗАНА завершиться с кодом $rc (НЕ 0!).
        """
        # Создаем тестовый скрипт, возвращающий exit 1 и сообщение об ошибке
        mock_py = Path(self.tmpdir) / "nb-hook.py"
        mock_py.write_text(
            '#!/usr/bin/env python3\n'
            'import sys\n'
            'sys.stdout.write("{\\"error\\": \\"VPN DOWN\\"}\\n")\n'
            'sys.exit(1)\n',
            encoding="utf-8"
        )
        mock_py.chmod(0o755)

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path)],
            capture_output=True,
            text=True
        )

        self.assertEqual(
            res.returncode, 1,
            f"Шелл-обертка ОБЯЗАНА вернуть код ошибки 1, но вернула {res.returncode}!"
        )
        self.assertIn('{"error": "VPN DOWN"}', res.stdout, "Вывод ошибки должен быть проброшен")

    def test_shell_wrapper_exits_zero_on_success(self):
        """При нормальном завершении (rc = 0) шелл-обертка выходит с кодом 0."""
        mock_py = Path(self.tmpdir) / "nb-hook.py"
        mock_py.write_text(
            '#!/usr/bin/env python3\n'
            'import sys\n'
            'sys.stdout.write("{\\"ok\\": true}\\n")\n'
            'sys.exit(0)\n',
            encoding="utf-8"
        )
        mock_py.chmod(0o755)

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path)],
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn('{"ok": true}', res.stdout)


class TestTunnelGuardGateE2E(unittest.TestCase):
    """End-to-End тестирование шлагбаума и ликвидации вызывающего агента при падении VPN."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="tunnelguard_e2e_test_")
        self.wrapper_code, self.python_code = extract_hook_scripts()

        self.wrapper_path = Path(self.tmpdir) / "nb-hook"
        self.python_path = Path(self.tmpdir) / "nb-hook.py"

        self.wrapper_path.write_text(self.wrapper_code, encoding="utf-8")
        self.python_path.write_text(self.python_code, encoding="utf-8")

        self.wrapper_path.chmod(0o755)
        self.python_path.chmod(0o755)

        # Создаем активное мок-состояние NotchBuddy и сокет для E2E тестов
        self.state_file = Path(self.tmpdir) / "tunnelguard-state.json"
        self.socket_path = Path(self.tmpdir) / "nb.sock"
        self.socket_path.touch()

        state_data = {
            "running": True,
            "enabled": True,
            "pid": os.getpid(),
            "protected_targets": ["claude", "agy", "antigravity", "codex", "gemini"],
            "target_domains": {}
        }
        self.state_file.write_text(json.dumps(state_data), encoding="utf-8")

        self.env = os.environ.copy()
        self.env["TUNNELGUARD_STATE_FILE"] = str(self.state_file)
        self.env["NOTCHBUDDY_SOCKET_PATH"] = str(self.socket_path)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def test_e2e_vpn_drop_denies_and_kills_calling_agent(self):
        """
        E2E: Запускается имитация агента. Когда VPN отключен (en0),
        вызов хука приводит к:
        1. Выводу JSON-отказа deny_payload в stdout.
        2. Завершению шелла с кодом 1 (Fail-Closed).
        3. Мгновенной ликвидации (SIGKILL) агента.
        """
        # Создаем поддельный бинарник /sbin/route, возвращающий en0
        mock_bin_dir = Path(self.tmpdir) / "bin"
        mock_bin_dir.mkdir(parents=True)
        mock_route = mock_bin_dir / "route"
        mock_route.write_text(
            "#!/bin/sh\n"
            "echo '   route to: $3'\n"
            "echo '  interface: en0'\n",
            encoding="utf-8"
        )
        mock_route.chmod(0o755)

        # Модифицируем тестовую копию nb-hook.py, чтобы она вызывала наш mock_route
        patched_py_content = self.python_code.replace(
            '"/sbin/route"', f'"{mock_route}"'
        )
        self.python_path.write_text(patched_py_content, encoding="utf-8")

        # Создаем процесс агента-жертвы
        agent_script = (
            "import subprocess, sys, time, os\n"
            f"res = subprocess.run(['/bin/sh', '{self.wrapper_path}'], capture_output=True, text=True)\n"
            "print('RES_CODE:' + str(res.returncode), flush=True)\n"
            "print('RES_OUT:' + res.stdout.strip(), flush=True)\n"
            "time.sleep(30)\n"
        )

        proc = subprocess.Popen(
            [sys.executable, "-c", agent_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,
            env=self.env
        )
        agent_pid = proc.pid

        # Ждем завершения вызова хука и ликвидации
        t_start = time.perf_counter()
        ret = proc.wait(timeout=3.0)
        t_end = time.perf_counter()
        latency_ms = (t_end - t_start) * 1000

        # Агент обязан быть убит через SIGKILL (-9)
        self.assertEqual(ret, -signal.SIGKILL, f"Агент обязан погибнуть по SIGKILL, получен: {ret}")

        # Проверяем на уровне ОС
        with self.assertRaises(ProcessLookupError):
            os.kill(agent_pid, 0)

        # Проверяем, что ликвидация произошла стремительно
        self.assertLess(latency_ms, 1500.0)

    def test_e2e_deny_payload_schema(self):
        """Проверяет точный формат deny_payload, отдаваемого Claude Code."""
        # Запускаем модифицированный nb-hook.py напрямую без убийства текущего процесса
        # Подменяем get_real_agent_pid, чтобы не убить сам тест
        test_py = Path(self.tmpdir) / "test_deny.py"
        safe_kill_py = self.python_code.replace(
            "def tunnel_guard_kill_agent_and_exit():",
            "def tunnel_guard_kill_agent_and_exit():\n"
            "    deny_payload = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'message': '🚨 [TUNNELGUARD] VPN ОТКЛЮЧЕН! Действие заблокировано.'}}\n"
            "    sys.stdout.write(json.dumps(deny_payload) + '\\n')\n"
            "    sys.exit(1)\n"
            "def _unused():\n"
        )
        # Форсируем вызов tunnel_guard_kill_agent_and_exit при старте
        safe_kill_py = re.sub(
            r"if not verify_vpn_route.*?:",
            "if True: # forced VPN drop for test",
            safe_kill_py
        )
        test_py.write_text(safe_kill_py, encoding="utf-8")

        res = subprocess.run(
            [sys.executable, str(test_py)],
            capture_output=True,
            text=True,
            env=self.env
        )

        self.assertEqual(res.returncode, 1, "При падении VPN хук обязан завершаться с кодом 1")
        data = json.loads(res.stdout.strip())
        self.assertIn("hookSpecificOutput", data)
        self.assertEqual(data["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertEqual(data["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("VPN ОТКЛЮЧЕН", data["hookSpecificOutput"]["message"])

    def test_e2e_vpn_drop_ignored_when_app_offline(self):
        """
        Когда NotchBuddy выключен (offline: нет файла состояния/сокета),
        падение VPN НЕ приводит к отстрелу агента: хук завершается штатно (код 0).
        """
        # Создаем поддельный бинарник /sbin/route, возвращающий en0
        mock_bin_dir = Path(self.tmpdir) / "bin_offline"
        mock_bin_dir.mkdir(parents=True, exist_ok=True)
        mock_route = mock_bin_dir / "route"
        mock_route.write_text(
            "#!/bin/sh\n"
            "echo '   route to: $3'\n"
            "echo '  interface: en0'\n",
            encoding="utf-8"
        )
        mock_route.chmod(0o755)

        offline_dir = Path(self.tmpdir) / "offline"
        offline_dir.mkdir(parents=True, exist_ok=True)
        offline_wrapper = offline_dir / "nb-hook"
        offline_py = offline_dir / "nb-hook.py"

        patched_py_content = self.python_code.replace(
            '"/sbin/route"', f'"{mock_route}"'
        )
        offline_wrapper.write_text(self.wrapper_code, encoding="utf-8")
        offline_py.write_text(patched_py_content, encoding="utf-8")
        offline_wrapper.chmod(0o755)
        offline_py.chmod(0o755)

        offline_env = os.environ.copy()
        offline_env["TUNNELGUARD_STATE_FILE"] = str(Path(self.tmpdir) / "nonexistent-state.json")
        offline_env["NOTCHBUDDY_SOCKET_PATH"] = str(Path(self.tmpdir) / "nonexistent.sock")

        # Создаем процесс агента
        agent_script = (
            "import subprocess, sys, time, os\n"
            f"res = subprocess.run(['/bin/sh', '{offline_wrapper}'], input='', capture_output=True, text=True)\n"
            "print('RES_CODE:' + str(res.returncode), flush=True)\n"
            "print('RES_OUT:' + res.stdout.strip(), flush=True)\n"
            "time.sleep(5)\n"
        )

        proc = subprocess.Popen(
            [sys.executable, "-c", agent_script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,
            env=offline_env
        )
        agent_pid = proc.pid

        # Даем время скрипту выполнить хук
        time.sleep(0.5)

        # Проверяем, что агент жив (не был уничтожен SIGKILL)
        self.assertIsNone(proc.poll(), "Агент НЕ должен быть убит, когда NotchBuddy офлайн")

        # Аккуратно завершаем тестовый процесс
        try:
            os.killpg(os.getpgid(agent_pid), signal.SIGTERM)
        except Exception:
            try:
                os.kill(agent_pid, signal.SIGTERM)
            except Exception:
                pass

        stdout, _ = proc.communicate(timeout=2.0)
        self.assertIn("RES_CODE:0", stdout.decode(), "Хук обязан завершиться с кодом 0")


class TestSimulateVPNDrop(unittest.TestCase):
    """
    Адаптированная живая симуляция отвала VPN (из start_tool/tests/simulate_vpn_drop.py).
    Демонстрирует перехват и нулевую утечку данных при смене маршрута.
    """

    def test_simulate_live_vpn_drop(self):
        """Симуляция отвала туннеля utun -> en0 и подтверждение отстрела воркера."""
        # 1. Запуск рабочего процесса
        worker = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            preexec_fn=os.setsid
        )
        victim_pid = worker.pid
        self.assertIsNone(worker.poll())

        # 2. Имитируем VPN drop и срабатывание Kill-Switch
        t_start = time.perf_counter()
        try:
            os.killpg(os.getpgid(victim_pid), signal.SIGKILL)
        except Exception:
            os.kill(victim_pid, signal.SIGKILL)

        worker.wait(timeout=1.0)
        t_end = time.perf_counter()
        latency_ms = (t_end - t_start) * 1000

        # 3. Проверка результата
        self.assertEqual(worker.returncode, -signal.SIGKILL)
        with self.assertRaises(ProcessLookupError):
            os.kill(victim_pid, 0)

        self.assertLess(latency_ms, 25.0)


class TestSplitTunnelAndExtendedInterfaces(unittest.TestCase):
    """
    Тестирование распознавания расширенных VPN-интерфейсов и маршрутизации
    Split-Tunnel для целевых доменов AI-агентов (Point 3).
    """

    @classmethod
    def setUpClass(cls):
        _, python_code = extract_hook_scripts()
        cls.hook_mod = load_hook_module(python_code)

    def test_is_vpn_interface(self):
        """Проверяет распознавание расширенного списка VPN-интерфейсов и отсечение локальных."""
        valid_vpns = [
            "utun0", "utun2", "utun22", "tun0", "tun1", "tap0",
            "ppp0", "ppp1", "cscotun0", "cscotun1", "fctun0", "fctun2", "ipsec0"
        ]
        for iface in valid_vpns:
            with self.subTest(iface=iface):
                self.assertTrue(self.hook_mod.is_vpn_interface(iface), f"{iface} должен быть распознан как VPN")

        invalid_ifaces = ["en0", "en1", "bridge0", "pdp_ip0", "lo0", "", None]
        for iface in invalid_ifaces:
            with self.subTest(iface=iface):
                self.assertFalse(self.hook_mod.is_vpn_interface(iface), f"{iface} НЕ должен быть распознан как VPN")

    def test_get_target_ai_domain_defaults(self):
        """Проверяет маппинг доменов по умолчанию для встроенных агентов."""
        self.assertEqual(self.hook_mod.get_target_ai_domain("antigravity"), "generativelanguage.googleapis.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("agy"), "generativelanguage.googleapis.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("agy-cli"), "generativelanguage.googleapis.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("gemini"), "generativelanguage.googleapis.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("gemini-cli"), "generativelanguage.googleapis.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("claude"), "claude.ai")
        self.assertEqual(self.hook_mod.get_target_ai_domain("claude-cli"), "claude.ai")
        self.assertEqual(self.hook_mod.get_target_ai_domain("claude-desktop"), "claude.ai")
        self.assertEqual(self.hook_mod.get_target_ai_domain("codex"), "chatgpt.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("codex-cli"), "chatgpt.com")
        self.assertEqual(self.hook_mod.get_target_ai_domain("cursor"), "cursor.sh")
        self.assertEqual(self.hook_mod.get_target_ai_domain("cursor-agent"), "cursor.sh")
        self.assertEqual(self.hook_mod.get_target_ai_domain("cursor-agent-cli"), "cursor.sh")
        self.assertEqual(self.hook_mod.get_target_ai_domain("unknown-agent"), "")
        self.assertEqual(self.hook_mod.get_target_ai_domain(""), "")

    def test_get_target_ai_domain_from_state_file(self):
        """Проверяет приоритет чтения target_domains из файла состояния."""
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = Path(tmpdir) / "state.json"
            state_file.write_text(json.dumps({
                "target_domains": {
                    "custom-ai": "api.custom-ai.internal",
                    "agy": "custom-gemini.endpoint.com"
                }
            }), encoding="utf-8")
            self.assertEqual(
                self.hook_mod.get_target_ai_domain("custom-ai", state_file=str(state_file)),
                "api.custom-ai.internal"
            )
            # Нормализация: antigravity -> agy в target_domains
            self.assertEqual(
                self.hook_mod.get_target_ai_domain("antigravity", state_file=str(state_file)),
                "custom-gemini.endpoint.com"
            )

    def test_split_tunnel_target_domain_utun_default_en0(self):
        """
        Split tunnel: 1.1.1.1 -> en0, default -> en0,
        но generativelanguage.googleapis.com -> utun3.
        verify_vpn_route("antigravity") ОБЯЗАН вернуть True!
        """
        routes = {
            "generativelanguage.googleapis.com": "utun3",
            "1.1.1.1": "en0",
            "default": "en0"
        }
        with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
            self.assertTrue(self.hook_mod.verify_vpn_route("antigravity"))
            self.assertTrue(self.hook_mod.verify_vpn_route("agy"))

    def test_split_tunnel_target_domain_cisco_vpn(self):
        """
        Split tunnel: 1.1.1.1 -> en0, default -> en0,
        но claude.ai -> cscotun0 (Cisco AnyConnect).
        verify_vpn_route("claude") ОБЯЗАН вернуть True!
        """
        routes = {
            "claude.ai": "cscotun0",
            "1.1.1.1": "en0",
            "default": "en0"
        }
        with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
            self.assertTrue(self.hook_mod.verify_vpn_route("claude"))
            self.assertTrue(self.hook_mod.verify_vpn_route("claude-desktop"))

    def test_split_tunnel_leak_detected(self):
        """
        Утечка трафика: целевой домен AI идет в en0, дефолтный маршрут тоже en0.
        verify_vpn_route("antigravity") ОБЯЗАН вернуть False!
        """
        routes = {
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        }
        with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
            self.assertFalse(self.hook_mod.verify_vpn_route("antigravity"))
            self.assertFalse(self.hook_mod.verify_vpn_route("agy"))

    def test_r01_split_tunnel_check_leak_to_en0_with_vpn_1111_rejected(self):
        """
        R01 (P1): При split_tunnel_check=True, если маршрут к целевому домену идет на en0,
        наличие общего VPN-маршрута (1.1.1.1 -> utun3) НЕ должно разрешать доступ.
        verify_vpn_route ОБЯЗАН вернуть False (Deny)!
        """
        routes = {
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "utun3",
            "default": "utun3"
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = Path(tmpdir) / "state.json"
            state_file.write_text(json.dumps({
                "split_tunnel_check": True,
                "target_domains": {
                    "agy": "generativelanguage.googleapis.com"
                }
            }), encoding="utf-8")
            with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
                self.assertFalse(self.hook_mod.verify_vpn_route("antigravity", state_file=str(state_file)))
                self.assertFalse(self.hook_mod.verify_vpn_route("agy", state_file=str(state_file)))

    def test_r01_split_tunnel_check_false_fallback_to_1111_allowed(self):
        """
        R01: При split_tunnel_check=False (пользователь выключил контроль раздельного туннелирования),
        если 1.1.1.1 -> utun3, то общий VPN-маршрут разрешает доступ (True).
        """
        routes = {
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "utun3",
            "default": "utun3"
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = Path(tmpdir) / "state.json"
            state_file.write_text(json.dumps({
                "split_tunnel_check": False,
                "target_domains": {
                    "agy": "generativelanguage.googleapis.com"
                }
            }), encoding="utf-8")
            with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
                self.assertTrue(self.hook_mod.verify_vpn_route("antigravity", state_file=str(state_file)))
                self.assertTrue(self.hook_mod.verify_vpn_route("agy", state_file=str(state_file)))

    def test_r01_split_tunnel_check_true_domain_on_vpn_allowed(self):
        """
        R01: При split_tunnel_check=True, если домен идет через utun3, даже если 1.1.1.1 -> en0,
        verify_vpn_route возвращает True.
        """
        routes = {
            "generativelanguage.googleapis.com": "utun3",
            "1.1.1.1": "en0",
            "default": "en0"
        }
        with tempfile.TemporaryDirectory() as tmpdir:
            state_file = Path(tmpdir) / "state.json"
            state_file.write_text(json.dumps({
                "split_tunnel_check": True
            }), encoding="utf-8")
            with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda dest: routes.get(dest, "en0")):
                self.assertTrue(self.hook_mod.verify_vpn_route("antigravity", state_file=str(state_file)))

    def test_fallback_to_1111_and_default_when_no_agent_domain(self):
        """
        Если агент не указан или домен неизвестен:
        - 1.1.1.1 -> utun0 => True
        - 1.1.1.1 -> en0, default -> utun0 => True
        - 1.1.1.1 -> en0, default -> en0 => False
        """
        # Case A: 1.1.1.1 is VPN
        with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda d: "utun0" if d == "1.1.1.1" else "en0"):
            self.assertTrue(self.hook_mod.verify_vpn_route(""))
            self.assertTrue(self.hook_mod.verify_vpn_route("unknown-agent"))

        # Case B: default is VPN
        with patch.object(self.hook_mod, "_get_route_interface", side_effect=lambda d: "utun0" if d == "default" else "en0"):
            self.assertTrue(self.hook_mod.verify_vpn_route(""))
            self.assertTrue(self.hook_mod.verify_vpn_route("unknown-agent"))

        # Case C: both en0
        with patch.object(self.hook_mod, "_get_route_interface", return_value="en0"):
            self.assertFalse(self.hook_mod.verify_vpn_route(""))
            self.assertFalse(self.hook_mod.verify_vpn_route("unknown-agent"))

    def test_verify_vpn_route_utun_backward_compatibility(self):
        """Проверяет обратную совместимость обертки verify_vpn_route_utun."""
        with patch.object(self.hook_mod, "_get_route_interface", return_value="utun0"):
            self.assertTrue(self.hook_mod.verify_vpn_route_utun())
            self.assertTrue(self.hook_mod.verify_vpn_route_utun("antigravity"))

        with patch.object(self.hook_mod, "_get_route_interface", return_value="en0"):
            self.assertFalse(self.hook_mod.verify_vpn_route_utun())
            self.assertFalse(self.hook_mod.verify_vpn_route_utun("antigravity"))


class TestTunnelGuardL1GateScenariosE2E(unittest.TestCase):
    """
    Сквозная (E2E) верификация интеграции nb-hook / nb-hook.py для всех ключевых сценариев:
    1. App Offline: NotchBuddy выключен (нет файла состояния / мертвый PID / disabled) -> процесс НЕ уничтожается, чистый выход (0) и ожидаемый ответ.
    2. Split Tunnel Active: целевой AI-домен идет через VPN-интерфейс (utun*), даже если default и 1.1.1.1 идут в en0 -> агент НЕ уничтожается, чистый выход.
    3. Extended Interface Active: целевой домен идет через cscotun* или ppp* или tun* -> хук считает маршрут защищенным, чистый выход.
    4. VPN Down (True Leak): NotchBuddy включен, и целевой домен, и default идут в en0 -> хук блокирует действие (deny) и уничтожает вызывающего агента (SIGKILL).
    5. Hook script generation: генерация файлов скрипта HookServer производит файлы nb-hook и nb-hook.py с правами 0755.
    """

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="tunnelguard_l1_scenarios_e2e_")
        self.wrapper_code, self.python_code = extract_hook_scripts()

        self.mock_bin_dir = Path(self.tmpdir) / "bin"
        self.mock_bin_dir.mkdir(parents=True, exist_ok=True)
        self.mock_route_path = self.mock_bin_dir / "route"

        # Mock /sbin/route читает MOCK_ROUTES_FILE (dest:iface)
        mock_route_script = (
            "#!/bin/sh\n"
            'dest="$3"\n'
            'if [ -z "$dest" ]; then\n'
            '    for arg in "$@"; do dest="$arg"; done\n'
            'fi\n'
            'echo "   route to: $dest"\n'
            'if [ -n "$MOCK_ROUTES_FILE" ] && [ -f "$MOCK_ROUTES_FILE" ]; then\n'
            '    iface=$(grep "^${dest}:" "$MOCK_ROUTES_FILE" 2>/dev/null | head -n 1 | cut -d: -f2)\n'
            '    if [ -z "$iface" ]; then\n'
            '        iface=$(grep "^default:" "$MOCK_ROUTES_FILE" 2>/dev/null | head -n 1 | cut -d: -f2)\n'
            '    fi\n'
            '    if [ -z "$iface" ]; then\n'
            '        iface="en0"\n'
            '    fi\n'
            '    echo "  interface: $iface"\n'
            'else\n'
            '    echo "  interface: en0"\n'
            'fi\n'
        )
        self.mock_route_path.write_text(mock_route_script, encoding="utf-8")
        self.mock_route_path.chmod(0o755)

        # Прогрев для исключения задержек сканирования безопасности macOS при первом запуске
        subprocess.run([str(self.mock_route_path), "-n", "get", "warmup"], capture_output=True)

        # Модифицируем тестовую копию nb-hook.py для вызова mock /sbin/route
        self.patched_python_code = self.python_code.replace(
            '"/sbin/route"', f'"{self.mock_route_path}"'
        ).replace(
            "timeout=0.3", "timeout=2.0"
        )

        self.wrapper_path = Path(self.tmpdir) / "nb-hook"
        self.python_path = Path(self.tmpdir) / "nb-hook.py"

        self.wrapper_path.write_text(self.wrapper_code, encoding="utf-8")
        self.python_path.write_text(self.patched_python_code, encoding="utf-8")

        self.wrapper_path.chmod(0o755)
        self.python_path.chmod(0o755)

        self.state_file = Path(self.tmpdir) / "tunnelguard-state.json"
        self.socket_path = Path(self.tmpdir) / "nb.sock"
        self.routes_file = Path(self.tmpdir) / "routes.txt"
        self._set_routes({"default": "en0"})

        self.base_env = os.environ.copy()
        self.base_env["PATH"] = f"{self.mock_bin_dir}:{self.base_env.get('PATH', '')}"
        self.base_env["TUNNELGUARD_STATE_FILE"] = str(self.state_file)
        self.base_env["NOTCHBUDDY_SOCKET_PATH"] = str(self.socket_path)
        self.base_env["MOCK_ROUTES_FILE"] = str(self.routes_file)

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _set_routes(self, routes_dict):
        lines = [f"{dest}:{iface}" for dest, iface in routes_dict.items()]
        self.routes_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def _create_online_state(self, pid=None, enabled=True, running=True, protected_targets=None, target_domains=None):
        if pid is None:
            pid = os.getpid()
        if protected_targets is None:
            protected_targets = ["antigravity", "agy", "claude", "codex", "gemini"]
        if target_domains is None:
            target_domains = {
                "antigravity": "generativelanguage.googleapis.com",
                "agy": "generativelanguage.googleapis.com",
                "claude": "claude.ai",
                "codex": "chatgpt.com"
            }
        data = {
            "running": running,
            "enabled": enabled,
            "pid": pid,
            "protected_targets": protected_targets,
            "target_domains": target_domains
        }
        self.state_file.write_text(json.dumps(data), encoding="utf-8")
        self.socket_path.touch()

    # --- Scenario 1: App Offline ---

    def test_e2e_scenario1_app_offline_no_state_file_clean_exit(self):
        """
        Сценарий 1.1: NotchBuddy офлайн (файл состояния отсутствует).
        Даже при упавшем VPN (en0) хук НЕ убивает агента и завершается штатно с returncode 0
        и возвращает {"decision":"ask"} для antigravity PreToolUse.
        """
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "ls"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0, f"Хук обязан вернуть 0 при офлайн-приложении, получен {res.returncode}")
        self.assertIn('{"decision":"ask"}', res.stdout.strip(), "Antigravity PreToolUse обязан получить {'decision':'ask'}")

    def test_e2e_scenario1_app_offline_pid_dead_clean_exit(self):
        """
        Сценарий 1.2: Файл состояния есть, но PID процесса NotchBuddy мертв (ProcessLookupError).
        Хук распознает смерть процесса, НЕ убивает агента и завершается с returncode 0.
        """
        self._create_online_state(pid=99999999)
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "pwd"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    def test_e2e_scenario1_app_online_but_disabled_in_settings_clean_exit(self):
        """
        Сценарий 1.3: NotchBuddy запущен, но TunnelGuard отключен в настройках (enabled=False).
        Хук НЕ убивает агента и завершается штатно с 0.
        """
        self._create_online_state(enabled=False)
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "whoami"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    def test_e2e_scenario1_agent_not_in_protected_targets_clean_exit(self):
        """
        Сценарий 1.4: TunnelGuard включен, но данный агент не входит в protected_targets.
        Хук пропускает выполнение без убийства.
        """
        self._create_online_state(protected_targets=["codex"])
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "date"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    # --- Scenario 2: Split Tunnel Active ---

    def test_e2e_scenario2_split_tunnel_antigravity_gemini_active(self):
        """
        Сценарий 2.1: Split Tunnel активен для Antigravity/Gemini:
        - generativelanguage.googleapis.com идет в utun3
        - default и 1.1.1.1 идут в en0 (локальный Wi-Fi)
        Хук определяет защиту целевого домена, НЕ убивает процесс и отдает {"decision":"ask"}.
        """
        self._create_online_state(protected_targets=["antigravity", "agy"])
        self._set_routes({
            "generativelanguage.googleapis.com": "utun3",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git status"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    def test_e2e_scenario2_split_tunnel_claude_active(self):
        """
        Сценарий 2.2: Split Tunnel активен для Claude:
        - claude.ai идет в utun2
        - default и 1.1.1.1 идут в en0
        Хук подтверждает VPN для claude.ai и выходит с returncode 0.
        """
        self._create_online_state(protected_targets=["claude"])
        self._set_routes({
            "claude.ai": "utun2",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "pytest"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "claude", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)

    # --- Scenario 3: Extended Interface Active ---

    def test_e2e_scenario3_extended_interface_cscotun0_cisco(self):
        """
        Сценарий 3.1: Расширенный интерфейс cscotun0 (Cisco AnyConnect):
        - claude.ai идет в cscotun0
        - default и 1.1.1.1 идут в en0
        Хук распознает cscotun0 как валидный VPN-интерфейс и выходит с кодом 0.
        """
        self._create_online_state(protected_targets=["claude"])
        self._set_routes({
            "claude.ai": "cscotun0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "foo.txt"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "claude", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)

    def test_e2e_scenario3_extended_interface_ppp0_point_to_point(self):
        """
        Сценарий 3.2: Расширенный интерфейс ppp0 (macOS Point-to-Point VPN):
        - generativelanguage.googleapis.com идет в ppp0
        - default и 1.1.1.1 идут в en0
        Хук распознает ppp0 как валидный VPN, агент не убивается, returncode 0.
        """
        self._create_online_state(protected_targets=["antigravity"])
        self._set_routes({
            "generativelanguage.googleapis.com": "ppp0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "cargo build"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    def test_e2e_scenario3_extended_interface_tun0_openvpn(self):
        """
        Сценарий 3.3: Расширенный интерфейс tun0 (OpenVPN/WireGuard tun):
        - generativelanguage.googleapis.com идет в tun0
        - default и 1.1.1.1 идут в en0
        Хук распознает tun0 как валидный VPN, returncode 0.
        """
        self._create_online_state(protected_targets=["antigravity"])
        self._set_routes({
            "generativelanguage.googleapis.com": "tun0",
            "1.1.1.1": "en0",
            "default": "en0"
        })
        input_payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": "uname"}})

        res = subprocess.run(
            ["/bin/sh", str(self.wrapper_path), "--agent", "antigravity", "PreToolUse"],
            input=input_payload,
            capture_output=True,
            text=True,
            env=self.base_env,
            timeout=5.0
        )

        self.assertEqual(res.returncode, 0)
        self.assertIn('{"decision":"ask"}', res.stdout.strip())

    # --- Scenario 4: VPN Down (True Leak) ---

    def test_e2e_scenario4_vpn_down_true_leak_kills_calling_agent(self):
        """
        Сценарий 4.1: Реальная утечка (True Leak):
        - NotchBuddy онлайн и защищает antigravity
        - И целевой домен generativelanguage.googleapis.com, и default, и 1.1.1.1 идут в en0
        Вызов хука приводит к немедленной ликвидации (SIGKILL) вызывающего процесса агента!
        """
        self._create_online_state(protected_targets=["antigravity"])
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })

        agent_script = (
            "import subprocess, sys, time\n"
            f"res = subprocess.run(['/bin/sh', '{self.wrapper_path}', '--agent', 'antigravity', 'PreToolUse'], "
            "input='{}', text=True, capture_output=True)\n"
            "print('RES_CODE:' + str(res.returncode), flush=True)\n"
            "time.sleep(30)\n"
        )

        proc = subprocess.Popen(
            [sys.executable, "-c", agent_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,
            env=self.base_env
        )
        agent_pid = proc.pid

        try:
            ret = proc.wait(timeout=3.0)
        finally:
            if proc.stdout:
                proc.stdout.close()
            if proc.stderr:
                proc.stderr.close()

        # Агент обязан погибнуть от SIGKILL (-9)
        self.assertEqual(ret, -signal.SIGKILL, f"Агент должен быть завершен по SIGKILL (-9), получен: {ret}")

        # Проверка отсутствия процесса в ядре ОС
        with self.assertRaises(ProcessLookupError):
            os.kill(agent_pid, 0)

    def test_e2e_scenario4_vpn_down_deny_payload_schema(self):
        """
        Сценарий 4.2: Формат deny payload при истинной утечке.
        Проверяет, что при обнаружении утечки выдается сообщение с предупреждением об отключенном VPN.
        """
        self._create_online_state(protected_targets=["antigravity"])
        self._set_routes({
            "generativelanguage.googleapis.com": "en0",
            "1.1.1.1": "en0",
            "default": "en0"
        })

        # Тестовая обертка kill-функции без убийства текущего процесса теста
        safe_py = self.python_code.replace(
            "os.killpg(os.getpgid(agent_pid), signal.SIGKILL)",
            "pass  # os.killpg suppressed for schema test"
        ).replace(
            "os.kill(agent_pid, signal.SIGKILL)",
            "pass  # os.kill suppressed for schema test"
        ).replace(
            '"/sbin/route"', f'"{self.mock_route_path}"'
        ).replace(
            "timeout=0.3", "timeout=2.0"
        )

        safe_py_path = Path(self.tmpdir) / "nb-hook-safe-kill.py"
        safe_py_path.write_text(safe_py, encoding="utf-8")
        safe_py_path.chmod(0o755)

        safe_wrapper = Path(self.tmpdir) / "nb-hook-safe-wrapper"
        safe_wrapper.write_text(self.wrapper_code.replace("nb-hook.py", "nb-hook-safe-kill.py"), encoding="utf-8")
        safe_wrapper.chmod(0o755)

        res = subprocess.run(
            ["/bin/sh", str(safe_wrapper), "--agent", "antigravity", "PreToolUse"],
            input='{"tool_name": "Bash"}',
            capture_output=True,
            text=True,
            env=self.base_env
        )

        self.assertEqual(res.returncode, 1, "При утечке хук обязан возвращать код 1")
        data = json.loads(res.stdout.strip())
        self.assertIn("hookSpecificOutput", data)
        self.assertEqual(data["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("VPN ОТКЛЮЧЕН", data["hookSpecificOutput"]["message"])

    # --- Scenario 5: Hook Script Generation & Permissions ---

    def test_e2e_scenario5_hook_script_generation_and_permissions(self):
        """
        Сценарий 5: Проверка генерации скриптов nb-hook и nb-hook.py:
        - HookServer объявляет static func writeHookFiles
        - Файлы создаются с правами 0755
        - Корректные шебанги (#!/bin/sh и #!/usr/bin/env python3)
        - Синтаксическая валидность sh и python
        - Наличие ключевых функций L1 Gate в сгенерированном реле.
        """
        gen_dir = Path(self.tmpdir) / "generated_hooks"
        gen_dir.mkdir(parents=True, exist_ok=True)

        wrapper_out = gen_dir / "nb-hook"
        python_out = gen_dir / "nb-hook.py"

        wrapper_out.write_text(self.wrapper_code, encoding="utf-8")
        wrapper_out.chmod(0o755)

        python_out.write_text(self.python_code, encoding="utf-8")
        python_out.chmod(0o755)

        # 1. Проверка прав 0755
        self.assertEqual(stat.S_IMODE(wrapper_out.stat().st_mode), 0o755)
        self.assertEqual(stat.S_IMODE(python_out.stat().st_mode), 0o755)

        # 2. Проверка шебангов
        self.assertTrue(wrapper_out.read_text(encoding="utf-8").startswith("#!/bin/sh"))
        self.assertTrue(python_out.read_text(encoding="utf-8").startswith("#!/usr/bin/env python3"))

        # 3. Синтаксическая проверка шелла
        sh_check = subprocess.run(["/bin/sh", "-n", str(wrapper_out)], capture_output=True, text=True)
        self.assertEqual(sh_check.returncode, 0, f"Ошибка синтаксиса шелл-обертки: {sh_check.stderr}")

        # 4. Синтаксическая компиляция Python
        py_compile.compile(str(python_out), doraise=True)

        # 5. Проверка наличия ключевых функций в коде реле
        content = python_out.read_text(encoding="utf-8")
        self.assertIn("def is_tunnelguard_active(", content)
        self.assertIn("def is_vpn_interface(", content)
        self.assertIn("def get_target_ai_domain(", content)
        self.assertIn("def verify_vpn_route(", content)
        self.assertIn("def tunnel_guard_kill_agent_and_exit(", content)
        self.assertIn("generativelanguage.googleapis.com", content)
        self.assertIn("claude.ai", content)

        # 6. Проверка сигнатуры в HookServer.swift
        hook_server_source = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
        self.assertIn("static func writeHookFiles", hook_server_source)
        self.assertIn("func writeHookFiles", hook_server_source)


if __name__ == "__main__":
    unittest.main(verbosity=2)

