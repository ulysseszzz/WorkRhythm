#!/usr/bin/env python3
"""Compile native performance harness at Release optimization and launch an isolated app."""
from pathlib import Path
import plistlib
import subprocess
import sys

tool_root = Path(__file__).resolve().parents[1]
source_root = Path(sys.argv[1]) if len(sys.argv) > 1 else tool_root
label = sys.argv[2] if len(sys.argv) > 2 else "current"
directory = Path("/private/var/tmp/WorkRhythm-perf")
directory.mkdir(exist_ok=True)
bundle = directory / f"Probe-{label}.app"
binary = bundle / "Contents/MacOS/Probe"
binary.parent.mkdir(parents=True, exist_ok=True)
with (bundle / "Contents/Info.plist").open("wb") as file:
    plistlib.dump({"CFBundleExecutable": "Probe", "CFBundleIdentifier": f"local.workrhythm.performance.{label}",
                  "CFBundleName": "WorkRhythm Performance", "CFBundlePackageType": "APPL",
                  "LSUIElement": True, "LSMinimumSystemVersion": "14.0"}, file)
sources = sorted(str(path) for path in (source_root / "Sources").rglob("*.swift")
                 if path.name != "WorkRhythmApp.swift")
subprocess.run(["xcrun", "swiftc", "-O", "-swift-version", "5", "-parse-as-library",
                "-module-cache-path", str(directory / "module-cache"),
                *sources, str(tool_root / "Tools/PerformanceProbe.swift"), "-o", str(binary)], check=True)
subprocess.run(["open", "-n", "--stdout", str(directory / f"{label}.log"),
                "--stderr", str(directory / f"{label}.errors.log"),
                str(bundle), "--args", str(directory / f"{label}.json")], check=True)
print("Launched", label, "results at", directory / f"{label}.json")
