import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verification", Path(__file__).with_name("verification.py"))
verification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verification)


class VerificationTests(unittest.TestCase):
    def test_shell_entry_point_with_real_child_process(self):
        root = Path(__file__).resolve().parent.parent
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            (target / "scripts").mkdir()
            shutil.copy(root / "check.sh", target / "check.sh")
            shutil.copy(root / "scripts/verification.py", target / "scripts/verification.py")
            (target / "scripts/test_verification.py").write_text("import unittest\nclass Smoke(unittest.TestCase):\n    def test_one(self):\n        self.assertTrue(True)\n")
            swift = target / "swift"
            swift.write_text("""#!/bin/bash
if [ "$1" = test ]; then
    echo "Test Case 'Domain.testOne' passed (0 seconds)."
    echo "Test Case 'ScreenshotTests.testScreen' skipped (0 seconds)."
fi
""")
            swift.chmod(0o755)
            process = subprocess.run(["bash", "check.sh"], cwd=target, capture_output=True, text=True,
                                     env=dict(os.environ, PATH=f"{target}:{os.environ['PATH']}"))
            self.assertEqual(process.returncode, 0, process.stderr)
            self.assertIn("check passed: 1 behavior tests, 1 skipped", process.stdout)
            result = json.loads((target / ".build/check.json").read_text())
            self.assertEqual(result["stages"]["tests"]["test_counts"]["behavior"]["passed"], 1)
            self.assertEqual(result["test_counts"]["screenshots"]["skipped"], 1)
            swift.write_text('#!/bin/bash\nkill -TERM "$PPID"\nexec sleep 10\n')
            process = subprocess.run(["bash", "check.sh"], cwd=target, capture_output=True, text=True,
                                     env=dict(os.environ, PATH=f"{target}:{os.environ['PATH']}"), timeout=5)
            self.assertEqual(process.returncode, 130)
            result = json.loads((target / ".build/check.json").read_text())
            self.assertEqual(result["stages"]["build"]["status"], "failed")
            self.assertEqual(result["stages"]["tests"]["status"], "skipped")

    def run_script(self, kind, responses, args=(), baselines=(), script_result=(0, "Ran 19 tests in 0.001s\nOK\n")):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            os.chdir(directory)
            try:
                for name in baselines:
                    target = Path(".build/shots") / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.touch()

                def command(argv, stdout, stderr, env=None):
                    if "unittest" in argv:
                        code, text = script_result
                        stdout.write(text)
                        return subprocess.CompletedProcess(argv, code)
                    response = responses.pop(0)
                    if isinstance(response, BaseException):
                        raise response
                    code, text = response
                    stdout.write(text)
                    had_baseline = bool(env and (Path(env["SENDPOINT_SHOTS_DIR"]) / f"screen-{env['SENDPOINT_SHOTS_APPEARANCE']}.png").exists())
                    if env and code == 0:
                        (Path(env["SENDPOINT_SHOTS_DIR"]) / f"screen-{env['SENDPOINT_SHOTS_APPEARANCE']}.png").touch()
                    if env and "Test Case" in text:
                        name = f"screen-{env['SENDPOINT_SHOTS_APPEARANCE']}.png"
                        comparison = "failed" if "snapshot difference" in text else "passed" if had_baseline and env["SENDPOINT_SHOTS_RECORD"] == "missing" else "recorded"
                        stdout.write("SENDPOINT_SCREEN " + json.dumps(dict(name=name, rendering="passed", comparison=comparison)) + "\n")
                    if env and "snapshot difference" in text:
                        (Path(env["SNAPSHOT_ARTIFACTS"]) / "difference.png").touch()
                    return subprocess.CompletedProcess(argv, code)

                with patch.object(verification.subprocess, "run", side_effect=command), contextlib.redirect_stdout(io.StringIO()):
                    code = verification.run(kind, list(args))
                result = json.loads(Path(f".build/{kind}.json").read_text())
                self.assertFalse(responses)
                self.assertEqual(code, result["exit_code"])
                return result
            finally:
                os.chdir(original)

    def test_counts_do_not_double_count_nested_suites(self):
        text = """Test Case '-[SendpointTests.ControllerTests testPass]' passed (0.001 seconds).
Test Case '-[SendpointTests.ControllerTests testSkip]' skipped (0.001 seconds).
Test Case '-[SendpointDomainTests.MachineTests testFail]' failed (0.001 seconds).
Test Case '-[SendpointScreenshotTests.ScreenshotTests testScreen]' skipped (0.001 seconds).
Test Suite 'ControllerTests' passed
Executed 2 tests, with 1 test skipped and 0 failures
Test Suite 'All tests' failed
Executed 4 tests, with 2 tests skipped and 1 failure
✔ Test run with 0 tests passed after 0.001 seconds.
"""
        counts = verification.test_counts(text)
        self.assertEqual(counts["behavior"], dict(passed=1, failed=1, skipped=1, executed=2, total=3))
        self.assertEqual(counts["screenshots"]["skipped"], 1)

    def test_build_failure_skips_tests(self):
        result = self.run_script("check", [(2, "error: build failed\n")])
        self.assertEqual(result["stages"]["build"]["status"], "failed")
        self.assertEqual(result["stages"]["tests"]["status"], "skipped")

    def test_script_test_failure_skips_build_and_swift_tests(self):
        result = self.run_script("check", [], script_result=(1, "Ran 1 test in 0.001s\nFAILED (failures=1)\n"))
        self.assertEqual(result["stages"]["verification_scripts"]["test_counts"]["failures"], 1)
        self.assertEqual(result["stages"]["build"]["status"], "skipped")
        self.assertEqual(result["stages"]["tests"]["status"], "skipped")

    def test_test_failure_is_recorded(self):
        result = self.run_script("check", [(0, ""), (1, "Test Case 'Domain.testFail' failed (0 seconds).\n")])
        self.assertEqual(result["test_counts"]["behavior"]["failed"], 1)
        self.assertEqual(result["status"], "failed")

    def test_missing_swift_records_failure(self):
        result = self.run_script("check", [FileNotFoundError("swift unavailable")])
        self.assertEqual(result["exit_code"], 127)
        self.assertEqual(result["stages"]["tests"]["status"], "skipped")

    def test_interrupt_records_failure(self):
        result = self.run_script("check", [KeyboardInterrupt()])
        self.assertEqual(result["exit_code"], 130)
        self.assertEqual(result["stages"]["build"]["status"], "failed")

    def test_zero_behavior_tests_is_incomplete(self):
        result = self.run_script("check", [(0, ""), (0, "")])
        self.assertEqual(result["stages"]["tests"]["status"], "incomplete")
        self.assertEqual(result["status"], "failed")

    def test_install_failure_and_launch_failure_are_distinct(self):
        result = self.run_script("ship", [(0, ""), (1, "==> Installing to /Applications/Sendpoint.app\n")])
        self.assertEqual(result["stages"]["install"]["status"], "failed")
        self.assertEqual(result["stages"]["launch"]["status"], "skipped")
        result = self.run_script("ship", [(0, ""), (1, "==> Launching\nLaunch failed\n")])
        self.assertEqual(result["stages"]["install"]["status"], "passed")
        self.assertEqual(result["stages"]["launch"]["status"], "failed")

    def test_ship_build_failure_skips_install_and_launch(self):
        result = self.run_script("ship", [(1, "error: build failed\n")])
        self.assertEqual(result["stages"]["install"]["status"], "skipped")
        self.assertEqual(result["stages"]["launch"]["status"], "skipped")

    def test_ship_success(self):
        result = self.run_script("ship", [(0, ""), (0, "==> Launching\n")])
        self.assertEqual(result["stages"]["launch"]["status"], "passed")

    def test_ship_zero_exit_without_install_or_launch_evidence_is_incomplete(self):
        result = self.run_script("ship", [(0, ""), (0, "")])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["stages"]["install"]["status"], "incomplete")
        self.assertEqual(result["stages"]["launch"]["status"], "skipped")

    def screenshot_responses(self):
        return [(0, "Test Case 'ScreenshotTests.testScreen' passed (0 seconds).\n") for _ in range(2)]

    def test_recording_is_not_comparison(self):
        result = self.run_script("shots", self.screenshot_responses())
        self.assertEqual(result["stages"]["rendering"]["status"], "passed")
        self.assertEqual(result["stages"]["comparison"]["status"], "skipped")

    def test_missing_baselines_do_not_pass_comparison(self):
        result = self.run_script("shots", self.screenshot_responses(), ["--diff"])
        self.assertEqual(result["stages"]["comparison"]["status"], "incomplete")
        self.assertEqual(result["stages"]["comparison"]["new_baselines"], 2)
        self.assertEqual(result["status"], "failed")

    def test_existing_baselines_pass_comparison(self):
        result = self.run_script("shots", self.screenshot_responses(), ["--diff"],
                                 ["screen-light.png", "screen-dark.png"])
        self.assertEqual(result["stages"]["comparison"]["status"], "passed")

    def test_successful_command_with_no_tests_is_not_rendering(self):
        result = self.run_script("shots", [(0, ""), (0, "")])
        self.assertEqual(result["stages"]["rendering"]["status"], "incomplete")
        self.assertEqual(result["status"], "failed")

    def test_each_appearance_needs_tests(self):
        result = self.run_script("shots", [self.screenshot_responses()[0], (0, "")])
        self.assertEqual(result["stages"]["rendering"]["status"], "incomplete")

    def test_failed_light_run_still_attempts_dark(self):
        result = self.run_script("shots", [(1, "error: rendering failed\n"), self.screenshot_responses()[0]])
        self.assertEqual(result["stages"]["light"]["status"], "failed")
        self.assertEqual(result["stages"]["dark"]["status"], "passed")
        self.assertEqual(result["status"], "failed")

    def test_snapshot_mismatch_records_comparison_failure(self):
        result = self.run_script("shots", [(1, "Test Case 'ScreenshotTests.testScreen' failed (0 seconds).\nsnapshot difference\n"), self.screenshot_responses()[0]],
                                 ["--diff"], ["screen-light.png", "screen-dark.png"])
        self.assertEqual(result["stages"]["comparison"]["status"], "failed")
        self.assertEqual(result["stages"]["rendering"]["status"], "passed")

    def test_invalid_arguments_record_failure_and_skipped_stages(self):
        result = self.run_script("shots", [], ["--invalid"])
        self.assertIn("usage", result["error"])
        self.assertTrue(all(stage["status"] == "skipped" for stage in result["stages"].values()))


if __name__ == "__main__":
    unittest.main()
