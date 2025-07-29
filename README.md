# Baloo 🐻 

![Progress](https://img.shields.io/badge/progress-67%2F154%20done-brightgreen) ![Build Status](https://github.com/seanwevans/baloo/actions/workflows/makefile.yml/badge.svg)

Just the bear utilities in x86_64 assembly using direct syscalls only — no libc or dependencies.
<center><img src="assets/Baloo.jpg" title=" भालू "></img></center>

## 🛠 Build Instructions
simply run
```
make
```
or
```
nasm -f elf64 <input_file.asm> -o <output_binary_name>.o
ld -o <output_binary_name> <output_binary_name>.o
```
for whichever `.asm` in `src` you want to compile.

## 🧪 Testing
Install `bats`, `bats-assert`, and `bats-support` then run:
```make test```

## 📐 Formatting

Use `scripts/asmfmt.py` to keep assembly files consistent. By default it indents instructions with four spaces and aligns comments to column 40.
python3 scripts/asmfmt.py src/example.asm

## Catalog
- [`alias`](src/alias.asm) ✅ Defines or displays aliases
- [`ar`](src/ar.asm) ✅ Creates and maintains libraries
- [`arch`](src/arch.asm) ✅ Prints machine hardware name
- [`at`](src/at.asm) ✅ Executes commands at a later time
- [`awk`](src/awk.asm) ⛔️ Pattern scanning and processing language
- [`b2sum`](src/b2sum.asm) ✅ Computes and checks BLAKE2b message digest
 - [`base32`](src/base32.asm) ⛔️ Encodes or decodes Base32, and prints result to standard output
- [`base64`](src/base64.asm) ⛔️ Prints a file's contents in Base64 to standard output
- [`basename`](src/basename.asm) ✅ Removes the path prefix from a given pathname
- [`baseenc`](src/baseenc.asm) ✅ Encodes or decodes various encodings and prints result to standard output
 - [`batch`](src/batch.asm) ⛔️ Schedules commands to be executed in a batch queue
- [`bc`](src/bc.asm) ✅ Arbitrary-precision arithmetic language
- [`cat`](src/cat.asm) ✅ Concatenates and prints files
- [`cd`](src/cd.asm) ✅ Changes the working directory
 - [`chcon`](src/chcon.asm) ✅ Changes file security context
- [`chgrp`](src/chgrp.asm) ⛔️ Changes file group ownership
- [`chmod`](src/chmod.asm) ⛔️ Changes the permissions of a file or directory
 - [`chown`](src/chown.asm) ⛔️ Changes file ownership
 - [`chroot`](src/chroot.asm) ✅ Changes the root directory
- [`cksum`](src/cksum.asm) ⛔️ Checksums (IEEE Ethernet CRC-32) and count the bytes in a file
- [`cmp`](src/cmp.asm) ⛔️ Compares two files; see also diff
- [`comm`](src/comm.asm) ⛔️ Compares two sorted files line by line
- [`command`](src/command.asm) ✅ Executes a simple command
- [`cp`](src/cp.asm) ✅ Copy files/directories
- [`crontab`](src/crontab.asm) ⛔️ Schedule periodic background work
- [`csplit`](src/csplit.asm) ✅ Splits a file into sections determined by context lines
 - [`cut`](src/cut.asm) ⛔️ Removes sections from each line of files
- [`date`](src/date.asm) ✅ Sets or displays the date and time
- [`dd`](src/dd.asm) ⛔️ Copies and converts a file
- [`df`](src/df.asm) ✅ Shows disk free space on file systems
- [`diff`](src/diff.asm) ⛔️ Compare two files; see also cmp
- [`dircolors`](src/dircolors.asm) ✅ Set up color for ls
- [`dirname`](src/dirname.asm) ✅ Strips non-directory suffix from file name
- [`du`](src/du.asm) ⛔️ Shows disk usage on file systems
- [`echo`](src/echo.asm) ✅ Displays a specified line of text
- [`ed`](src/ed.asm) ⛔️ The standard text editor
- [`env`](src/env.asm) ⛔️ Run a program in a modified environment
 - [`expand`](src/expand.asm) ⛔️ Converts tabs to spaces
- [`expr`](src/expr.asm) ✅ Evaluates expressions
- [`factor`](src/factor.asm) ✅ Factors numbers
- [`false`](src/false.asm) ✅ Does nothing, but exits unsuccessfully
- [`file`](src/file.asm) ⛔️ Determine file type
- [`find`](src/find.asm) ✅ Find files
- [`fmt`](src/fmt.asm) ✅ Simple optimal text formatter
- [`fold`](src/fold.asm) ⛔️ Wraps each input line to fit in specified width
- [`gencat`](src/gencat.asm) ✅ Generate a formatted message catalog
- [`getconf`](src/getconf.asm) ✅ Get configuration values
- [`getopts`](src/getopts.asm) ✅ Parse utility options
- [`gettext`](src/gettext.asm) ⛔️ Retrieve text string from messages object
- [`grep`](src/grep.asm) ✅ Search text for a pattern
- [`groups`](src/groups.asm) ⛔️ Prints the groups of which the user is a member
- [`hash`](src/hash.asm) ✅ Hash database access method
- [`head`](src/head.asm) ✅ Output the beginning of files
- [`hostid`](src/hostid.asm) ✅ Prints the numeric identifier for the current host
- [`iconv`](src/iconv.asm) ⛔️ Codeset conversion
- [`id`](src/id.asm) ✅ Prints real or effective UID and GID
- [`install`](src/install.asm) ⛔️ Copies files and set attributes
- [`join`](src/join.asm) ✅ Merges two sorted text files based on the presence of a common field
- [`kill`](src/kill.asm) ⛔️ Terminate or signal processes
- [`link`](src/link.asm) ⛔️ Creates a link to a file
- [`ln`](src/ln.asm) ✅ Creates a link to a file
- [`locale`](src/locale.asm) ✅ Get locale-specific information
- [`localedef`](src/localedef.asm) ⛔️ Define locale environment
- [`logger`](src/logger.asm) ✅ Log messages
- [`logname`](src/logname.asm) ✅ Print the user's login name
- [`lp`](src/lp.asm) ⛔️ Send files to a printer
- [`ls`](src/ls.asm) ⛔️ List directory contents with formatting
- [`m4`](src/m4.asm) ✅ Macro processor
- [`mailx`](src/mailx.asm) ⛔️ Process messages
- [`man`](src/man.asm) ⛔️ Display system documentation
- [`md5sum`](src/md5sum.asm) ✅ Computes and checks MD5 message digest
- [`mesg`](src/mesg.asm) ⛔️ Permit or deny messages
- [`mkdir`](src/mkdir.asm) ✅ Creates directories
- [`mkfifo`](src/mkfifo.asm) ⛔️ Makes named pipes (FIFOs)
- [`mknod`](src/mknod.asm) ⛔️ Makes block or character special files
- [`mktemp`](src/mktemp.asm) ⛔️ Creates a temporary file or directory
- [`msgfmt`](src/msgfmt.asm) ⛔️ Create messages objects from messages object files
- [`mv`](src/mv.asm) ⛔️ Moves files or rename files
- [`newgrp`](src/newgrp.asm) ⛔️ Change to a new group
- [`ngettext`](src/ngettext.asm) ⛔️ Retrieve text string from messages object with plural form
- [`nice`](src/nice.asm) ✅ Modifies scheduling priority
- [`nl`](src/nl.asm) ⛔️ Numbers lines of files
- [`nohup`](src/nohup.asm) ✅ Allows a command to continue running after logging out
- [`nproc`](src/nproc.asm) ✅ Queries the number of (active) processors
- [`numfmt`](src/numfmt.asm) ✅ Reformat numbers
- [`od`](src/od.asm) ⛔️ Dumps files in octal and other formats
- [`paste`](src/paste.asm) ⛔️ Merge corresponding or subsequent lines of files
- [`patch`](src/patch.asm) ⛔️ Apply changes to files
- [`pathchk`](src/pathchk.asm) ⛔️ Checks whether file names are valid or portable
- [`pax`](src/pax.asm) ⛔️ Portable archive interchange
- [`pinky`](src/pinky.asm) ⛔️ A lightweight version of finger
- [`pr`](src/pr.asm) ⛔️ Paginate or columnate files for printing
- [`printenv`](src/printenv.asm) ✅ Prints environment variables
- [`printf`](src/printf.asm) ⛔️ Formats and prints data
- [`ps`](src/ps.asm) ⛔️ Report process status
- [`ptx`](src/ptx.asm) ⛔️ Produces a permuted index of file contents
- [`pwd`](src/pwd.asm) ✅ Prints the current working directory
- [`read`](src/read.asm) ⛔️ Read a line from standard input
- [`readlink`](src/readlink.asm) ⛔️ Print destination of a symbolic link
- [`realpath`](src/realpath.asm) ⛔️ Returns the resolved absolute or relative path for a file
- [`renice`](src/renice.asm) ✅ Set nice values of running processes
- [`rm`](src/rm.asm) ⛔️ Removes files/directories
- [`rmdir`](src/rmdir.asm) ✅ Removes empty directories
- [`runcon`](src/runcon.asm) ⛔️ Run command with specified security context
- [`sed`](src/sed.asm) ⛔️ Stream editor
- [`seq`](src/seq.asm) ✅ Prints a sequence of numbers
- [`sh`](src/sh.asm) ⛔️ Shell, the standard command language interpreter
- [`sha1sum`](src/sha1sum.asm) ⛔️ Computes and checks SHA-1/SHA-2 message digests
- [`sha224sum`](src/sha224sum.asm) ⛔️ Computes and checks SHA-1/SHA-2 message digests
- [`sha256sum`](src/sha256sum.asm) ⛔️ Computes and checks SHA-1/SHA-2 message digests
- [`sha384sum`](src/sha384sum.asm) ⛔️ Computes and checks SHA-1/SHA-2 message digests
- [`sha512sum`](src/sha512sum.asm) ⛔️ Computes and checks SHA-1/SHA-2 message digests
- [`shred`](src/shred.asm) ✅ Overwrites a file to hide its contents, and optionally deletes it
- [`shuf`](src/shuf.asm) ⛔️ generates random permutations
- [`sleep`](src/sleep.asm) ✅ Delays for a specified amount of time
- [`sort`](src/sort.asm) ⛔️ Sorts lines of text files
- [`split`](src/split.asm) ✅ Splits a file into pieces
- [`stat`](src/stat.asm) ⛔️ Returns data about an inode
- [`stdbuf`](src/stdbuf.asm) ⛔️ Controls buffering for commands that use stdio
- [`strings`](src/strings.asm) ✅ Find printable strings in files
- [`stty`](src/stty.asm) ⛔️ Changes and prints terminal line settings
- [`sum`](src/sum.asm) ✅ Checksums and counts the blocks in a file
- [`sync`](src/sync.asm) ✅ Flushes file system buffers
- [`tabs`](src/tabs.asm) ✅ Set terminal tabs
- [`tac`](src/tac.asm) ⛔️ Concatenates and prints files in reverse order line by line
- [`tail`](src/tail.asm) ✅ Output the end of files
- [`tee`](src/tee.asm) ✅ Sends output to multiple files
- [`test`](src/test.asm) ⛔️ Evaluates an expression
- [`time`](src/time.asm) ⛔️ Display elapsed, system and kernel time used by the current shell or designated process.
- [`timeout`](src/timeout.asm) ✅ Runs a command with a time limit
- [`touch`](src/touch.asm) ✅ Changes file timestamps; creates file
- [`tput`](src/tput.asm) ⛔️ Change terminal characteristics
- [`tr`](src/tr.asm) ✅ Translates or deletes characters
- [`true`](src/true.asm) ✅ Does nothing, but exits successfully
- [`truncate`](src/truncate.asm) ✅ Shrink the size of a file to the specified size
- [`tsort`](src/tsort.asm) ✅ Performs a topological sort
- [`tty`](src/tty.asm) ✅ Prints terminal name
- [`umask`](src/umask.asm) ✅ Get or set the file mode creation mask
 - [`unalias`](src/unalias.asm) ✅ Remove alias definitions
- [`uname`](src/uname.asm) ✅ Prints system information
- [`unexpand`](src/unexpand.asm) ✅ Converts spaces to tabs
- [`uniq`](src/uniq.asm) ✅ Removes duplicate lines from a sorted file
- [`unlink`](src/unlink.asm) ⛔️ Removes the specified file using the unlink function
- [`uptime`](src/uptime.asm) ✅ Tells how long the system has been running
- [`users`](src/users.asm) ⛔️ Prints the user names of users currently logged into the current host
- [`uudecode`](src/uudecode.asm) ✅ Decode a binary file
- [`uuencode`](src/uuencode.asm) ⛔️ Encode a binary file
- [`wait`](src/wait.asm) ✅ Await process completion
- [`wc`](src/wc.asm) ✅ Prints the number of bytes, words, and lines in files
- [`who`](src/who.asm) ✅ Prints a list of all users currently logged in
- [`whoami`](src/whoami.asm) ✅ Prints the effective userid
- [`write`](src/write.asm) ⛔️ Write to another user's terminal
- [`xargs`](src/xargs.asm) ⛔️ Construct argument lists and invoke utility
- [`yes`](src/yes.asm) ✅ Prints a string repeatedly

## Benchmark
Run `make` to build all binaries, then execute `./benchmark.sh` to compare a few Baloo programs against the system implementations using `hyperfine`.

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
