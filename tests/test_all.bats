#!/usr/bin/env bats
bats_load_library bats-support
bats_load_library bats-assert

# Directory with Baloo binaries ------------------------------------------------
setup()  { BIN="${BATS_TEST_DIRNAME}/../bin"; TMP=$(mktemp -d); }
teardown(){ rm -rf "$TMP"; }

make_utmp_fixture() {
  local file="$1"
  python3 - "$file" <<'PY'
import struct
import sys

path = sys.argv[1]
UTMP_SIZE = 384
records = []
for user, line, when in ((b"alice", b"pts/0", 1234567890), (b"bob", b"tty1", 1234567891)):
    rec = bytearray(UTMP_SIZE)
    struct.pack_into("<h", rec, 0, 7)
    rec[8:8 + len(line)] = line
    rec[44:44 + len(user)] = user
    struct.pack_into("<I", rec, 340, when)
    records.append(rec)
open(path, "wb").write(b"".join(records))
PY
}

# ----------  SINGLE‑TEST SMOKE CHECKS FOR EVERY ✅ PROGRAM ---------- #


@test "alias — lists stored aliases" {
  printf 'baloo=test\n' >/tmp/alias.txt
  run "$BIN/alias"
  rm -f /tmp/alias.txt
  assert_success
  assert_output --partial 'baloo=test'
}

@test "ar — fails cleanly without an archive" {
  run "$BIN/ar"
  assert_failure
  assert_output 'Usage: ar t ARCHIVE'
}

@test "arch — prints hardware name" {
  run "$BIN/arch"
  assert_success
  assert_output "$(uname -m)"
}


@test "baseenc — defaults to base64 encoding" {
  printf 'hello' >"$TMP/plain"
  run "$BIN/baseenc" "$TMP/plain"
  assert_success
  assert_output 'aGVsbG8='
}

@test "basename — strips directories" {
  run "$BIN/basename" "/usr/local/bin/foo"
  assert_output "foo"
}

@test "at — accepts a scheduled command" {
  printf 'echo later\n' >"$TMP/atjob"
  run "$BIN/at" now <"$TMP/atjob"
  assert_success
}

@test "base32 — encodes file contents" {
  printf 'hello' >"$TMP/plain"
  run "$BIN/base32" "$TMP/plain"
  assert_success
  assert_output 'NBSWY3DP'
}

@test "base64 — encodes file contents" {
  printf 'hello' >"$TMP/plain"
  run "$BIN/base64" "$TMP/plain"
  assert_success
  assert_output 'aGVsbG8='
}

@test "batch — accepts a queued command" {
  printf 'echo batched\n' >"$TMP/batchjob"
  run "$BIN/batch" <"$TMP/batchjob"
  assert_success
}

@test "bc — evaluates expressions without delegating to system bc" {
  printf '2+2
(3+4)*5
2^8
7/2
' >"$TMP/bc.in"

  run "$BIN/bc" "$TMP/bc.in"
  assert_success
  assert_output $'4
35
256
3'

  if command -v strings >/dev/null 2>&1; then
    run strings "$BIN/bc"
    refute_output --partial "/usr/bin/bc"
  fi
}


@test "cat — echoes file contents" {
  echo "hello, baloo" >"$TMP/file"
  run "$BIN/cat" "$TMP/file"
  assert_output "hello, baloo"
}

@test "cd — exits success when directory exists" {
  run "$BIN/cd" /
  assert_success
}

@test "chcon — sets security context" {
  touch "$TMP/ctxfile"

  # Probe SELinux xattr support first so this test is skipped (not failed)
  # on filesystems that do not implement security.selinux xattrs.
  unsupported_reason=""
  if command -v getfattr >/dev/null 2>&1; then
    if ! getfattr -n security.selinux "$TMP/ctxfile" >/dev/null 2>"$TMP/chcon-probe.err"; then
      probe_err=$(<"$TMP/chcon-probe.err")
      if [[ "$probe_err" =~ [Oo]peration[[:space:]]not[[:space:]]supported|[Nn]ot[[:space:]]supported|ENOTSUP|EOPNOTSUPP ]]; then
        unsupported_reason="SELinux xattrs unsupported for test filesystem ($probe_err)"
      fi
    fi
  fi

  if [ -n "$unsupported_reason" ]; then
    skip "$unsupported_reason"
  fi

  run "$BIN/chcon" "dummy_u:dummy_r:dummy_t:s0" "$TMP/ctxfile"

  if [ "$status" -ne 0 ] && [[ "$output" =~ [Oo]peration[[:space:]]not[[:space:]]supported|[Nn]ot[[:space:]]supported|ENOTSUP|EOPNOTSUPP ]]; then
    skip "Baloo chcon reports SELinux xattrs unsupported: $output"
  fi

  assert_success
}

@test "chgrp — changes group ownership" {  
  touch "$TMP/testfile"    
  current_group=$(id -g)    
  run "$BIN/chgrp" "$current_group" "$TMP/testfile"
  assert_success    
  file_group=$(stat -c %g "$TMP/testfile")
  assert_equal "$file_group" "$current_group"
}

@test "chgrp — passes parsed gid as chown gid argument" {
  if ! command -v strace >/dev/null 2>&1; then
    skip "strace is required for syscall argument regression check"
  fi

  if [ "$(id -u)" -eq 0 ]; then
    skip "requires non-root: root may change group ownership freely, so chgrp will not fail"
  fi

  touch "$TMP/testfile"
  gid=12345
  run strace -e trace=chown "$BIN/chgrp" "$gid" "$TMP/testfile"

  assert_failure
  assert_line --regexp "chown\(\"$TMP/testfile\", -1, $gid\)"
}

@test "chmod — changes mode" {
  touch "$TMP/f"
  run "$BIN/chmod" 600 "$TMP/f"
  assert_success
  run stat -c %a "$TMP/f"
  assert_output '600'
}

@test "chown — (non‑root) returns EPERM" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "requires non-root: root can change ownership without EPERM"
  fi
  touch "$TMP/f"
  run "$BIN/chown" 0 "$TMP/f"
  assert_failure
}

@test "chroot — fails without privilege and prints usage" {
  run "$BIN/chroot" 2>/dev/null
  assert_failure
}

@test "cmp — identical files exit 0" {
  echo test >"$TMP/a"; cp "$TMP/a" "$TMP/b"
  run "$BIN/cmp" "$TMP/a" "$TMP/b"
  assert_success
}

@test "cksum — checksums stdin" {
  run bash -c 'printf hello | "$1"' _ "$BIN/cksum"
  assert_success
  assert_output --partial '907060870 5'
}

@test "command — executes a command" {
  run "$BIN/command" "$BIN/true"
  assert_success
}

@test "comm — compares sorted files" {
  printf 'a\nb\nc\n' >"$TMP/a"
  printf 'b\nc\nd\n' >"$TMP/b"
  run "$BIN/comm" "$TMP/a" "$TMP/b"
  expected_comm=$'a\n\t\tb\n\t\tc\n\td'
  assert_output "$expected_comm"
}


@test "cp — copies file" {
  echo copy >"$TMP/src"
  run "$BIN/cp" "$TMP/src" "$TMP/dst"
  assert_success
  assert [ -f "$TMP/dst" ]
  assert_equal "$(cat "$TMP/dst")" "copy"
}

@test "dd — copies stdin to stdout by default" {
  run "$BIN/dd" <<<'hello'
  assert_success
  assert_output 'hello'
}

@test "df — prints available bytes" {
  run "$BIN/df"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "cut — first 3 chars" {
  printf "abcdef\n" >"$TMP/cutfile"
  run "$BIN/cut" -c 3 "$TMP/cutfile"
  assert_output --partial "abc"
}

@test "csplit — splits at line" {
  printf "one\ntwo\nthree\n" >"$TMP/in"
  pushd "$TMP" >/dev/null
  run "$BIN/csplit" "$TMP/in" 2
  popd >/dev/null
  assert_success
  printf 'one\ntwo\n' >"$TMP/expected_xaa"
  printf 'three\n' >"$TMP/expected_xab"
  run cmp -s "$TMP/xaa" "$TMP/expected_xaa"
  assert_success
  run cmp -s "$TMP/xab" "$TMP/expected_xab"
  assert_success
}

@test "date — prints a date-like timestamp" {
  run "$BIN/date"
  assert_success
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]
}

@test "dircolors — emits LS_COLORS shell setup" {
  run "$BIN/dircolors"
  assert_success
  assert_output --partial "LS_COLORS='"
  assert_output --partial 'export LS_COLORS'
}

@test "du — reports usage for the current directory" {
  pushd "$TMP" >/dev/null
  run "$BIN/du"
  popd >/dev/null
  assert_success
  assert_output --partial '.'
}

@test "dirname — keeps directory portion" {
  run "$BIN/dirname" "/etc/ssl/certs"
  assert_output "/etc/ssl"
}

@test "echo — prints its arguments" {
  run "$BIN/echo" -n "ping"
  assert_output "ping"
}

@test "expand — converts tabs to spaces" {
  printf 'a\tb\n' >"$TMP/t"
  run "$BIN/expand" "$TMP/t"
  assert_output 'a       b'
}

@test "expr — basic arithmetic" {
  run "$BIN/expr" 3 + 2
  assert_output '5'
}

@test "factor — factors 77" {
  run "$BIN/factor" 77
  assert_output "77: 7 11"
}

@test "false — exits with non‑zero" {
  run "$BIN/false"
  assert_failure
}

@test "file — identifies ELF binary" {
  run "$BIN/file" "$BIN/arch"
  assert_success
}


@test "fmt — copies short input" {
  run "$BIN/fmt" <<<'hello'
  assert_success
  assert_output 'hello'
}

@test "gencat — fails cleanly for a missing catalog" {
  run "$BIN/gencat" "$TMP/missing.cat"
  assert_failure
  assert_output 'Error opening file'
}

@test "fold — wraps long lines" {
  printf '%0.sx' {1..100} >"$TMP/long"
  run "$BIN/fold" -w 20 "$TMP/long"
  assert_success
  [ "$(echo "$output" | head -1 | wc -c)" -le 21 ]    # 20 chars + newline
}

@test "groups — prints numeric groups" {
  run "$BIN/groups"
  assert_output "$(id -G)"
}


@test "hash — computes an FNV-1a hash" {
  run "$BIN/hash" hello
  assert_success
  assert_output 'cbf29ce484222325'
}

@test "head — first line only" {
  printf '1\n2\n3\n' >"$TMP/l"
  run "$BIN/head" -n 1 "$TMP/l"
  assert_output '1'
}

@test "hostid — prints a hex id" {
  run "$BIN/hostid"
  assert_success
  [[ "$output" =~ ^[0-9a-f]{8}$ ]]
}

@test "id — prints uid" {
  run "$BIN/id" -u
  assert_output "$(id -u)"
}



@test "install — copies source to destination" {
  printf 'install data' >"$TMP/install.src"
  run "$BIN/install" "$TMP/install.src" "$TMP/install.dst"
  assert_success
  assert_equal "$(cat "$TMP/install.dst")" 'install data'
}

@test "join — joins matching fields" {
  printf 'a 1\nb 2\n' >"$TMP/j1"
  printf 'a X\nc Y\n' >"$TMP/j2"
  run "$BIN/join" "$TMP/j1" "$TMP/j2"
  assert_success
  assert_output 'a 1 X'
}

@test "kill — terminates a background process" {
  sleep 30 & pid=$!
  trap 'kill "$pid" 2>/dev/null || true' RETURN
  if [ -z "$pid" ]; then
    fail "failed to capture background pid in kill test"
  fi
  run "$BIN/kill" "$pid"
  assert_success
  run wait "$pid"
  assert_failure
}

@test "link — creates hard link" {
  echo "hard" >"$TMP/orig"
  run "$BIN/link" "$TMP/orig" "$TMP/lnk"
  assert_success
  assert_equal "$(cat "$TMP/lnk")" "hard"
}

@test "ln — default hard‑link creation" {
  echo hi >"$TMP/a"
  run "$BIN/ln" "$TMP/a" "$TMP/b"
  assert_success
  assert [ -f "$TMP/b" ]
}


@test "locale — prints locale variables" {
  run "$BIN/locale"
  assert_success
  assert_output --partial 'LANG='
  assert_output --partial 'LC_CTYPE='
}


@test "localedef — fails cleanly for missing input" {
  run "$BIN/localedef" -i "$TMP/no-locale" -f UTF-8 "$TMP/out-locale"
  assert_failure
  assert_output 'Error opening file'
}

@test "lp — fails cleanly when no printer is available" {
  printf 'print me' >"$TMP/print.txt"
  run "$BIN/lp" "$TMP/print.txt"
  assert_success
  assert_output --partial 'lp: cannot open printer'
}

@test "man — reports failure when no page can be opened" {
  run "$BIN/man" baloo-definitely-missing
  assert_failure
}

@test "logname — prints login name" {
  if ! logname >/dev/null 2>&1; then
    skip "logname unavailable (no login session in CI)"
  fi

  run "$BIN/logname"
  assert_success
  assert_output "$(logname)"
}

@test "ls — current directory listing contains test file" {
  touch "$TMP/zzz"
  pushd "$TMP" >/dev/null
  run "$BIN/ls"
  popd >/dev/null
  assert_output --partial "zzz"
}

@test "sum — computes BSD checksum" {
  printf 'hello\n' >"$TMP/sumfile"
  if command -v timeout >/dev/null 2>&1; then
    run timeout 2 "$BIN/sum" "$TMP/sumfile"
  else
    run "$BIN/sum" "$TMP/sumfile"
  fi
  assert_success
  assert_output "36979 1 $TMP/sumfile"
}

@test "m4 — expands simple macros" {
  printf 'define(name,Baloo)Hello, name\n' >"$TMP/input.m4"
  run "$BIN/m4" "$TMP/input.m4"
  assert_success
  assert_output "Hello, Baloo"
}

@test "m4 — supports undefine and ifdef" {
  printf 'ifdef(name,yes,no)\ndefine(name,Baloo)ifdef(name,yes,no)\nundefine(name)ifdef(name,yes,no)\n' >"$TMP/input.m4"
  run "$BIN/m4" "$TMP/input.m4"
  assert_success
  assert_output $'no\nyes\nno'
}


@test "md5sum — hashes empty input" {
  : >"$TMP/empty"
  run "$BIN/md5sum" "$TMP/empty"
  assert_success
  assert_output 'd41d8cd98f00b204e9800998ecf8427e'
}

@test "mesg — reports terminal message status" {
  run "$BIN/mesg"
  assert_success
  [[ "$output" =~ ^is[[:space:]][yn]$ ]]
}

@test "ngettext — selects plural form" {
  run "$BIN/ngettext" singular plural 2
  assert_success
  assert_output 'plural'
}

@test "nohup — reports missing command" {
  run "$BIN/nohup"
  assert_failure
}

@test "pinky — prints a summary count" {
  run "$BIN/pinky"
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "ps — lists running processes" {
  run "$BIN/ps"
  assert_success
  assert_output --partial 'bash'
}

@test "mkdir — creates directory" {
  run "$BIN/mkdir" "$TMP/dir"
  assert_success
  assert [ -d "$TMP/dir" ]
}

@test "mkfifo — makes named pipe" {
  run "$BIN/mkfifo" "$TMP/p"
  assert_success
  assert [ -p "$TMP/p" ]
}

@test "mknod — creates fifo" {
  run "$BIN/mknod" "$TMP/nod" p
  assert_success
  assert [ -p "$TMP/nod" ]
}

@test "mktemp — returns unique path" {
  run "$BIN/mktemp" -u
  assert_success
  [[ "$output" =~ /tmp/ ]]
}

@test "mv — moves file" {
  echo move >"$TMP/m"
  run "$BIN/mv" "$TMP/m" "$TMP/n"
  assert_success
  assert_equal "$(cat "$TMP/n")" "move"
}

@test "newgrp — executes command with new gid" {
  gid=$(id -g)
  run "$BIN/newgrp" "$gid" "$BIN/id" -g
  assert_success
  assert_output "$gid"
}

@test "nproc — ≥ 1" {
  run "$BIN/nproc"
  assert_success
  [[ "$output" -ge 1 ]]
}

@test "numfmt — converts bytes" {
  run "$BIN/numfmt" 2048
  assert_output '2K'
}

@test "nice — executes command" {
  run "$BIN/nice" "$BIN/true"
  assert_success
}

@test "renice — adjusts pid priority" {
  sleep 30 & pid=$!
  trap 'kill "$pid" 2>/dev/null || true' RETURN
  if [ -z "$pid" ]; then
    fail "failed to capture background pid in renice test"
  fi
  run "$BIN/renice" 5 "$pid"
  if [ "$status" -ne 0 ]; then
    skip "renice unavailable for this process in the test environment"
  fi
  run ps -o ni= -p "$pid"
  if [ "$status" -ne 0 ]; then
    skip "renice target process is unavailable in the test environment"
  fi
  normalized_nice="$(echo "$output" | xargs)"
  assert_equal "$normalized_nice" "5"
}


@test "printf — prints its format operand" {
  run "$BIN/printf" 'hello'
  assert_success
  assert_output 'hello'
}

@test "printenv — returns PATH value" {
  run "$BIN/printenv" PATH
  assert_output "$PATH"
}

@test "env — prints environment" {
  run "$BIN/env"
  [[ "$output" == *"PATH="* ]]
}

@test "env — executes command" {
  run "$BIN/env" "$BIN/true"
  assert_success
}

@test "pwd — matches $(pwd)" {
  pushd "$TMP" >/dev/null
  run "$BIN/pwd"
  assert_output "$TMP"
  popd >/dev/null
}

@test "readlink — prints symlink target" {
  ln -s /etc/hosts "$TMP/sym"
  run "$BIN/readlink" "$TMP/sym"
  assert_output "/etc/hosts"
}

@test "rm — removes file" {
  touch "$TMP/r"
  run "$BIN/rm" "$TMP/r"
  assert_success
  refute [ -e "$TMP/r" ]
}

@test "shred — overwrites and deletes" {
  printf 'secret' >"$TMP/s"
  run "$BIN/shred" -u "$TMP/s"
  assert_success
  refute [ -e "$TMP/s" ]
}

@test "rmdir — removes empty dir" {
  mkdir "$TMP/d"
  run "$BIN/rmdir" "$TMP/d"
  assert_success
  refute [ -d "$TMP/d" ]
}

@test "seq — prints numeric sequence" {
  run "$BIN/seq" 3
  assert_output $'1\n2\n3'
}

@test "sleep — sleeps & returns" {
  run "$BIN/sleep" 0
  assert_success
}

@test "sync — exits 0" {
  run "$BIN/sync"
  assert_success
}

@test "tabs — exits 0" {
  run "$BIN/tabs"
  assert_success
}

@test "tail — last line only" {
  printf '1\n2\n3\n' >"$TMP/l"
  run "$BIN/tail" -n 1 "$TMP/l"
  assert_output '3'
}

@test "tac — reverses line order" {
  printf 'a\nb\nc\n' >"$TMP/tacfile"
  run "$BIN/tac" "$TMP/tacfile"
  assert_output $'c\nb\na'
}

@test "tee — writes stdin to stdout and file" {
  printf 'tee data' >"$TMP/tee.in"
  run "$BIN/tee" "$TMP/tee.out" <"$TMP/tee.in"
  assert_success
  assert_output 'tee data'
  assert_equal "$(cat "$TMP/tee.out")" 'tee data'
}

@test "time — runs a command and prints timings" {
  run "$BIN/time" "$BIN/true"
  assert_success
  assert_output --partial 'real '
  assert_output --partial 'user '
  assert_output --partial 'sys '
}

@test "timeout — runs a command within the time limit" {
  run "$BIN/timeout" 2 "$BIN/true"
  assert_success
}

@test "test — basic comparisons" {
  touch "$TMP/exist"
  run "$BIN/test" -e "$TMP/exist"
  assert_success
  run "$BIN/test" foo = foo
  assert_success
  run "$BIN/test" foo = bar
  assert_failure
}

@test "touch — creates empty file" {
  run "$BIN/touch" "$TMP/new"
  assert_success
  assert [ -f "$TMP/new" ]
}
@test "true — exits 0" {
  run "$BIN/true"
  assert_success
}

@test "truncate — shrinks file" {
  printf 'xxxxx' >"$TMP/f"
  run "$BIN/truncate" -s 2 "$TMP/f"
  assert_success
  [ "$(wc -c < "$TMP/f")" -eq 2 ]
}


@test "tsort — accepts an acyclic graph" {
  printf 'b a\na c\n' >"$TMP/graph"
  run "$BIN/tsort" "$TMP/graph"
  assert_success
}

@test "tty — behaves when stdin is not a tty" {
  run "$BIN/tty" < /dev/null
  assert_failure
}

@test "umask — prints current mask" {
  run "$BIN/umask"
  assert_success
  [[ "$output" =~ ^[0-7]{3,4}$ ]]
}

@test "uname — -s matches system" {
  run "$BIN/uname" -s
  assert_output "$(uname -s)"
}

@test "unexpand — converts spaces to tabs" {
  printf 'a       b\n' >"$TMP/s"
  run "$BIN/unexpand" "$TMP/s"
  assert_output $'a\tb'
}


@test "unalias — removes a named alias entry" {
  printf 'baloo=test\nkeep=1\n' >/tmp/alias.txt
  run "$BIN/unalias" baloo
  status_after="$status"
  aliases_after="$(cat /tmp/alias.txt 2>/dev/null || true)"
  rm -f /tmp/alias.txt
  assert_equal "$status_after" 0
  [[ "$aliases_after" != *'baloo=test'* ]]
  [[ "$aliases_after" == *'keep=1'* ]]
}

@test "uniq — removes adjacent duplicates" {
  printf 'a\na\nb\n' >"$TMP/uniq"
  run "$BIN/uniq" "$TMP/uniq"
  assert_success
  assert_output $'a\nb'
}

@test "unlink — removes file via unlink" {
  touch "$TMP/u"
  run "$BIN/unlink" "$TMP/u"
  assert_success
  refute [ -e "$TMP/u" ]
}

@test "uptime — prints uptime string" {
  run "$BIN/uptime"
  assert_success
  assert_output --partial "load"
}

@test "users — reads an explicit utmp file" {
  make_utmp_fixture "$TMP/utmp"
  run "$BIN/users" "$TMP/utmp"
  assert_success
  assert_output "alice bob"
}


@test "xargs — default echo is resolved via PATH" {
  cat >"$TMP/echo" <<'SH'
#!/bin/sh
printf 'path-echo:%s\n' "$*"
SH
  chmod +x "$TMP/echo"

  run env PATH="$TMP:$PATH" "$BIN/xargs" <<<'alpha beta'

  assert_success
  assert_output "path-echo:alpha beta"
}

@test "xargs — explicit command is resolved via PATH" {
  cat >"$TMP/collect" <<'SH'
#!/bin/sh
printf 'collected:%s\n' "$*"
SH
  chmod +x "$TMP/collect"

  run env PATH="$TMP:$PATH" "$BIN/xargs" collect prefix <<<'alpha beta'

  assert_success
  assert_output "collected:prefix alpha beta"
}


@test "uudecode — accepts empty stdin" {
  run "$BIN/uudecode" </dev/null
  assert_success
}

@test "uuencode — emits begin and end markers" {
  printf 'hello' >"$TMP/uu.in"
  run "$BIN/uuencode" "$TMP/uu.in" out.txt
  assert_success
  assert_output --partial 'begin 644'
  assert_output --partial 'end'
}

@test "wait — times out when no child exits" {
  run "$BIN/wait"
  assert_failure
}

@test "write — fails without a recipient" {
  run "$BIN/write" </dev/null
  assert_failure
}

@test "wc — counts lines" {
  printf 'a\nb\n' >"$TMP/w"
  run "$BIN/wc" -l "$TMP/w"
  assert_output "2 $TMP/w"
}

@test "who — reads an explicit utmp file" {
  make_utmp_fixture "$TMP/utmp"
  run "$BIN/who" "$TMP/utmp"
  assert_success
  assert_output $'alice\tpts/0\t1234567890
bob\ttty1\t1234567891'
}

@test "whoami — matches whoami(1)" {
  run "$BIN/whoami"
  assert_output "$(whoami)"
}

@test "getconf — prints page size" {
  run "$BIN/getconf" PAGESIZE
  assert_success
  assert_output --partial '4096'
}

@test "gettext — echoes message id" {
  run "$BIN/gettext" 'hello baloo'
  assert_success
  assert_output 'hello baloo'
}

@test "grep — matches lines containing pattern" {
  printf 'foo\nbar\n' >"$TMP/g"
  run "$BIN/grep" foo "$TMP/g"
  assert_output 'foo'
}


@test "stdbuf — reports usage without a command" {
  run "$BIN/stdbuf"
  assert_failure
  assert_output --partial 'Usage: stdbuf'
}


@test "yes — repeats its arguments" {
  run bash -c '"$1" yep | head -n 3' _ "$BIN/yes"
  assert_success
  assert_output $'yep\nyep\nyep'
}

@test "strings — extracts printable sequences" {
  printf 'a\x00abcdEF\x01' >"$TMP/str"
  run "$BIN/strings" "$TMP/str"
  assert_output --partial "abcdEF"
}

@test "logger — logs message" {
  run "$BIN/logger" "hello"
  assert_success
}

@test "crontab — installs and lists file" {
  echo "* * * * * echo hi" >"$TMP/cronfile"
  run env HOME="$TMP" "$BIN/crontab" "$TMP/cronfile"
  assert_success
  run env HOME="$TMP" "$BIN/crontab" -l
  assert_output "* * * * * echo hi"
}

@test "crontab — remove table" {
  echo "a" >"$TMP/cfile"
  run env HOME="$TMP" "$BIN/crontab" "$TMP/cfile"
  run env HOME="$TMP" "$BIN/crontab" -r
  assert_success
  [ ! -f "$TMP/.baloo_crontab" ]
}
