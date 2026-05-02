#!/usr/bin/env python3
"""Fail when README links point to missing src/*.asm files."""
from pathlib import Path
import re
import sys


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    readme_path = repo_root / "README.md"
    content = readme_path.read_text()

    missing: list[str] = []
    for rel_path in re.findall(r"\(src/([a-zA-Z0-9_+-]+\.asm)\)", content):
        file_path = repo_root / "src" / rel_path
        if not file_path.exists():
            missing.append(f"src/{rel_path}")

    if missing:
        print("README has links to missing source files:")
        for path in sorted(set(missing)):
            print(f"- {path}")
        return 1

    print("README src/*.asm links are valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
