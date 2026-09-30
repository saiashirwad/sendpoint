#!/usr/bin/env python3
"""Research only. No app installation, network access, or signing credentials."""
import json
import pathlib
import plistlib
import statistics
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent
scratch = pathlib.Path(tempfile.gettempdir()) / "opencode"
scratch.mkdir(exist_ok=True)
out = pathlib.Path(tempfile.mkdtemp(prefix="odin-agents-", dir=scratch))
results = {}
def run(args, check=True):
    p = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and p.returncode:
        raise RuntimeError(p.stdout)
    return p

results["compiler"] = run(["odin", "version"]).stdout.strip()
results["output_directory"] = str(out)
commands = {
    "check_capture": ["odin", "check", str(root / "capture"), "-no-entry-point"],
    "test_capture": ["odin", "test", str(root / "capture"), f"-out:{out}/tests", "-define:ODIN_TEST_FANCY=false", "-define:ODIN_TEST_THREADS=1", "-define:ODIN_TEST_RANDOM_SEED=42"],
    "build_native_debug": ["odin", "build", str(root / "native"), "-debug", f"-out:{out}/native"],
    "build_native_release": ["odin", "build", str(root / "native"), "-o:speed", f"-out:{out}/native-release"],
}
for name, command in commands.items():
    samples = []
    for _ in range(5):
        start = time.perf_counter()
        p = run(command)
        samples.append(round(time.perf_counter() - start, 4))
    results[name] = {"seconds": samples, "median": statistics.median(samples), "last_output": p.stdout}

app = out / "OdinProbe.app"
(app / "Contents/MacOS").mkdir(parents=True)
(app / "Contents/Resources").mkdir()
run(["cp", str(out / "native"), str(app / "Contents/MacOS/OdinProbe")])
with (app / "Contents/Info.plist").open("wb") as f:
    plistlib.dump({"CFBundleExecutable": "OdinProbe", "CFBundleIdentifier": "research.sendpoint.odin-probe", "CFBundleName": "OdinProbe", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "0.0.1", "LSUIElement": True}, f)
results["sign"] = run(["codesign", "--force", "--sign", "-", str(app)]).stdout
results["verify"] = run(["codesign", "--verify", "--strict", "--verbose=2", str(app)]).stdout
results["bundle_execution"] = run([str(app / "Contents/MacOS/OdinProbe")]).stdout
results["debugger"] = run(["lldb", "--batch", "-o", f"target symbols add {out}/native.dSYM", "-o", "breakpoint set --file main.odin --line 8", "-o", "run", "-o", "frame variable pool", "-o", "continue", str(app / "Contents/MacOS/OdinProbe")], check=False).stdout
results["sizes"] = {"debug_bytes": (out / "native").stat().st_size, "release_bytes": (out / "native-release").stat().st_size}
results["appkit_construction"] = run(["odin", "run", str(root / "appkit"), f"-out:{out}/appkit"]).stdout
# Negative compilation probe, kept out of runnable package.
bad = out / "missing_case.odin"
bad.write_text('package main\nMode :: enum {Text, Voice}\nmain :: proc() { m := Mode.Text; switch m { case .Text: } }\n')
p = run(["odin", "check", str(bad), "-file"], check=False)
results["missing_enum_case"] = {"exit": p.returncode, "output": p.stdout}
assert p.returncode != 0
print(json.dumps(results, indent=2))
