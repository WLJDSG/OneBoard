"""使用实际 App Bundle 冷启动设置，避免 XCTest 宿主没有通知权限 Bundle 的限制。"""
import os
import platform
import pathlib
import plistlib
import shlex
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
build = (root / "OneBoard/.build" / os.environ.get("ONEBOARD_TEST_CONFIGURATION", "debug")).resolve()
with tempfile.TemporaryDirectory(prefix="oneboard-settings-smoke-") as directory:
    app = pathlib.Path(directory) / "SettingsSmoke.app"
    contents = app / "Contents"
    binary = contents / "MacOS/SettingsSmoke"
    binary.parent.mkdir(parents=True)
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "com.oneboard.settings-smoke", "CFBundleName": "SettingsSmoke",
                      "CFBundleExecutable": "SettingsSmoke", "CFBundlePackageType": "APPL", "LSUIElement": True}, file)
    objects = shlex.split((build / "OneBoard.product/Objects.LinkFileList").read_text())
    objects = [path for path in objects if "/OneBoard.build/" not in path]
    command = ["swiftc", str(root / "script/tests/settings_cold_start.swift"), "-I", str(build / "Modules"),
               "-I", str(root / "OneBoard/.build/checkouts/GRDB.swift/Sources/CSQLite"),
               "-target", platform.machine() + "-apple-macosx15.0", "-o", str(binary), "-lsqlite3",
               "-framework", "AppKit", "-framework", "LocalAuthentication", "-framework", "Security"] + objects
    subprocess.run(command, check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
    print(result.stdout)
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
    assert "PASS: cold settings" in result.stdout
