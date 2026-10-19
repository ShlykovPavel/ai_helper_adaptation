"""Exercise the shipped relay against a local notch socket, without running Codex."""
import io
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

from test_antigravity_hook_relay import extract_python_relay, load_relay_module


class CodexQuestionRelayTests(unittest.TestCase):
    def relay(self, payload, response=None, connected=True):
        module = load_relay_module(extract_python_relay(), "codex_relay")
        received = []
        with tempfile.TemporaryDirectory(prefix="cq-", dir="/tmp") as folder:
            path = folder + "/nb.sock"
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            if connected:
                server.bind(path)
                server.listen(1)
                server.settimeout(2)

                def serve():
                    try:
                        client, _ = server.accept()
                        with client:
                            client.settimeout(2)
                            data = b""
                            while b"\n" not in data:
                                chunk = client.recv(4096)
                                if not chunk:
                                    break
                                data += chunk
                            received.append(json.loads(data))
                            if response is not None:
                                try:
                                    client.sendall((json.dumps(response) + "\n").encode())
                                except BrokenPipeError:
                                    pass
                    except socket.timeout:
                        pass

                thread = threading.Thread(target=serve)
                thread.start()
            stdin = io.TextIOWrapper(io.BytesIO(json.dumps(payload).encode()))
            stdout = io.StringIO()
            with patch.object(module, "is_tunnelguard_active", return_value=False), \
                 patch.dict(os.environ, {"NOTCHBUDDY_SOCKET_PATH": path}), \
                 patch.object(sys, "argv", ["nb-hook.py", "--agent", "codex"]), \
                 patch.object(sys, "stdin", stdin), patch.object(sys, "stdout", stdout):
                try:
                    module.main()
                except SystemExit as exc:
                    self.assertEqual(exc.code, 0)
            if connected:
                thread.join(3)
            server.close()
        return received, stdout.getvalue()

    def test_sync_question_answer_is_delivered_without_rewriting_codex_arguments(self):
        payload = {"hook_event_name": "PreToolUse", "session_id": "codex-session",
                   "tool_name": "request_user_input", "tool_input": {"questions": [
                       {"id": "db", "question": "Which database?", "header": "DB", "options": [
                           {"label": "SQLite", "description": "Local"}, {"label": "Postgres", "description": "Server"}]}]}}
        received, output = self.relay(payload, {"permissionDecision": "answer", "answers": {"db": "SQLite"}})
        self.assertEqual(received[0].get("coucou_kind"), "ask_user_question")
        result = json.loads(output)["hookSpecificOutput"]
        self.assertEqual(result["hookEventName"], "PreToolUse")
        self.assertEqual(result["permissionDecision"], "deny")
        self.assertIn('"db": "SQLite"', result["permissionDecisionReason"])
        self.assertNotIn("updatedInput", result)

    def test_async_free_text_question_is_forwarded(self):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "request_user_input_async",
                   "tool_input": {"questions": [{"title": "What happened?"}]}}
        received, output = self.relay(payload, {"permissionDecision": "answer", "answers": {"What happened?": "A blank card"}})
        self.assertEqual(received[0].get("coucou_kind"), "ask_user_question")
        self.assertIn("A blank card", json.loads(output)["hookSpecificOutput"]["permissionDecisionReason"])

    def test_reply_in_codex_preserves_native_prompt(self):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "request_user_input",
                   "tool_input": {"questions": [{"id": "db", "question": "Choose"}]}}
        _, output = self.relay(payload, {"permissionDecision": "ask"})
        self.assertEqual(output, "")

    def test_app_offline_preserves_native_prompt(self):
        payload = {"hook_event_name": "PreToolUse", "tool_name": "request_user_input_async",
                   "tool_input": {"questions": [{"title": "Choose"}]}}
        _, output = self.relay(payload, connected=False)
        self.assertEqual(output, "")

    def test_completed_question_is_not_asked_again(self):
        payload = {"hook_event_name": "PostToolUse", "tool_name": "request_user_input",
                   "tool_input": {"questions": [{"id": "db", "question": "Choose"}]}}
        received, output = self.relay(payload)
        self.assertNotIn("coucou_kind", received[0])
        self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
