#!/usr/bin/env python3
"""Update README.md progress and catalog from Baloo.json."""
import json
import re
from pathlib import Path


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    json_path = repo_root / "Baloo.json"
    readme_path = repo_root / "README.md"

    data = json.loads(json_path.read_text())
    total = len(data)
    done = sum(1 for entry in data if entry.get("isDone"))

    progress_badge = (
        f"![Progress](https://img.shields.io/badge/progress-{done}%2F{total}%20done-brightgreen)"
    )

    lines = readme_path.read_text().splitlines()

    # Update progress badge line
    for idx, line in enumerate(lines):
        m = re.match(r"^!\[Progress\]\([^)]+\)(.*)$", line)
        if m:
            suffix = m.group(1).lstrip()
            lines[idx] = f"{progress_badge}{(' ' + suffix) if suffix else ''}"
            break

    # Locate catalog section
    start = end = None
    for i, line in enumerate(lines):
        if line.strip() == "## Catalog":
            start = i + 1
            continue
        if start is not None and line.startswith("## Benchmark"):
            end = i
            break
    if start is None or end is None:
        raise RuntimeError("Failed to locate catalog section in README")

    catalog_lines = [
        f"- [`{entry['name']}`](src/{entry['name']}.asm) {'✅' if entry['isDone'] else '⛔️'} {entry['description']}"
        for entry in data
    ]

    lines[start:end] = catalog_lines
    readme_path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
