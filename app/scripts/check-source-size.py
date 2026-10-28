#!/usr/bin/env python3
"""Keep the native app and local runtime within the project's 600-line source limit."""
from pathlib import Path
import sys

app = Path(__file__).resolve().parent.parent
oversized = []
for directory in (app / "lazzy", app / "PowerHelper", app / "server-v2/src", app / "tests"):
    for source in directory.rglob("*"):
        if source.suffix in {".swift", ".ts"}:
            count = len(source.read_bytes().splitlines())
            if count > 600:
                oversized.append(f"{source.relative_to(app)}: {count} lines")
if oversized:
    print("\n".join(oversized))
    sys.exit(1)
print("Native app, runtime, and test sources are within 600 lines per file")
