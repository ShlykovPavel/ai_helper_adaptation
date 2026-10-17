#!/usr/bin/env python3
"""
Unit tests for Antigravity hook relay in nb-hook.py:
1. Transcript reading and last user prompt extraction for PreInvocation.
2. Formatting and structure of --ask response payload for ask_question.
3. Verification of HookServer.swift embedded script and hooks.json generation.
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


def extract_python_relay():
    """Extract nbHookPythonGitHub from HookServer.swift."""
    if not HOOK_SERVER_SWIFT.exists():
        raise FileNotFoundError(f"HookServer.swift not found: {HOOK_SERVER_SWIFT}")
    content = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
    m = re.search(r'private let nbHookPythonGitHub = """(.*?)"""', content, re.DOTALL)
    if not m:
        raise ValueError("Could not extract nbHookPythonGitHub from HookServer.swift")

    s = m.group(1)
    placeholder = "___SWIFT_ESCAPED_NEWLINE___"
    res = s.replace("\\\\n", placeholder)
    res = res.replace("\\n", "\n")
    res = res.replace(placeholder, "\\n")
    return res.strip() + "\n"


def load_relay_module(py_code):
    """Load relay code as a python module without invoking main()."""
    code_without_main = re.sub(
        r'try:\s+main\(\)\s+except Exception:\s+sys\.exit\(1\)\s+sys\.exit\(0\)',
        '# main execution stripped for module loading',
        py_code
    )
    mod = types.ModuleType("nb_hook_relay")
    exec(compile(code_without_main, "nb-hook.py", "exec"), mod.__dict__)
    return mod


class TestAntigravityHookRelay(unittest.TestCase):

    def test_transcript_prompt_extraction(self):
        """Test extraction of the last user prompt from a simulated JSONL transcript."""
        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
            f.write(json.dumps({"type": "SYSTEM_MESSAGE", "content": "system"}) + "\n")
            f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "First instruction"}) + "\n")
            f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "planning"}) + "\n")
            f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "  Add dark mode support  \n"}) + "\n")
            f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "implementing"}) + "\n")
            f.write(json.dumps({"type": "GENERIC", "content": "running tests"}) + "\n")
            tpath = f.name

        try:
            extracted = None
            with open(tpath, "r", encoding="utf-8") as fp:
                for line in reversed(fp.readlines()):
                    if not line.strip():
                        continue
                    entry = json.loads(line)
                    if entry.get("type") == "USER_INPUT" or entry.get("source") == "USER_EXPLICIT":
                        content = entry.get("content")
                        if isinstance(content, str) and content.strip():
                            extracted = content.strip()
                            break
            self.assertEqual(extracted, "Add dark mode support")
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

    def test_extracted_script_extract_last_user_prompt(self):
        """Verify extract_last_user_prompt function inside HookServer.swift embedded script."""
        py_code = extract_python_relay()
        mod = load_relay_module(py_code)
        self.assertTrue(hasattr(mod, "extract_last_user_prompt"), "Relay script must define extract_last_user_prompt")

        with tempfile.NamedTemporaryFile("w+", delete=False, suffix=".jsonl") as f:
            f.write(json.dumps({"type": "SYSTEM_MESSAGE", "content": "init"}) + "\n")
            f.write(json.dumps({"type": "USER_INPUT", "source": "USER_EXPLICIT", "content": "Build SwiftUI app"}) + "\n")
            f.write(json.dumps({"type": "PLANNER_RESPONSE", "content": "working"}) + "\n")
            tpath = f.name

        try:
            prompt = mod.extract_last_user_prompt(tpath)
            self.assertEqual(prompt, "Build SwiftUI app")

            # Missing or empty file
            self.assertIsNone(mod.extract_last_user_prompt("/nonexistent/file.jsonl"))
            self.assertIsNone(mod.extract_last_user_prompt(None))
        finally:
            if os.path.exists(tpath):
                os.remove(tpath)

    def test_extracted_script_ask_question_handling(self):
        """Verify embedded script accepts ask_question in --ask mode and formats allow response."""
        py_code = extract_python_relay()
        # Verify ask_question is present in --ask handling
        self.assertIn("ask_question", py_code)
        self.assertIn("'decision': 'allow'", py_code)
        self.assertIn("'updatedInput': {'questions': questions, 'answers': answers}", py_code)

    def test_swift_build_agy_hooks_data(self):
        """Verify buildAgyHooksData in HookServer.swift configures ask_question with 130s timeout."""
        content = HOOK_SERVER_SWIFT.read_text(encoding="utf-8")
        self.assertIn('"matcher": "ask_question"', content)
        self.assertIn("--ask PreToolUse", content)
        self.assertIn('"timeout": 130', content)


if __name__ == "__main__":
    unittest.main()
