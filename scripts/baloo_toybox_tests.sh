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

# A few Toybox tests assert behaviour the kernel reserves for privileged
# processes. The harness stops a test file at its first failure, so one such
# assertion buries the rest of the file, and the report ends up blaming Baloo
# for a limit of the machine it ran on. Skip those instead.

# can_lower_nice: renice.test asserts that "renice -n -1" takes a nice-0
# process to -1. Lowering a nice value needs CAP_SYS_NICE, or headroom under
# RLIMIT_NICE, whose floor is 20 minus the limit; with neither, util-linux's
# own renice fails that same assertion.
can_lower_nice() {
    [ "$EUID" -eq 0 ] && return 0
    local limit stat
    limit="$(ulimit -e)"
    [ "$limit" = unlimited ] && return 0
    read -ra stat < /proc/self/stat      # field 19 is the nice value
    [ $(( ${stat[18]} - 1 )) -ge $(( 20 - limit )) ]
}

# skip_reason UTIL: why UTIL's test cannot run here, or nothing when it can.
skip_reason() {
    case "$1" in
        renice)
            can_lower_nice ||
                echo "needs CAP_SYS_NICE or RLIMIT_NICE headroom to lower a nice value"
            ;;
    esac
}

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
            
            SKIP_WHY="$(skip_reason "$UTIL")"

            # Capture the test output via a file, NOT a $(...) pipe. Some
            # tests background helpers that outlive the test: renice.test
            # spawns `yes` processes whose inherited stderr would keep a
            # command-substitution pipe open forever, so the read never
            # returns even after timeout kills the test itself. Closing stdin
            # stops tests that block reading it; the time cap bounds runaway
            # tests; then we reap the stray helpers and read the file.
            : > "$TEST_OUT"
            if [ -n "$SKIP_WHY" ]; then
                # Counted below like any SKIP: line a test prints itself.
                printf 'SKIP: %s (%s)\n' "$UTIL" "$SKIP_WHY" > "$TEST_OUT"
            else
                TEST_HOST=1 timeout -s KILL "$TEST_TIMEOUT" scripts/test.sh "$UTIL" </dev/null >"$TEST_OUT" 2>&1 || true
                pkill -KILL -x yes 2>/dev/null || true
            fi
            OUTPUT="$(cat "$TEST_OUT")"
            
            P_COUNT=$(echo "$OUTPUT" | grep -c "^PASS:" || true)
            F_COUNT=$(echo "$OUTPUT" | grep -c "^FAIL:" || true)
            S_COUNT=$(echo "$OUTPUT" | grep -c "^SKIP:" || true)

            TOTAL_PASS=$((TOTAL_PASS + P_COUNT))
            TOTAL_FAIL=$((TOTAL_FAIL + F_COUNT))
            TOTAL_SKIP=$((TOTAL_SKIP + S_COUNT))

            printf "%-15s | %-6d | %-6d | %-6d\n" "$UTIL" "$P_COUNT" "$F_COUNT" "$S_COUNT" >> "$SUMMARY_FILE"
            if [ -n "$SKIP_WHY" ]; then
                echo " -> Skipped $UTIL: $SKIP_WHY"
            else
                echo " -> Tested $UTIL: $P_COUNT passed"
            fi
        fi
    fi
done

echo "----------------------------------------------------------" >> "$SUMMARY_FILE"
printf "%-15s | %-6d | %-6d | %-6d\n" "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL" "$TOTAL_SKIP" >> "$SUMMARY_FILE"
echo "==========================================================" >> "$SUMMARY_FILE"

echo ""
cat "$SUMMARY_FILE"
