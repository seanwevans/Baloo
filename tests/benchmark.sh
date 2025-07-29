#!/usr/bin/env bash
# Benchmark Baloo's assembly utilities against system utilities.

set -e

BALOOBIN="$(dirname "$0")/bin"

# Ensure hyperfine is installed
if ! command -v hyperfine >/dev/null; then
  echo "hyperfine not found. Install it with: sudo apt-get install -y hyperfine" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Prepare a 1MB test file for commands that need input
head -c 1048576 </dev/urandom > "$TMPDIR/file"

benchmark() {
  local name=$1
  shift
  echo "\n== $name =="
  hyperfine --ignore-failure "$@"
}

benchmark "cat"    "$BALOOBIN/cat $TMPDIR/file > /dev/null"    "cat $TMPDIR/file > /dev/null"
benchmark "echo"   "$BALOOBIN/echo hello > /dev/null"         "echo hello > /dev/null"
benchmark "true"   "$BALOOBIN/true"                             "/bin/true"
benchmark "false"  "$BALOOBIN/false"                            "/bin/false"
benchmark "base64" "$BALOOBIN/base64 $TMPDIR/file > /dev/null" "base64 $TMPDIR/file > /dev/null"
