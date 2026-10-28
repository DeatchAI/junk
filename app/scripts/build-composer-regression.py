#!/usr/bin/env python3
"""Build an isolated GUI regression app from an existing Debug build and its log.

Usage: build-composer-regression.py BUILT_APP XCODE_BUILD_LOG OUTPUT_APP
Launch OUTPUT_APP with the native UI tool; results go to /tmp/detach-composer-regression.
"""
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys

built_app, build_log, output_app = map(Path, sys.argv[1:4])
products = built_app.parent
app_root = Path(__file__).resolve().parent.parent
driver = next(line for line in build_log.read_text().splitlines()
              if "builtin-SwiftDriver --" in line and "-module-name Detach " in line)
arguments = shlex.split(driver.split("builtin-SwiftDriver --", 1)[1])
flags = []
for index, flag in enumerate(arguments[:-1]):
    if flag in ("-I", "-F", "-Xcc"):
        flags.extend([flag, arguments[index + 1]])

contents = output_app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(exist_ok=True)
executable = contents / "MacOS/composer-regression"
command = ["xcrun", "swiftc", "-parse-as-library", "-module-cache-path",
           str(output_app.parent / "composer-regression-modules"), *flags]
for folder in (products / "PackageFrameworks", built_app / "Contents/Frameworks",
               built_app / "Contents/MacOS"):
    command.extend(["-Xlinker", "-rpath", "-Xlinker", str(folder)])
source = Path(sys.argv[4]) if len(sys.argv) > 4 else app_root / "tests/composer/FullComposerWindowRegression.swift"
command.extend([str(source),
                str(built_app / "Contents/MacOS/Detach.debug.dylib"), "-o", str(executable)])
subprocess.run(command, check=True)
for name in ("Assets.car", "Geist-Regular.ttf"):
    source = built_app / "Contents/Resources" / name
    if source.exists():
        shutil.copy2(source, contents / "Resources" / name)
bundle_id = sys.argv[5] if len(sys.argv) > 5 else "dev.detach.composer-regression"
with (contents / "Info.plist").open("wb") as file:
    plistlib.dump({"CFBundleIdentifier": bundle_id,
                  "CFBundleName": output_app.stem if len(sys.argv) > 5 else "Detach Composer Regression",
                  "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                  "CFBundleExecutable": executable.name,
                  "CFBundlePackageType": "APPL", "NSPrincipalClass": "NSApplication"}, file)
print(output_app)
