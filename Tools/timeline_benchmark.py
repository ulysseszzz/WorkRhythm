#!/usr/bin/env python3
"""Compare 1.5 and current timeline preparation. All inputs are synthetic, no database access."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
baseline = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path("/private/var/tmp/WorkRhythm-timeline-benchmark")
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="WorkRhythm-timeline-source-", dir="/private/var/tmp") as directory:
    frozen = pathlib.Path(directory)
    # Finish both compilations before sampling either executable.
    for label, source in [("baseline", baseline), ("current", root)]:
        target = frozen / label
        shutil.copytree(source / "Sources/Core", target)
        binary = output / label
        subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library",
                        "-module-cache-path", str(output / "modules"),
                        *(["-D", "BASELINE_COMPARE"] if label == "baseline" else []),
                        *map(str, sorted(target.glob("*.swift"))),
                        str(root / "Tools/TimelineBenchmark.swift"), "-o", str(binary)], check=True)
    for label in ["baseline", "current"]:
        subprocess.run([str(output / label), str(output / (label + ".json"))], check=True, timeout=60)
old = json.loads((output / "baseline.json").read_text())
new = json.loads((output / "current.json").read_text())
assert [r["checksum"] for r in old] == [r["checksum"] for r in new], "Behavior checksum mismatch"
print("PASS: matching checksums. Results:", output)
