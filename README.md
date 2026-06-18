# 🐻 Baloo  ![Progress](https://img.shields.io/badge/progress-150%2F150%20done-brightgreen) ![Build Status](https://github.com/seanwevans/baloo/actions/workflows/Baloo.yml/badge.svg)

Just the bare utilities in x86_64 assembly using direct syscalls only. No libc or dependencies.

I was tired of seeing

<img alt="'strace usr/bin/true' output" src="https://github.com/user-attachments/assets/be6b408b-c922-411f-ae68-2a9de0ea70e0" />

When I should be seeing

<img alt="'strace Baloo/bin/true' output" src="https://github.com/user-attachments/assets/ca5c42ed-33ea-405b-9d39-c97396ee827c" />


So I built

## Catalog

| Emoji | Name | Description | Status | Source |
| :---: | --- | --- | :---: | --- |
| 🏷️ | [`alias`](src/alias.asm) | Defines or displays aliases | ✅ Done | [`src/alias.asm`](src/alias.asm) |
| 🗄️ | [`ar`](src/ar.asm) | Creates and maintains libraries | ✅ Done | [`src/ar.asm`](src/ar.asm) |
| 🏗️ | [`arch`](src/arch.asm) | Prints machine hardware name | ✅ Done | [`src/arch.asm`](src/arch.asm) |
| ⏰ | [`at`](src/at.asm) | Executes commands at a later time | ✅ Done | [`src/at.asm`](src/at.asm) |
| 🧪 | [`b2sum`](src/b2sum.asm) | Computes and checks BLAKE2b message digest | ✅ Done | [`src/b2sum.asm`](src/b2sum.asm) |
| 3️⃣ | [`base32`](src/base32.asm) | Encodes or decodes Base32, and prints result to standard output | ✅ Done | [`src/base32.asm`](src/base32.asm) |
| 6️⃣ | [`base64`](src/base64.asm) | Encodes or decodes Base64, and prints result to standard output | ✅ Done | [`src/base64.asm`](src/base64.asm) |
| 🔤 | [`basename`](src/basename.asm) | Removes the path prefix from a given pathname | ✅ Done | [`src/basename.asm`](src/basename.asm) |
| 🔡 | [`baseenc`](src/baseenc.asm) | Encodes or decodes various encodings and prints result to standard output | ✅ Done | [`src/baseenc.asm`](src/baseenc.asm) |
| 📚 | [`batch`](src/batch.asm) | Schedules commands to be executed in a batch queue | ✅ Done | [`src/batch.asm`](src/batch.asm) |
| 🧮 | [`bc`](src/bc.asm) | Arbitrary-precision arithmetic language | ✅ Done | [`src/bc.asm`](src/bc.asm) |
| 🐱 | [`cat`](src/cat.asm) | Concatenates and prints files | ✅ Done | [`src/cat.asm`](src/cat.asm) |
| 🚶 | [`cd`](src/cd.asm) | Changes the working directory | ✅ Done | [`src/cd.asm`](src/cd.asm) |
| 🛡️ | [`chcon`](src/chcon.asm) | Changes file security context | ✅ Done | [`src/chcon.asm`](src/chcon.asm) |
| 👥 | [`chgrp`](src/chgrp.asm) | Changes file group ownership | ✅ Done | [`src/chgrp.asm`](src/chgrp.asm) |
| 🔒 | [`chmod`](src/chmod.asm) | Changes the permissions of a file or directory | ✅ Done | [`src/chmod.asm`](src/chmod.asm) |
| 🔐 | [`chown`](src/chown.asm) | Changes file ownership | ✅ Done | [`src/chown.asm`](src/chown.asm) |
| 🌱 | [`chroot`](src/chroot.asm) | Changes the root directory | ✅ Done | [`src/chroot.asm`](src/chroot.asm) |
| 🧾 | [`cksum`](src/cksum.asm) | Checksums (IEEE Ethernet CRC-32) and count the bytes in a file | ✅ Done | [`src/cksum.asm`](src/cksum.asm) |
| 🔬 | [`cmp`](src/cmp.asm) | Compares two files; see also diff | ✅ Done | [`src/cmp.asm`](src/cmp.asm) |
| ☯️ | [`comm`](src/comm.asm) | Compares two sorted files line by line | ✅ Done | [`src/comm.asm`](src/comm.asm) |
| ⚡ | [`command`](src/command.asm) | Executes a simple command | ✅ Done | [`src/command.asm`](src/command.asm) |
| 📑 | [`cp`](src/cp.asm) | Copy files/directories | ✅ Done | [`src/cp.asm`](src/cp.asm) |
| 🗓️ | [`crontab`](src/crontab.asm) | Schedule periodic background work | ✅ Done | [`src/crontab.asm`](src/crontab.asm) |
| 📂 | [`csplit`](src/csplit.asm) | Splits a file into sections determined by context lines | ✅ Done | [`src/csplit.asm`](src/csplit.asm) |
| ✂️ | [`cut`](src/cut.asm) | Removes sections from each line of files | ✅ Done | [`src/cut.asm`](src/cut.asm) |
| 📅 | [`date`](src/date.asm) | Sets or displays the date and time | ✅ Done | [`src/date.asm`](src/date.asm) |
| 💾 | [`dd`](src/dd.asm) | Copies and converts a file | ✅ Done | [`src/dd.asm`](src/dd.asm) |
| 💽 | [`df`](src/df.asm) | Shows disk free space on file systems | ✅ Done | [`src/df.asm`](src/df.asm) |
| 🔍 | [`diff`](src/diff.asm) | Compare two files; see also cmp | ✅ Done | [`src/diff.asm`](src/diff.asm) |
| 🎨 | [`dircolors`](src/dircolors.asm) | Set up color for ls | ✅ Done | [`src/dircolors.asm`](src/dircolors.asm) |
| 📁 | [`dirname`](src/dirname.asm) | Strips non-directory suffix from file name | ✅ Done | [`src/dirname.asm`](src/dirname.asm) |
| 📊 | [`du`](src/du.asm) | Shows disk usage on file systems | ✅ Done | [`src/du.asm`](src/du.asm) |
| 🗣️ | [`echo`](src/echo.asm) | Displays a specified line of text | ✅ Done | [`src/echo.asm`](src/echo.asm) |
| 🌐 | [`env`](src/env.asm) | Run a program in a modified environment | ✅ Done | [`src/env.asm`](src/env.asm) |
| ➡️ | [`expand`](src/expand.asm) | Converts tabs to spaces | ✅ Done | [`src/expand.asm`](src/expand.asm) |
| 📊 | [`expr`](src/expr.asm) | Evaluates expressions | ✅ Done | [`src/expr.asm`](src/expr.asm) |
| 🔢 | [`factor`](src/factor.asm) | Factors numbers | ✅ Done | [`src/factor.asm`](src/factor.asm) |
| ❌ | [`false`](src/false.asm) | Does nothing, but exits unsuccessfully | ✅ Done | [`src/false.asm`](src/false.asm) |
| 📎 | [`file`](src/file.asm) | Determine file type | ✅ Done | [`src/file.asm`](src/file.asm) |
| 🔎 | [`find`](src/find.asm) | Find files | ✅ Done | [`src/find.asm`](src/find.asm) |
| 📐 | [`fmt`](src/fmt.asm) | Simple optimal text formatter | ✅ Done | [`src/fmt.asm`](src/fmt.asm) |
| 📃 | [`fold`](src/fold.asm) | Wraps each input line to fit in specified width | ✅ Done | [`src/fold.asm`](src/fold.asm) |
| 😺 | [`gencat`](src/gencat.asm) | Generate a formatted message catalog | ✅ Done | [`src/gencat.asm`](src/gencat.asm) |
| ⚙️ | [`getconf`](src/getconf.asm) | Get configuration values | ✅ Done | [`src/getconf.asm`](src/getconf.asm) |
| 🔣 | [`getopts`](src/getopts.asm) | Parse utility options | ✅ Done | [`src/getopts.asm`](src/getopts.asm) |
| 💬 | [`gettext`](src/gettext.asm) | Retrieve text string from messages object | ✅ Done | [`src/gettext.asm`](src/gettext.asm) |
| 🔦 | [`grep`](src/grep.asm) | Search text for a pattern | ✅ Done | [`src/grep.asm`](src/grep.asm) |
| 👪 | [`groups`](src/groups.asm) | Prints the groups of which the user is a member | ✅ Done | [`src/groups.asm`](src/groups.asm) |
| 🔐 | [`hash`](src/hash.asm) | Hash database access method | ✅ Done | [`src/hash.asm`](src/hash.asm) |
| ⬆️ | [`head`](src/head.asm) | Output the beginning of files | ✅ Done | [`src/head.asm`](src/head.asm) |
| 🏷️ | [`hostid`](src/hostid.asm) | Prints the numeric identifier for the current host | ✅ Done | [`src/hostid.asm`](src/hostid.asm) |
| 🔄 | [`iconv`](src/iconv.asm) | Codeset conversion | ✅ Done | [`src/iconv.asm`](src/iconv.asm) |
| 🆔 | [`id`](src/id.asm) | Prints real or effective UID and GID | ✅ Done | [`src/id.asm`](src/id.asm) |
| 📥 | [`install`](src/install.asm) | Copies files and set attributes | ✅ Done | [`src/install.asm`](src/install.asm) |
| 🔗 | [`join`](src/join.asm) | Merges two sorted text files based on the presence of a common field | ✅ Done | [`src/join.asm`](src/join.asm) |
| 💀 | [`kill`](src/kill.asm) | Terminate or signal processes | ✅ Done | [`src/kill.asm`](src/kill.asm) |
| 🔗 | [`link`](src/link.asm) | Creates a link to a file | ✅ Done | [`src/link.asm`](src/link.asm) |
| 🖇️ | [`ln`](src/ln.asm) | Creates a link to a file | ✅ Done | [`src/ln.asm`](src/ln.asm) |
| 🌍 | [`locale`](src/locale.asm) | Get locale-specific information | ✅ Done | [`src/locale.asm`](src/locale.asm) |
| 🌐 | [`localedef`](src/localedef.asm) | Define locale environment | ✅ Done | [`src/localedef.asm`](src/localedef.asm) |
| 📓 | [`logger`](src/logger.asm) | Log messages | ✅ Done | [`src/logger.asm`](src/logger.asm) |
| 👤 | [`logname`](src/logname.asm) | Print the user's login name | ✅ Done | [`src/logname.asm`](src/logname.asm) |
| 🖨️ | [`lp`](src/lp.asm) | Send files to a printer | ✅ Done | [`src/lp.asm`](src/lp.asm) |
| 📋 | [`ls`](src/ls.asm) | List directory contents with formatting | ✅ Done | [`src/ls.asm`](src/ls.asm) |
| 🔁 | [`m4`](src/m4.asm) | Macro processor | ✅ Done | [`src/m4.asm`](src/m4.asm) |
| 📧 | [`mailx`](src/mailx.asm) | Process messages | ✅ Done | [`src/mailx.asm`](src/mailx.asm) |
| 📚 | [`man`](src/man.asm) | Display system documentation | ✅ Done | [`src/man.asm`](src/man.asm) |
| 🔑 | [`md5sum`](src/md5sum.asm) | Computes and checks MD5 message digest | ✅ Done | [`src/md5sum.asm`](src/md5sum.asm) |
| 📨 | [`mesg`](src/mesg.asm) | Permit or deny messages | ✅ Done | [`src/mesg.asm`](src/mesg.asm) |
| 📁 | [`mkdir`](src/mkdir.asm) | Creates directories | ✅ Done | [`src/mkdir.asm`](src/mkdir.asm) |
| 📯 | [`mkfifo`](src/mkfifo.asm) | Makes named pipes (FIFOs) | ✅ Done | [`src/mkfifo.asm`](src/mkfifo.asm) |
| 🧩 | [`mknod`](src/mknod.asm) | Makes block or character special files | ✅ Done | [`src/mknod.asm`](src/mknod.asm) |
| 📜 | [`mktemp`](src/mktemp.asm) | Creates a temporary file or directory | ✅ Done | [`src/mktemp.asm`](src/mktemp.asm) |
| 📬 | [`msgfmt`](src/msgfmt.asm) | Create messages objects from messages object files | ✅ Done | [`src/msgfmt.asm`](src/msgfmt.asm) |
| 🚚 | [`mv`](src/mv.asm) | Moves files or rename files | ✅ Done | [`src/mv.asm`](src/mv.asm) |
| 👨‍👩‍👧 | [`newgrp`](src/newgrp.asm) | Change to a new group | ✅ Done | [`src/newgrp.asm`](src/newgrp.asm) |
| 🗯️ | [`ngettext`](src/ngettext.asm) | Retrieve text string from messages object with plural form | ✅ Done | [`src/ngettext.asm`](src/ngettext.asm) |
| 👌 | [`nice`](src/nice.asm) | Modifies scheduling priority | ✅ Done | [`src/nice.asm`](src/nice.asm) |
| 🔢 | [`nl`](src/nl.asm) | Numbers lines of files | ✅ Done | [`src/nl.asm`](src/nl.asm) |
| 🏃 | [`nohup`](src/nohup.asm) | Allows a command to continue running after logging out | ✅ Done | [`src/nohup.asm`](src/nohup.asm) |
| 🖥️ | [`nproc`](src/nproc.asm) | Queries the number of (active) processors | ✅ Done | [`src/nproc.asm`](src/nproc.asm) |
| 🔣 | [`numfmt`](src/numfmt.asm) | Reformat numbers | ✅ Done | [`src/numfmt.asm`](src/numfmt.asm) |
| 👁️ | [`od`](src/od.asm) | Dumps files in octal and other formats | ✅ Done | [`src/od.asm`](src/od.asm) |
| 📌 | [`paste`](src/paste.asm) | Merge corresponding or subsequent lines of files | ✅ Done | [`src/paste.asm`](src/paste.asm) |
| 🩹 | [`patch`](src/patch.asm) | Apply changes to files | ✅ Done | [`src/patch.asm`](src/patch.asm) |
| ✓ | [`pathchk`](src/pathchk.asm) | Checks whether file names are valid or portable | ✅ Done | [`src/pathchk.asm`](src/pathchk.asm) |
| 📦 | [`pax`](src/pax.asm) | Portable archive interchange | ✅ Done | [`src/pax.asm`](src/pax.asm) |
| 👆 | [`pinky`](src/pinky.asm) | A lightweight version of finger | ✅ Done | [`src/pinky.asm`](src/pinky.asm) |
| 📄 | [`pr`](src/pr.asm) | Paginate or columnate files for printing | ✅ Done | [`src/pr.asm`](src/pr.asm) |
| 🖼️ | [`printenv`](src/printenv.asm) | Prints environment variables | ✅ Done | [`src/printenv.asm`](src/printenv.asm) |
| 🖊️ | [`printf`](src/printf.asm) | Formats and prints data | ✅ Done | [`src/printf.asm`](src/printf.asm) |
| 📈 | [`ps`](src/ps.asm) | Report process status | ✅ Done | [`src/ps.asm`](src/ps.asm) |
| 📇 | [`ptx`](src/ptx.asm) | Produces a permuted index of file contents | ✅ Done | [`src/ptx.asm`](src/ptx.asm) |
| 🧭 | [`pwd`](src/pwd.asm) | Prints the current working directory | ✅ Done | [`src/pwd.asm`](src/pwd.asm) |
| 📖 | [`read`](src/read.asm) | Read a line from standard input | ✅ Done | [`src/read.asm`](src/read.asm) |
| 👉 | [`readlink`](src/readlink.asm) | Print destination of a symbolic link | ✅ Done | [`src/readlink.asm`](src/readlink.asm) |
| 🛣️ | [`realpath`](src/realpath.asm) | Returns the resolved absolute or relative path for a file | ✅ Done | [`src/realpath.asm`](src/realpath.asm) |
| 👍 | [`renice`](src/renice.asm) | Set nice values of running processes | ✅ Done | [`src/renice.asm`](src/renice.asm) |
| 🗑️ | [`rm`](src/rm.asm) | Removes files/directories | ✅ Done | [`src/rm.asm`](src/rm.asm) |
| 🗂️ | [`rmdir`](src/rmdir.asm) | Removes empty directories | ✅ Done | [`src/rmdir.asm`](src/rmdir.asm) |
| 🔓 | [`runcon`](src/runcon.asm) | Run command with specified security context | ✅ Done | [`src/runcon.asm`](src/runcon.asm) |
| 🔄 | [`seq`](src/seq.asm) | Prints a sequence of numbers | ✅ Done | [`src/seq.asm`](src/seq.asm) |
| 🔏 | [`sha1sum`](src/sha1sum.asm) | Computes and checks SHA-1/SHA-2 message digests | ✅ Done | [`src/sha1sum.asm`](src/sha1sum.asm) |
| 🔐 | [`sha224sum`](src/sha224sum.asm) | Computes and checks SHA-1/SHA-2 message digests | ✅ Done | [`src/sha224sum.asm`](src/sha224sum.asm) |
| 🔒 | [`sha256sum`](src/sha256sum.asm) | Computes and checks SHA-1/SHA-2 message digests | ✅ Done | [`src/sha256sum.asm`](src/sha256sum.asm) |
| 🔓 | [`sha384sum`](src/sha384sum.asm) | Computes and checks SHA-1/SHA-2 message digests | ✅ Done | [`src/sha384sum.asm`](src/sha384sum.asm) |
| 🔑 | [`sha512sum`](src/sha512sum.asm) | Computes and checks SHA-1/SHA-2 message digests | ✅ Done | [`src/sha512sum.asm`](src/sha512sum.asm) |
| 🔪 | [`shred`](src/shred.asm) | Overwrites a file to hide its contents, and optionally deletes it | ✅ Done | [`src/shred.asm`](src/shred.asm) |
| 🎲 | [`shuf`](src/shuf.asm) | generates random permutations | ✅ Done | [`src/shuf.asm`](src/shuf.asm) |
| 💤 | [`sleep`](src/sleep.asm) | Delays for a specified amount of time | ✅ Done | [`src/sleep.asm`](src/sleep.asm) |
| 🔠 | [`sort`](src/sort.asm) | Sorts lines of text files | ✅ Done | [`src/sort.asm`](src/sort.asm) |
| ✂️ | [`split`](src/split.asm) | Splits a file into pieces | ✅ Done | [`src/split.asm`](src/split.asm) |
| 📊 | [`stat`](src/stat.asm) | Returns data about an inode | ✅ Done | [`src/stat.asm`](src/stat.asm) |
| 📤 | [`stdbuf`](src/stdbuf.asm) | Controls buffering for commands that use stdio | ✅ Done | [`src/stdbuf.asm`](src/stdbuf.asm) |
| 🔤 | [`strings`](src/strings.asm) | Find printable strings in files | ✅ Done | [`src/strings.asm`](src/strings.asm) |
| ⌨️ | [`stty`](src/stty.asm) | Changes and prints terminal line settings | ✅ Done | [`src/stty.asm`](src/stty.asm) |
| ➕ | [`sum`](src/sum.asm) | Checksums and counts the blocks in a file | ✅ Done | [`src/sum.asm`](src/sum.asm) |
| 🔃 | [`sync`](src/sync.asm) | Flushes file system buffers | ✅ Done | [`src/sync.asm`](src/sync.asm) |
| 📑 | [`tabs`](src/tabs.asm) | Set terminal tabs | ✅ Done | [`src/tabs.asm`](src/tabs.asm) |
| 🙃 | [`tac`](src/tac.asm) | Concatenates and prints files in reverse order line by line | ✅ Done | [`src/tac.asm`](src/tac.asm) |
| ⬇️ | [`tail`](src/tail.asm) | Output the end of files | ✅ Done | [`src/tail.asm`](src/tail.asm) |
| 🔱 | [`tee`](src/tee.asm) | Sends output to multiple files | ✅ Done | [`src/tee.asm`](src/tee.asm) |
| 🧪 | [`test`](src/test.asm) | Evaluates an expression | ✅ Done | [`src/test.asm`](src/test.asm) |
| ⏱️ | [`time`](src/time.asm) | Display elapsed, system and kernel time | ✅ Done | [`src/time.asm`](src/time.asm) |
| ⌛ | [`timeout`](src/timeout.asm) | Runs a command with a time limit | ✅ Done | [`src/timeout.asm`](src/timeout.asm) |
| 👆 | [`touch`](src/touch.asm) | Changes file timestamps; creates file | ✅ Done | [`src/touch.asm`](src/touch.asm) |
| 🎮 | [`tput`](src/tput.asm) | Change terminal characteristics | ✅ Done | [`src/tput.asm`](src/tput.asm) |
| 🔡 | [`tr`](src/tr.asm) | Translates or deletes characters | ✅ Done | [`src/tr.asm`](src/tr.asm) |
| ✅ | [`true`](src/true.asm) | Does nothing, but exits successfully | ✅ Done | [`src/true.asm`](src/true.asm) |
| 📏 | [`truncate`](src/truncate.asm) | Shrink the size of a file to the specified size | ✅ Done | [`src/truncate.asm`](src/truncate.asm) |
| 🧶 | [`tsort`](src/tsort.asm) | Performs a topological sort | ✅ Done | [`src/tsort.asm`](src/tsort.asm) |
| 📺 | [`tty`](src/tty.asm) | Prints terminal name | ✅ Done | [`src/tty.asm`](src/tty.asm) |
| 🎭 | [`umask`](src/umask.asm) | Get or set the file mode creation mask | ✅ Done | [`src/umask.asm`](src/umask.asm) |
| 🚫 | [`unalias`](src/unalias.asm) | Remove alias definitions | ✅ Done | [`src/unalias.asm`](src/unalias.asm) |
| 💻 | [`uname`](src/uname.asm) | Prints system information | ✅ Done | [`src/uname.asm`](src/uname.asm) |
| ⬅️ | [`unexpand`](src/unexpand.asm) | Converts spaces to tabs | ✅ Done | [`src/unexpand.asm`](src/unexpand.asm) |
| 🎯 | [`uniq`](src/uniq.asm) | Removes duplicate lines from a sorted file | ✅ Done | [`src/uniq.asm`](src/uniq.asm) |
| 🔓 | [`unlink`](src/unlink.asm) | Removes the specified file using the unlink function | ✅ Done | [`src/unlink.asm`](src/unlink.asm) |
| ⏰ | [`uptime`](src/uptime.asm) | Tells how long the system has been running | ✅ Done | [`src/uptime.asm`](src/uptime.asm) |
| 👨‍👩‍👧‍👦 | [`users`](src/users.asm) | Prints the user names of users currently logged in | ✅ Done | [`src/users.asm`](src/users.asm) |
| 📩 | [`uudecode`](src/uudecode.asm) | Decode a binary file | ✅ Done | [`src/uudecode.asm`](src/uudecode.asm) |
| 📫 | [`uuencode`](src/uuencode.asm) | Encode a binary file | ✅ Done | [`src/uuencode.asm`](src/uuencode.asm) |
| ⏳ | [`wait`](src/wait.asm) | Await process completion | ✅ Done | [`src/wait.asm`](src/wait.asm) |
| 🔡 | [`wc`](src/wc.asm) | Prints the number of bytes, words, and lines in files | ✅ Done | [`src/wc.asm`](src/wc.asm) |
| 👨‍👨‍👧‍👧 | [`who`](src/who.asm) | Prints a list of all users currently logged in | ✅ Done | [`src/who.asm`](src/who.asm) |
| 🙋 | [`whoami`](src/whoami.asm) | Prints the effective userid | ✅ Done | [`src/whoami.asm`](src/whoami.asm) |
| ✉️ | [`write`](src/write.asm) | Write to another user's terminal | ✅ Done | [`src/write.asm`](src/write.asm) |
| 🔨 | [`xargs`](src/xargs.asm) | Construct argument lists and invoke utility | ✅ Done | [`src/xargs.asm`](src/xargs.asm) |
| 🔁 | [`yes`](src/yes.asm) | Prints a string repeatedly | ✅ Done | [`src/yes.asm`](src/yes.asm) |

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

## 📊 Benchmark
Run `make` to build all binaries, then execute `tests/benchmark.sh` to compare a few Baloo programs against the system implementations using `hyperfine`.


## 📐 Formatting

Canonical style rules:
- No trailing whitespace in tracked text files.
- NASM labels/directives stay at column 0; instructions use 4-space indentation; inline comments are aligned to column 40.

Commands:
- Apply formatting: `make format`
- Validate formatting only: `make lint-format`
- Single file: `python3 scripts/asmfmt.py src/example.asm`

<hr>

<img src="assets/Baloo.jpg" title=" भालू "></img>
