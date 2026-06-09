#!/usr/bin/env bash
# baloo_toybox_tests.sh
# Automates POSIX compliance testing against Toybox

set -e

# Resolve the repository location relative to this script so the report
# works from any checkout (including CI); both are overridable via env.
BALOO_ROOT="${BALOO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BALOO_BIN_DIR="${BALOO_BIN_DIR:-$BALOO_ROOT/bin}"

# Hard per-test time limit (seconds). Some Toybox tests block on stdin or
# loop against Baloo's partial implementations, so this keeps a single test
# from stalling the whole run. Overridable via env.
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"

TEST_ENV="/tmp/baloo_compliance_env"
FARM_DIR="$TEST_ENV/symlink_farm"
SUMMARY_FILE="$TEST_ENV/summary_report.txt"
TEST_OUT="$TEST_ENV/last_test.out"

rm -rf "$FARM_DIR" 
mkdir -p "$FARM_DIR"

export PATH="$FARM_DIR:$PATH"

mkdir -p "$TEST_ENV/src"
cd "$TEST_ENV/src"

if [ ! -d "toybox" ]; then
    echo "[*] Cloning Toybox..."
    git clone --depth 1 https://github.com/landley/toybox.git
fi

cd "$TEST_ENV/src/toybox"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

echo "==========================================================" > "$SUMMARY_FILE"
echo " BALOO COMPLIANCE SUMMARY (TOYBOX)" >> "$SUMMARY_FILE"
echo "==========================================================" >> "$SUMMARY_FILE"
printf "%-15s | %-6s | %-6s | %-6s\n" "Utility" "PASS" "FAIL" "SKIP" >> "$SUMMARY_FILE"
echo "----------------------------------------------------------" >> "$SUMMARY_FILE"

echo "[*] Running..."

for file in "$BALOO_BIN_DIR"/*; do
    if [[ -x "$file" && -f "$file" ]] && ! head -c 2 "$file" | grep -q "#!"; then
        UTIL="$(basename "$file")"        
        
        if [ -f "tests/$UTIL.test" ]; then
            
            # FIXED: Separated rm and ln commands
            rm -f "$FARM_DIR"/* 
            ln -sf "$file" "$FARM_DIR/$UTIL"            
            
            # Capture the test output via a file, NOT a $(...) pipe. Some
            # tests background helpers that outlive the test: renice.test
            # spawns `yes` processes whose inherited stderr would keep a
            # command-substitution pipe open forever, so the read never
            # returns even after timeout kills the test itself. Closing stdin
            # stops tests that block reading it; the time cap bounds runaway
            # tests; then we reap the stray helpers and read the file.
            : > "$TEST_OUT"
            TEST_HOST=1 timeout -s KILL "$TEST_TIMEOUT" scripts/test.sh "$UTIL" </dev/null >"$TEST_OUT" 2>&1 || true
            pkill -KILL -x yes 2>/dev/null || true
            OUTPUT="$(cat "$TEST_OUT")"
            
            P_COUNT=$(echo "$OUTPUT" | grep -c "^PASS:" || true)
            F_COUNT=$(echo "$OUTPUT" | grep -c "^FAIL:" || true)
            S_COUNT=$(echo "$OUTPUT" | grep -c "^SKIP:" || true)

            TOTAL_PASS=$((TOTAL_PASS + P_COUNT))
            TOTAL_FAIL=$((TOTAL_FAIL + F_COUNT))
            TOTAL_SKIP=$((TOTAL_SKIP + S_COUNT))

            printf "%-15s | %-6d | %-6d | %-6d\n" "$UTIL" "$P_COUNT" "$F_COUNT" "$S_COUNT" >> "$SUMMARY_FILE"
            echo " -> Tested $UTIL: $P_COUNT passed"
        fi
    fi
done

echo "----------------------------------------------------------" >> "$SUMMARY_FILE"
printf "%-15s | %-6d | %-6d | %-6d\n" "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_SKIP" >> "$SUMMARY_FILE"
echo "==========================================================" >> "$SUMMARY_FILE"

echo ""
cat "$SUMMARY_FILE"
