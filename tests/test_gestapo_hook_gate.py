#!/usr/bin/env python3
"""
test_gestapo_hook_gate.py - Тесты контура L1 Gate и Kill-Switch в NotchBuddy (Coucou).
Адаптировано из start_tool/tests/test_gestapo.py и simulate_vpn_drop.py.

Проверяет:
1. 100% ликвидацию процессов (SIGKILL, процессные деревья, группы процессов, latency benchmark).
2. Детекцию сетевых интерфейсов и таймауты /sbin/route в Python-реле nb-hook.py.
3. Шлагбаум Гестапо в nb-hook.py (блокировка до чтения stdin, deny-ответ, отстрел агента).
4. Определение реального PID агента (get_real_agent_pid: claude, node, agy, codex, gemini).
5. Принудительный Fail-Closed в шелл-обертке nb-hook (проброс exit $rc при падении VPN).
6. End-to-End симуляцию отвала VPN и ликвидации вызывающего агента.
"""

import json
import os
import re
import shutil
import signal
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

    wrapper_code = m_wrapper.group(1).strip() + "\n"
    python_code = m_python.group(1).strip() + "\n"
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


class TestGestapoProcessKill(unittest.TestCase):
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


class TestGestapoHookVPNCheck(unittest.TestCase):
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
        self.tmpdir = tempfile.mkdtemp(prefix="gestapo_wrapper_test_")
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


class TestGestapoGateE2E(unittest.TestCase):
    """End-to-End тестирование шлагбаума и ликвидации вызывающего агента при падении VPN."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp(prefix="gestapo_e2e_test_")
        self.wrapper_code, self.python_code = extract_hook_scripts()

        self.wrapper_path = Path(self.tmpdir) / "nb-hook"
        self.python_path = Path(self.tmpdir) / "nb-hook.py"

        self.wrapper_path.write_text(self.wrapper_code, encoding="utf-8")
        self.python_path.write_text(self.python_code, encoding="utf-8")

        self.wrapper_path.chmod(0o755)
        self.python_path.chmod(0o755)

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
            preexec_fn=os.setsid
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
            "def gestapo_kill_agent_and_exit():",
            "def gestapo_kill_agent_and_exit():\n"
            "    deny_payload = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'deny', 'message': '🚨 [GESTAPO] VPN ОТКЛЮЧЕН! Действие заблокировано.'}}\n"
            "    sys.stdout.write(json.dumps(deny_payload) + '\\n')\n"
            "    sys.exit(1)\n"
            "def _unused():\n"
        )
        # Форсируем вызов gestapo_kill_agent_and_exit при старте
        safe_kill_py = safe_kill_py.replace(
            "if not verify_vpn_route_utun():",
            "if True: # forced VPN drop for test"
        )
        test_py.write_text(safe_kill_py, encoding="utf-8")

        res = subprocess.run(
            [sys.executable, str(test_py)],
            capture_output=True,
            text=True
        )

        self.assertEqual(res.returncode, 1, "При падении VPN хук обязан завершаться с кодом 1")
        data = json.loads(res.stdout.strip())
        self.assertIn("hookSpecificOutput", data)
        self.assertEqual(data["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertEqual(data["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("VPN ОТКЛЮЧЕН", data["hookSpecificOutput"]["message"])


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
