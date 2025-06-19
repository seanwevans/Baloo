#!/usr/bin/env bats
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Directory with Baloo binaries ------------------------------------------------
setup()  { BIN="${BATS_TEST_DIRNAME}/../bin"; TMP=$(mktemp -d); }
teardown(){ rm -rf "$TMP"; }

# ----------  SINGLE‑TEST SMOKE CHECKS FOR EVERY ✅ PROGRAM ---------- #

@test "arch — prints hardware name" {
  run "$BIN/arch"
  assert_success
  assert_output "$(uname -m)"
}

@test "base64 — encodes stdin" {
  printf 'hi' | run "$BIN/base64"
  assert_success
  assert_output 'aGk='
}
@test "batch — runs stdin script" {
  echo "echo hi" | run "$BIN/batch"
  assert_success
  assert_output "hi"
}


@test "base32 — encodes stdin" {
  printf 'hello' | run "$BIN/base32"
  assert_success
  assert_output 'NBSWY3DP'
}

@test "basename — strips directories" {
  run "$BIN/basename" "/usr/local/bin/foo"
  assert_output "foo"
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

@test "chgrp — changes group ownership" {  
  touch "$TMP/testfile"    
  current_group=$(id -g)    
  run "$BIN/chgrp" "$current_group" "$TMP/testfile"
  assert_success    
  file_group=$(stat -c %g "$TMP/testfile")
  assert_equal "$file_group" "$current_group"
}

@test "chmod — changes mode" {
  touch "$TMP/f"
  run "$BIN/chmod" 600 "$TMP/f"
  assert_success
  run stat -c %a "$TMP/f"
  assert_output '600'
}

@test "chown — (non‑root) returns EPERM" {
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
  (sleep 30 &); pid=$!
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
  run "$BIN/logname"
  assert_output "$(logname)"
}

@test "ls — current directory listing contains test file" {
  touch "$TMP/zzz"
  pushd "$TMP" >/dev/null
  run "$BIN/ls"
  popd >/dev/null
  assert_output --partial "zzz"
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

@test "nproc — ≥ 1" {
  run "$BIN/nproc"
  assert_success
  [[ "$output" -ge 1 ]]
}

@test "printenv — returns PATH value" {
  run "$BIN/printenv" PATH
  assert_output "$PATH"
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

@test "tail — last line only" {
  printf '1\n2\n3\n' >"$TMP/l"
  run "$BIN/tail" -n 1 "$TMP/l"
  assert_output '3'
}

@test "tee — duplicates stdin to file" {
  run bash -c "echo hi | \"$BIN/tee\" \"$TMP/out\""
  assert_success
  assert_equal "$(cat "$TMP/out")" "hi"
}

@test "touch — creates empty file" {
  run "$BIN/touch" "$TMP/new"
  assert_success
  assert [ -f "$TMP/new" ]
}

@test "tr — character translation" {
  printf 'abc' | run "$BIN/tr" 'a-c' 'A-C'
  assert_output 'ABC'
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

@test "uniq — removes duplicate lines" {
  printf 'x\nx\ny\n' | run "$BIN/uniq"
  assert_output $'x\ny'
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

@test "users — prints current user" {
  run "$BIN/users"
  assert_output --partial "$(whoami)"
}

@test "wc — counts lines" {
  printf 'a\nb\n' >"$TMP/w"
  run "$BIN/wc" -l "$TMP/w"
  assert_output "2 $TMP/w"
}

@test "who — lists users" {
  run "$BIN/who"
  assert_success
}

@test "whoami — matches whoami(1)" {
  run "$BIN/whoami"
  assert_output "$(whoami)"
}

@test "yes — stops after 3 lines with head" {
  run bash -c "\"$BIN/yes\" | head -n 3"
  assert_success
  [ "$(echo \"$output\" | wc -l)" -eq 3 ]
}

@test "logger — logs message" {
  run "$BIN/logger" "hello"
  assert_success
}
