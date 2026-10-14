#!/usr/bin/env python3
"""Compile and launch isolated native UI checks. Never touches personal app data."""
import pathlib
import plistlib
import subprocess
import sys
import shutil
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
output = sys.argv[1] if len(sys.argv) > 1 else "/private/var/tmp/WorkRhythm-ui-1.7"
(pathlib.Path(output) / "result.txt").unlink(missing_ok=True)
for name in ["WorkRhythm-preview-runtime.log", "WorkRhythm-preview-runtime-error.log"]:
    pathlib.Path("/private/var/tmp", name).write_text("")
bundle = pathlib.Path("/private/var/tmp/WorkRhythmPreview.app")
executable = bundle / "Contents/MacOS/Preview"
executable.parent.mkdir(parents=True, exist_ok=True)
with (bundle / "Contents/Info.plist").open("wb") as file:
    plistlib.dump({
        "CFBundleExecutable": "Preview", "CFBundleIdentifier": "local.workrhythm.preview",
        "CFBundleName": "WorkRhythmPreview", "CFBundlePackageType": "APPL",
        "LSUIElement": True, "LSMinimumSystemVersion": "14.0",
    }, file)
# Compile a stable snapshot: editing the project while the compiler is running
# must not cause "input file was modified during the build".
with tempfile.TemporaryDirectory(prefix="WorkRhythm-preview-source-", dir="/private/var/tmp") as snapshot:
    frozen = pathlib.Path(snapshot)
    shutil.copytree(root / "Sources", frozen / "Sources")
    shutil.copy2(root / "Tools/RenderPreview.swift", frozen / "RenderPreview.swift")
    sources = sorted(str(path) for path in (frozen / "Sources").rglob("*.swift")
                     if path.name != "WorkRhythmApp.swift")
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                    "-module-cache-path", "/private/var/tmp/WorkRhythm-preview-module-cache",
                    *sources, str(frozen / "RenderPreview.swift"), "-o", str(executable)], check=True)
subprocess.run(["open", "-n", "--stdout", "/private/var/tmp/WorkRhythm-preview-runtime.log",
                "--stderr", "/private/var/tmp/WorkRhythm-preview-runtime-error.log",
                str(bundle), "--args", output], check=True)
print("Native preview launched; inspect result.txt and PNGs in", output)
