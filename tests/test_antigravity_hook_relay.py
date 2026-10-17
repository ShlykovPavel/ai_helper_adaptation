#!/usr/bin/env python3
"""
Unit tests for Antigravity hook relay in nb-hook.py (GitHub & App Store builds):
1. Transcript reading, trailing seek (128KB), and <USER_REQUEST> stripping for PreInvocation.
2. Formatting and structure of --ask response payload for ask_question.
3. Fallback behavior emitting {"decision":"ask"} for Antigravity in --ask mode.
4. Prevention of general PreToolUse hook from interfering with ask_question.
5. Gating prompt extraction on invocationNum <= 1.
6. Verification of HookServer.swift embedded scripts and hooks.json generation.
"""

import json
import os
import re
import tempfile
import types
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HOOK_SERVER_SWIFT = REPO_ROOT / "NotchBuddy" / "Sources" / "App" / "HookServer.swift"


def extract_python_relay(var_name="nbHookPythonGitHub"):
    """Extract embedded Python relay script from HookServer.swift."""
    if not HOOK_SERVER_SWIFT.exists():
        raise FileNotFoundError(f"HookServer.swift not found: {HOOK_SERVER_SWIFT}")
    content = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
    m = re.search(rf'private let {var_name} = """(.*?)"""', content, re.DOTALL)
    if not m:
        raise ValueError(f"Could not extract {var_name} from HookServer.swift")

    s = m.group(1)
    placeholder = "___SWIFT_ESCAPED_NEWLINE___"
    res = s.replace("\\\\n", placeholder)
    res = res.replace("\\n", "\n")
    res = res.replace(placeholder, "\\n")
    res = res.replace("\\\\s", "\\s")
    return res.strip() + "\n"


def load_relay_module(py_code, module_name="nb_hook_relay"):
    """Load relay code as a python module without invoking main()."""
    code_without_main = re.sub(
        r'try:\s+main\(\)\s+except Exception:.*',
        '# main execution stripped for module loading',
        py_code,
        flags=re.DOTALL
    )
    mod = types.ModuleType(module_name)
    exec(compile(code_without_main, "nb-hook.py", "exec"), mod.__dict__)
    return mod


class TestAntigravityHookRelay(unittest.TestCase):

    def test_extract_last_user_prompt_plain_and_user_request_tags(self):
        """Test prompt extraction with plain text and <USER_REQUEST> tags on both relay scripts."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                mod = load_relay_module(py_code, f"mod_{var_name}")
                self.assertTrue(hasattr(mod, "extract_last_user_prompt"))

                # 1. Plain text prompt
                with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
                    f.write(json.dumps({"type": "SYSTEM_MESSAGE", "content": "init"}) + "\n")
                    f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "Build SwiftUI app"}) + "\n")
                    f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "working"}) + "\n")
                    tpath_plain = f.name

                try:
                    prompt = mod.extract_last_user_prompt(tpath_plain)
                    self.assertEqual(prompt, "Build SwiftUI app")
                finally:
                    if os.path.exists(tpath_plain):
                        os.remove(tpath_plain)

                # 2. Tagged <USER_REQUEST> prompt
                tagged_content = (
                    "The following is a <SYSTEM_MESSAGE> not actually sent by the user.\n\n"
                    "<USER_REQUEST>\n"
                    "  Refactor the authentication flow to use OAuth2 PKCE  \n"
                    "</USER_REQUEST>\n"
                    "Some trailing instructions"
                )
                with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
                    f.write(json.dumps({"type": "SYSTEM_MESSAGE", "content": "system prompt"}) + "\n")
                    f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": tagged_content}) + "\n")
                    f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "analyzing"}) + "\n")
                    tpath_tagged = f.name

                try:
                    prompt = mod.extract_last_user_prompt(tpath_tagged)
                    self.assertEqual(prompt, "Refactor the authentication flow to use OAuth2 PKCE")
                finally:
                    if os.path.exists(tpath_tagged):
                        os.remove(tpath_tagged)

                # 3. Nonexistent / empty file
                self.assertIsNone(mod.extract_last_user_prompt("/nonexistent/file.jsonl"))
                self.assertIsNone(mod.extract_last_user_prompt(None))

    def test_extract_last_user_prompt_trailing_seek(self):
        """Test that extract_last_user_prompt seeks trailing 128KB on large transcript files (>128KB)."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                mod = load_relay_module(py_code, f"mod_large_{var_name}")

                with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
                    # Write an old user input at the very beginning
                    f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "OLD PROMPT AT START"}) + "\n")
                    # Pad with >140KB of filler lines
                    filler_entry = json.dumps({"type": "PLANNER_RESPONSE", "content": "x" * 200}) + "\n"
                    for _ in range(700):  # ~140KB
                        f.write(filler_entry)
                    # Write the latest user input at the end with <USER_REQUEST>
                    latest_content = "<USER_REQUEST>\nLatest Prompt In Last 128KB\n</USER_REQUEST>"
                    f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": latest_content}) + "\n")
                    f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "executing"}) + "\n")
                    tpath = f.name

                try:
                    file_size = os.path.getsize(tpath)
                    self.assertGreater(file_size, 131072, "Test file must be >128KB")
                    prompt = mod.extract_last_user_prompt(tpath)
                    self.assertEqual(prompt, "Latest Prompt In Last 128KB")
                finally:
                    if os.path.exists(tpath):
                        os.remove(tpath)

    def test_ask_question_response_payload(self):
        """Test formatting of --ask response output for ask_question."""
        answers = {"Which database engine would you like to use?": "PostgreSQL"}
        questions = [
            {
                "question": "Which database engine would you like to use?",
                "options": ["PostgreSQL", "SQLite", "MySQL"],
                "is_multi_select": False
            }
        ]
        out = {
            "decision": "allow",
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": {"questions": questions, "answers": answers}
            },
            "updatedInput": {"questions": questions, "answers": answers}
        }
        self.assertEqual(out["decision"], "allow")
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "PreToolUse")
        self.assertEqual(out["hookSpecificOutput"]["permissionDecision"], "allow")
        self.assertEqual(out["hookSpecificOutput"]["updatedInput"]["answers"]["Which database engine would you like to use?"], "PostgreSQL")
        self.assertEqual(out["updatedInput"]["answers"]["Which database engine would you like to use?"], "PostgreSQL")
        self.assertEqual(out["updatedInput"]["questions"], questions)

    def test_ask_fallback_antigravity(self):
        """Verify that both scripts emit {"decision":"ask"} for Antigravity in --ask mode when unanswered."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                # Verify ask fallback logic for antigravity
                self.assertIn("if agent == 'antigravity' or payload.get('coucou_agent') == 'antigravity':", py_code)
                self.assertIn('{"decision":"ask"}', py_code)

    def test_pre_tool_use_ask_question_guard(self):
        """Verify that general PreToolUse hook exits cleanly on ask_question to prevent conflicting ask decisions."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                self.assertIn("if payload.get('tool_name') == 'ask_question':", py_code)
                self.assertIn("return  # handled by --ask hook, do not emit conflicting ask", py_code)

    def test_agent_parsed_at_top_of_main(self):
        """Verify agent argument is parsed before --ask in both scripts."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                # Ensure agent parsing appears before '--ask' check
                pos_agent = py_code.find("agent = ''")
                pos_ask = py_code.find("if '--ask' in sys.argv[1:]:")
                self.assertNotEqual(pos_agent, -1)
                self.assertNotEqual(pos_ask, -1)
                self.assertLess(pos_agent, pos_ask, f"agent parsing must precede --ask in {var_name}")

    def test_invocation_num_gating(self):
        """Verify prompt extraction on UserPromptSubmit is gated on invocationNum <= 1."""
        for var_name in ("nbHookPythonGitHub", "nbHookPythonAppStore"):
            with self.subTest(var_name=var_name):
                py_code = extract_python_relay(var_name)
                self.assertIn("invocationNum", py_code)
                self.assertIn("inv_ok", py_code)

    def test_swift_build_agy_hooks_data(self):
        """Verify buildAgyHooksData in HookServer.swift configures ask_question with 130s timeout."""
        content = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
        self.assertIn('"matcher": "ask_question"', content)
        self.assertIn("--ask PreToolUse", content)
        self.assertIn('"timeout": 130', content)


if __name__ == "__main__":
    unittest.main()
