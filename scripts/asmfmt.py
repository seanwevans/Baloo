#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

DEFAULT_INDENT = 4
DEFAULT_COMMENT_COL = 40


def normalize_whitespace_prefix(line: str) -> str:
    """Normalize leading whitespace to spaces only."""
    expanded = line.expandtabs(DEFAULT_INDENT)
    return expanded


def format_line(line: str, indent: int, comment_col: int) -> str:
    raw = normalize_whitespace_prefix(line.rstrip('\n')).rstrip()
    stripped = raw.lstrip()

    # Empty or whitespace-only line
    if stripped == '':
        return ''

    # Full-line comments at column 0
    if stripped.startswith(';'):
        return stripped

    # Keep labels and top-level directives at column 0
    if re.match(r"^[^\s].*:", stripped):
        return stripped
    if stripped.startswith(('section', 'global', 'extern')):
        return stripped

    # Split code and comment
    if ';' in raw:
        code_part, comment_part = raw.split(';', 1)
        code = code_part.strip()
        comment = ';' + comment_part.strip()
    else:
        code = raw.strip()
        comment = ''

    formatted = ' ' * indent + code
    if comment:
        pad = max(1, comment_col - len(formatted))
        formatted += ' ' * pad + comment
    return formatted


def format_text(text: str, indent: int, comment_col: int) -> str:
    lines = text.splitlines()
    formatted_lines = [format_line(line, indent, comment_col) for line in lines]
    return '\n'.join(formatted_lines) + '\n'


def process_file(path: Path, indent: int, comment_col: int, check: bool) -> bool:
    original = path.read_text()
    formatted = format_text(original, indent, comment_col)

    changed = original != formatted
    if check:
        return changed

    if changed:
        path.write_text(formatted)
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description="Format/lint NASM assembly files")
    parser.add_argument('files', nargs='+', help='Assembly files to format/lint')
    parser.add_argument('--indent', type=int, default=DEFAULT_INDENT,
                        help='Indentation width (default: %(default)s)')
    parser.add_argument('--comment-col', type=int, default=DEFAULT_COMMENT_COL,
                        help='Column to align comments (default: %(default)s)')
    parser.add_argument('--check', action='store_true',
                        help='Do not write files; fail if formatting changes are required')
    args = parser.parse_args()

    changed_files = []
    for file in args.files:
        path = Path(file)
        if process_file(path, args.indent, args.comment_col, args.check):
            changed_files.append(file)

    if args.check and changed_files:
        print('Formatting issues found in:')
        for file in changed_files:
            print(f'  {file}')
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
