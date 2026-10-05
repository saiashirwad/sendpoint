#!/usr/bin/env python3
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys


def test_counts(text):
    groups = {name: dict(passed=0, failed=0, skipped=0) for name in ("behavior", "screenshots")}
    for name, outcome in re.findall(r"^Test Case '([^']+)' (passed|failed|skipped) \(", text, re.MULTILINE):
        group = "screenshots" if "ScreenshotTests" in name else "behavior"
        groups[group][outcome] += 1
    for counts in groups.values():
        counts["executed"] = counts["passed"] + counts["failed"]
        counts["total"] = counts["executed"] + counts["skipped"]
    return groups


def skipped(reason="Earlier stage did not complete"):
    return {"status": "skipped", "reason": reason}


def screenshot_records(text):
    return [json.loads(line.removeprefix("SENDPOINT_SCREEN "))
            for line in text.splitlines() if line.startswith("SENDPOINT_SCREEN ")]


def unittest_counts(text):
    total = re.search(r"^Ran (\d+) tests? in", text, re.MULTILINE)
    counts = {name: int(value) for name, value in re.findall(r"(failures|errors|skipped)=(\d+)", text)}
    return {"total": int(total[1]) if total else 0,
            **{name: counts.get(name, 0) for name in ("failures", "errors", "skipped")}}


def install_results(text, code):
    launched = "==> Launching\n" in text
    return {
        "install": {"status": "passed" if launched else "failed" if code else "incomplete", "exit_code": 0 if launched else code},
        "launch": {"status": "passed" if code == 0 else "failed", "exit_code": code} if launched else skipped(),
    }


def run(kind, args):
    build = Path(".build")
    build.mkdir(exist_ok=True)
    log_path = build / f"{kind}.log"
    result_path = build / f"{kind}.json"
    names = {"check": ["verification_scripts", "build", "tests"], "shots": ["light", "dark", "rendering", "comparison"],
             "ship": ["build_and_assemble", "install", "launch"]}[kind]
    result = {"schema_version": 1, "command": kind, "status": "failed", "exit_code": 1,
              "log": str(log_path), "stages": {name: skipped() for name in names}}
    status = 1
    shots = build / "shots"
    diffs = build / "shots-diff"

    with log_path.open("w") as log:
        def stage(name, command, env=None):
            result["stages"][name] = {"status": "running"}
            offset = log.tell()
            try:
                code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env).returncode
                if code < 0:
                    code = 128 - code
            except OSError as error:
                log.write(f"error: {error}\n")
                code = 127
            log.flush()
            result["stages"][name] = {"status": "passed" if code == 0 else "failed", "exit_code": code}
            if command[:2] == ["swift", "test"] or name == "verification_scripts":
                with log_path.open() as output:
                    output.seek(offset)
                    text = output.read()
                    result["stages"][name]["test_counts"] = unittest_counts(text) if name == "verification_scripts" else test_counts(text)
                    if name in ("light", "dark"):
                        result["stages"][name]["screens"] = screenshot_records(text)
            return code

        try:
            if (kind == "check" and args) or (kind == "shots" and args not in ([], ["--diff"])):
                raise ValueError(f"usage: ./{kind}.sh" + (" [--diff]" if kind == "shots" else ""))
            if kind == "check":
                status = stage("verification_scripts", [sys.executable, "-m", "unittest", "discover", "-s", "scripts", "-p", "test_*.py"])
                if status == 0 and result["stages"]["verification_scripts"]["test_counts"]["total"] == 0:
                    result["stages"]["verification_scripts"].update(status="incomplete", reason="No script tests observed")
                    status = 1
                if status == 0:
                    status = stage("build", ["swift", "build"])
                if status == 0:
                    status = stage("tests", ["swift", "test"])
                    counts = result["stages"]["tests"]["test_counts"]["behavior"]
                    if status == 0 and (counts["executed"] == 0 or counts["failed"]):
                        result["stages"]["tests"].update(status="incomplete", reason="No passing behavior test run observed")
                        status = 1
            elif kind == "ship":
                status = stage("build_and_assemble", ["./build.sh", *args])
                if status == 0:
                    status = stage("install", ["./install.sh"])
                    result["stages"].update(install_results(log_path.read_text(), status))
                    if status == 0 and result["stages"]["launch"]["status"] != "passed":
                        status = 1
            else:
                compare = args == ["--diff"]
                before = set(shots.glob("*.png")) if compare else set()
                if not compare and shots.exists():
                    shutil.rmtree(shots)
                if diffs.exists():
                    shutil.rmtree(diffs)
                shots.mkdir(parents=True, exist_ok=True)
                diffs.mkdir(parents=True, exist_ok=True)
                status = 0
                for appearance in ("light", "dark"):
                    env = dict(os.environ, SENDPOINT_SHOTS_DIR=str(shots.resolve()),
                               SENDPOINT_SHOTS_APPEARANCE=appearance,
                               SENDPOINT_SHOTS_RECORD="missing" if compare else "all",
                               SNAPSHOT_ARTIFACTS=str(diffs.resolve()))
                    code = stage(appearance, ["swift", "test", "--filter", "SendpointScreenshotTests"], env)
                    status = status or code
                after = set(shots.glob("*.png"))
                counts = test_counts(log_path.read_text())["screenshots"]
                records = screenshot_records(log_path.read_text())
                rendered_names = {shots / record["name"] for record in records if record["rendering"] == "passed"}
                rendered = bool(rendered_names) and rendered_names <= after and all(
                    result["stages"][appearance]["test_counts"]["screenshots"]["executed"] > 0
                    and result["stages"][appearance]["test_counts"]["screenshots"]["skipped"] == 0
                    and result["stages"][appearance]["screens"]
                    for appearance in ("light", "dark"))
                rendered = rendered and (before <= rendered_names if compare else status == 0)
                result["stages"]["rendering"] = {
                    "status": "passed" if rendered else "incomplete", "screens": len(rendered_names),
                    "tests": counts, "directory": str(shots)}
                result["stages"]["comparison"] = skipped("Recording requested; no comparison performed")
                if compare:
                    complete = rendered and bool(before) and status == 0 and all(
                        record["comparison"] == "passed" for record in records)
                    result["stages"]["comparison"] = {
                        "status": "passed" if complete else "failed" if any(
                            record["comparison"] == "failed" for record in records) else "incomplete",
                        "compared": sum(record["comparison"] in ("passed", "failed") for record in records),
                        "mismatches": sum(record["comparison"] == "failed" for record in records),
                        "new_baselines": len(after - before), "missing_renders": len(before - rendered_names),
                        "diffs": str(diffs),
                        "reason": "Missing baselines are recorded, not compared" if after - before else None}
                if not rendered and status == 0:
                    status = 1
                if compare and result["stages"]["comparison"]["status"] != "passed" and status == 0:
                    status = 1
        except KeyboardInterrupt:
            status = 130
            log.write("error: verification interrupted\n")
        except Exception as error:
            status = 1
            result["error"] = str(error)
            log.write(f"error: {error}\n")
        finally:
            if kind == "ship" and result["stages"]["install"]["status"] == "running":
                log.flush()
                result["stages"].update(install_results(log_path.read_text(), status))
            for value in result["stages"].values():
                if value["status"] == "running":
                    value.update(status="failed", reason=result.get("error", "Verification interrupted"))
            log.flush()
            if kind == "check":
                result["test_counts"] = test_counts(log_path.read_text())
            result.update(status="passed" if status == 0 else "failed", exit_code=status)
            temporary = result_path.with_suffix(".json.tmp")
            temporary.write_text(json.dumps(result, indent=2) + "\n")
            temporary.replace(result_path)

    text = log_path.read_text()
    diagnostics = sorted(set(line for line in text.splitlines() if re.search(
        r"error:|Test Case .* failed|/(Sources|Tests)/.*warning:|^==>", line)))
    print("\n".join(diagnostics[:60]), end="\n" if diagnostics else "")
    detail = ""
    if kind == "check":
        counts = result["test_counts"]
        script_counts = result["stages"]["verification_scripts"].get("test_counts", {})
        detail = f": {counts['behavior']['executed']} behavior tests, {sum(c['skipped'] for c in counts.values())} skipped, {sum(c['failed'] for c in counts.values())} failures, {script_counts.get('total', 0)} script tests"
    elif kind == "shots":
        detail = f": {len(list(shots.glob('*.png')))} screens in {shots}"
    elif status == 0:
        detail = ": installed and launched"
    print(f"{kind} {'passed' if status == 0 else 'FAILED (exit ' + str(status) + ')'}{detail}. Results: {result_path}; full log: {log_path}")
    return status


if __name__ == "__main__":
    def terminate(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, terminate)
    sys.exit(run(sys.argv[1], sys.argv[2:]))
