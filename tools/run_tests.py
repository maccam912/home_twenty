#!/usr/bin/env python3
"""Import the game and run every headless suite without credentials or a network."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
TESTS = PROJECT / "tests"


def run(label, command, timeout):
    print(f"\n--- {label} ---", flush=True)
    try:
        result = subprocess.run(command, cwd=PROJECT, capture_output=True,
                                text=True, errors="replace", timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        return False
    output = result.stdout + result.stderr
    print(output.rstrip(), flush=True)
    # A Godot method can abort on a script error while the engine still exits zero.
    fatal_messages = ("SCRIPT ERROR:", "SHADER ERROR:", "Parse Error:",
                      "Failed to load script", "Error loading resource")
    return result.returncode == 0 and not any(word in output for word in fatal_messages)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or "godot")
    options = parser.parse_args()
    failures = []
    with tempfile.TemporaryDirectory(prefix="home-twenty-tests-") as temp:
        engine = [options.godot, "--headless", "--path", str(PROJECT),
                  "--log-file", str(Path(temp) / "engine.log")]
        if not run("Godot resource import", [*engine, "--editor", "--import"], 300):
            return 1
        godot_suites = [(p.name, ["--script", "res://tests/" + p.name])
                        for p in sorted(TESTS.glob("*_test.gd"))]
        for label, args in godot_suites:
            if label == "touch_test.gd":
                args.extend(["--", "--touch-ui"])
        smoke = ["--script", "res://tests/shift_smoke.gd"]
        godot_suites += [("Shift controls and radio", smoke),
                         ("Full contract with driving inputs", [*smoke, "--", "--route"])]
        for label, args in godot_suites:
            if not run(label, [*engine, "--fixed-fps", "60", *args], 180):
                failures.append(label)
        if not run("Offline Python tests", [sys.executable, "-m", "unittest", "discover",
                                            "-s", "tests", "-p", "test_*.py", "-v"], 100):
            failures.append("Python tests")
    if failures:
        print("Failed suites: " + ", ".join(failures), file=sys.stderr)
        return 1
    print(f"All {len(godot_suites)} Godot runs and the Python suite passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
