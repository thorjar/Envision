#!/usr/bin/env python3
"""Run shared API and TV validation regressions on macOS; no server required."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sources = [root / name for name in (
    "Envision/JellymaxAPI.swift", "Envision/JellymaxModels.swift",
    "Envision/Subtitles.swift", "EnvisionTV/TVModels.swift",
    "Tests/TVCore/TVCoreTests.swift",
)]
with tempfile.TemporaryDirectory(prefix="envision-tv-tests-") as directory:
    executable = Path(directory) / "TVCoreTests"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5",
                    *map(str, sources), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
