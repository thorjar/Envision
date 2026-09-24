#!/usr/bin/env python3
"""Run playback regressions using production Swift sources. Requires Xcode + ffmpeg.
Use --simulator with a booted iOS simulator for the real-media test on iOS.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

def run(*args):
    subprocess.run(args, check=True)

with tempfile.TemporaryDirectory(prefix="envision-seek-") as tmp:
    work = Path(tmp)
    clip = work / "clip.mp4"
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
        "testsrc2=size=320x180:rate=24", "-t", "30", "-c:v", "libx264",
        "-pix_fmt", "yuv420p", "-y", str(clip))
    sources = [str(p) for p in (ROOT / "Envision").glob("*.swift") if p.name != "EnvisionApp.swift"]
    code = (HERE / "RealSeekTest.swift").read_text().replace(
        'URL(fileURLWithPath: "/tmp/envision-seek-clip.mp4")',
        'Bundle.main.url(forResource: "clip", withExtension: "mp4")!' if "--simulator" in sys.argv
        else f'URL(fileURLWithPath: "{clip}")')
    flags = ["xcrun", "swiftc", "-parse-as-library", "-swift-version", "5", "-default-isolation", "MainActor"]
    if "--simulator" not in sys.argv:
        controls = (ROOT / "Envision/PlaybackEngineControls.swift").read_text()
        method = controls[controls.index("    func seek(to"):controls.index("    func skip(by")]
        mock = work / "Mock.swift"
        mock.write_text((HERE / "SeekTests.template.swift").read_text().replace("    __SEEK_METHOD__", method))
        run("xcrun", "swiftc", "-parse-as-library", str(mock), "-o", str(work / "mock"))
        run(str(work / "mock"))
        source = work / "Real.swift"
        source.write_text(code)
        run(*flags, *sources, str(source), "-o", str(work / "real"))
        run(str(work / "real"))
    else:
        app = work / "SeekHarness.app"
        app.mkdir()
        shutil.copy(clip, app / "clip.mp4")
        code = code.replace("@main\n", "").replace("static func main()", "static func run()")
        code += '''
import SwiftUI
@main struct SeekHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Playback regression test").task {
                do {
                    try await RealSeekTest.run()
                    let result = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("result.txt")
                    try "PASS: simulator seeks to 18s, then 23s; playback advances beyond 23s".write(to: result, atomically: true, encoding: .utf8)
                } catch { print("FAIL: \\(error)") }
            }
        }
    }
}
'''
        source = work / "Simulator.swift"
        source.write_text(code)
        info = dict(CFBundleExecutable="SeekHarness", CFBundleIdentifier="local.envision.seek-harness",
                    CFBundleName="SeekHarness", CFBundlePackageType="APPL", CFBundleVersion="1",
                    CFBundleShortVersionString="1.0", LSRequiresIPhoneOS=True,
                    UILaunchScreen={}, UIDeviceFamily=[1, 2])
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
        arch = subprocess.check_output(["uname", "-m"], text=True).strip()
        run(*flags, "-sdk", sdk, "-target", f"{arch}-apple-ios26.5-simulator",
            *sources, str(source), "-o", str(app / "SeekHarness"))
        run("codesign", "--force", "--sign", "-", str(app))
        run("xcrun", "simctl", "install", "booted", str(app))
        container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", "booted", info["CFBundleIdentifier"], "data"], text=True).strip())
        result = container / "Documents/result.txt"
        result.unlink(missing_ok=True)
        run("xcrun", "simctl", "launch", "--terminate-running-process", "booted", info["CFBundleIdentifier"])
        for _ in range(60):
            if result.exists():
                print(result.read_text())
                break
            time.sleep(1)
        else:
            raise RuntimeError("Simulator test timed out; inspect simulator crash logs")
