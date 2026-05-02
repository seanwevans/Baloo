#!/usr/bin/env bash
# Benchmark Baloo's assembly utilities against system utilities.
#
# Usage: run from any working directory after `make`; this script resolves
# the repository root from its own location and uses <repo>/bin for Baloo binaries.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BALOOBIN="$REPO_ROOT/bin"


# Verify every benchmarked Baloo command resolves to a built binary in bin/
for cmd in cat echo true false base64; do
  if [[ ! -x "$BALOOBIN/$cmd" ]]; then
    echo "Missing benchmark binary: $BALOOBIN/$cmd. Run 'make' from repo root first." >&2
    exit 1
  fi
done

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
