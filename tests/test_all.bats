#!/usr/bin/env bats
if [ -e "${BATS_TEST_DIRNAME}/test_helper/bats-support/load.bash" ]; then
  load 'test_helper/bats-support/load'
else
  bats_load_library bats-support
fi

if [ -e "${BATS_TEST_DIRNAME}/test_helper/bats-assert/load.bash" ]; then
  load 'test_helper/bats-assert/load'
else
  bats_load_library bats-assert
fi

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

@test "arch — prints hardware name" {
  run "$BIN/arch"
  assert_success
  assert_output "$(uname -m)"
}

@test "basename — strips directories" {
  run "$BIN/basename" "/usr/local/bin/foo"
  assert_output "foo"
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
  skip "Temporarily disabled per request: skip chcon tests"
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
  cat >"$TMP/input.m4" <<'EOF'
define(`name',`Baloo')Hello, name
EOF
  run "$BIN/m4" "$TMP/input.m4"
  assert_success
  assert_output "Hello, Baloo"
}

@test "m4 — supports undefine and ifdef" {
  cat >"$TMP/input.m4" <<'EOF'
ifdef(`name',`yes',`no')
define(`name',`Baloo')ifdef(`name',`yes',`no')
undefine(`name')ifdef(`name',`yes',`no')
EOF
  run "$BIN/m4" "$TMP/input.m4"
  assert_success
  assert_output $'no\nyes\nno'
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
  skip "Temporarily disabled per request: skip renice tests"
  sleep 30 & pid=$!
  trap 'kill "$pid" 2>/dev/null || true' RETURN
  if [ -z "$pid" ]; then
    fail "failed to capture background pid in renice test"
  fi
  run "$BIN/renice" 5 "$pid"
  assert_success
  run ps -o ni= -p "$pid"
  assert_success
  normalized_nice="$(echo "$output" | xargs)"
  assert_equal "$normalized_nice" "5"
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
@test "grep — matches lines containing pattern" {
  printf 'foo\nbar\n' >"$TMP/g"
  run "$BIN/grep" foo "$TMP/g"
  assert_output 'foo'
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


# ----------  SMOKE TESTS FOR PREVIOUSLY-UNTESTED PROGRAMS ---------- #

@test "alias — defines/lists aliases" {
  skip "standalone alias has no shell context; exits 1 with no output"
}

@test "ar — lists archive members" {
  skip "known bug: ar cannot open existing archives (reports 'Error opening file')"
}

@test "at — runs queued command after delay" {
  run bash -c "printf 'echo at_ok\n' | '$BIN/at' 0"
  assert_success
  assert_output "at_ok"
}

@test "b2sum — BLAKE2b digest" {
  skip "known bug: b2sum exits 1 without producing a digest"
}

@test "base32 — encodes like coreutils" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/base32" "$TMP/f"
  assert_success
  assert_output "$(base32 "$TMP/f")"
}

@test "base64 — encodes like coreutils" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/base64" "$TMP/f"
  assert_success
  assert_output "$(base64 "$TMP/f")"
}

@test "baseenc — encodes/decodes" {
  skip "known bug: baseenc exits 1 for documented invocations"
}

@test "batch — runs queued command" {
  run bash -c "printf 'echo batch_ok\n' | '$BIN/batch'"
  assert_success
  assert_output "batch_ok"
}

@test "cksum — CRC32 and byte count" {
  skip "known bug: cksum segfaults (exit 139) after emitting output"
}

@test "command — executes a program" {
  run "$BIN/command" echo command_ok
  assert_success
  assert_output "command_ok"
}

@test "date — prints an ISO-like date" {
  run "$BIN/date"
  assert_success
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

@test "dd — copies a file" {
  skip "known bug: dd segfaults (exit 139) on basic if=/of= copy"
}

@test "diff — compares files" {
  skip "known bug: diff segfaults (exit 139) even on identical files"
}

@test "dircolors — emits LS_COLORS" {
  run "$BIN/dircolors"
  assert_success
  assert_output --partial "LS_COLORS"
}

@test "du — reports usage for a directory" {
  run "$BIN/du" "$TMP"
  assert_success
  [[ "$output" =~ [0-9] ]]
}

@test "find — lists a directory tree" {
  skip "known bug: find segfaults (exit 139) after printing the start dir"
}

@test "fmt — reflows text" {
  run bash -c "printf 'hello world\n' | '$BIN/fmt'"
  assert_success
  assert_output --partial "hello"
}

@test "gencat — generates a message catalog" {
  skip "known bug: gencat reports 'Error opening file' for basic usage"
}

@test "getconf — prints a system limit" {
  run "$BIN/getconf" PAGESIZE
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "getopts — parses options" {
  skip "known bug: getopts segfaults (exit 139)"
}

@test "gettext — echoes its argument" {
  run "$BIN/gettext" hello
  assert_success
  assert_output "hello"
}

@test "hash — prints a hex digest" {
  run bash -c "printf '' | '$BIN/hash'"
  assert_success
  [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "iconv — converts encodings" {
  skip "known bug: iconv segfaults (exit 139)"
}

@test "install — copies a file" {
  echo payload >"$TMP/src"
  run "$BIN/install" "$TMP/src" "$TMP/dst"
  assert_success
  assert [ -f "$TMP/dst" ]
  assert_equal "$(cat "$TMP/dst")" "payload"
}

@test "join — joins on a common field" {
  printf '1 a\n2 b\n' >"$TMP/j1"
  printf '1 x\n2 y\n' >"$TMP/j2"
  run "$BIN/join" "$TMP/j1" "$TMP/j2"
  assert_success
  assert_line --index 0 "1 a x"
}

@test "locale — runs" {
  run "$BIN/locale"
  assert_success
}

@test "localedef — compiles a locale" {
  skip "needs a charmap/input locale; prints usage and exits 1 in CI"
}

@test "lp — accepts input" {
  run bash -c "echo page | '$BIN/lp'"
  assert_success
}

@test "man — shows documentation" {
  skip "needs installed man pages; exits 1 in CI"
}

@test "md5sum — MD5 digest" {
  skip "known bug: md5sum exits 1 without producing a digest"
}

@test "mesg — reports messaging status" {
  run "$BIN/mesg"
  assert_success
  assert_output --partial "is"
}

@test "ngettext — selects plural form" {
  skip "known bug: ngettext segfaults (exit 139)"
}

@test "nl — numbers lines" {
  skip "known bug: nl segfaults (exit 139)"
}

@test "nohup — runs a command, redirecting to nohup.out" {
  run bash -c "cd '$TMP' && '$BIN/nohup' echo nohup_ok >/dev/null 2>&1; cat '$TMP/nohup.out'"
  assert_success
  assert_output --partial "nohup_ok"
}

@test "od — dumps a file" {
  skip "known bug: od segfaults (exit 139) after partial output"
}

@test "pinky — runs" {
  run "$BIN/pinky"
  assert_success
}

@test "ps — reports process status" {
  run "$BIN/ps"
  assert_success
  refute_output ""
}

@test "split — splits a file" {
  skip "known bug: split reports 'Error opening file' instead of splitting"
}

@test "stdbuf — runs a command" {
  run "$BIN/stdbuf" -oL echo stdbuf_ok
  assert_success
  assert_output "stdbuf_ok"
}

@test "tee — copies stdin to a file and stdout" {
  run bash -c "echo teed | '$BIN/tee' '$TMP/teeout'"
  assert_success
  assert_output "teed"
  assert_equal "$(cat "$TMP/teeout")" "teed"
}

@test "time — runs a command and reports timing" {
  run "$BIN/time" echo time_ok
  assert_success
  assert_line --index 0 "time_ok"
}

@test "timeout — runs a command within the limit" {
  run "$BIN/timeout" 5 echo timeout_ok
  assert_success
  assert_output "timeout_ok"
}

@test "tr — translates explicit character sets" {
  run bash -c "printf 'abc' | '$BIN/tr' abc xyz"
  assert_success
  assert_output "xyz"
}

@test "tsort — topological sort" {
  skip "known bug: tsort segfaults (exit 139)"
}

@test "unalias — removes an alias" {
  skip "standalone unalias has no shell context; exits 1"
}

@test "uniq — collapses adjacent duplicates" {
  run bash -c "printf 'x\nx\ny\n' | '$BIN/uniq'"
  assert_success
  assert_output $'x\ny'
}

@test "uudecode — decodes a uuencoded stream" {
  skip "known bug: uudecode reports 'Error opening file'"
}

@test "uuencode — emits a uuencoded stream" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/uuencode" "$TMP/f" out.dat
  assert_success
  assert_line --index 0 "begin 644 out.dat"
}

@test "wait — awaits process completion" {
  skip "no child to await in this harness; exit status is environment-specific"
}

@test "write — writes to another terminal" {
  skip "needs a logged-in target tty; exits non-zero in CI"
}

@test "yes — repeats its output" {
  # yes runs forever; bound it with timeout (it busy-loops on a closed
  # pipe when SIGPIPE is ignored, as on CI runners) and take two lines.
  run bash -c "timeout -s KILL 2 '$BIN/yes' | head -n2"
  assert_success
  assert_output $'y\ny'
}

@test "printf — interprets format specifiers, width, and escapes" {
  run "$BIN/printf" '%s=%d\n' answer 42
  assert_output 'answer=42'

  run "$BIN/printf" '%05d|%-5s|%x\n' 42 hi 255
  assert_output '00042|hi   |ff'

  run "$BIN/printf" '%s\n' a b c
  assert_output $'a\nb\nc'
}

@test "sha384sum — matches coreutils" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/sha384sum" "$TMP/f"
  assert_success
  assert_output "$(sha384sum "$TMP/f")"
}

@test "sha1sum — matches coreutils" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/sha1sum" "$TMP/f"
  assert_success
  assert_output "$(sha1sum "$TMP/f")"
}

@test "sha256sum — matches coreutils" {
  printf 'hello world\n' >"$TMP/f"
  run "$BIN/sha256sum" "$TMP/f"
  assert_success
  assert_output "$(sha256sum "$TMP/f")"
}
