# 🐻 Baloo  

![Progress](https://img.shields.io/badge/progress-150%2F150%20done-brightgreen) ![Build Status](https://github.com/seanwevans/baloo/actions/workflows/Baloo.yml/badge.svg)

Just the bear utilities in x86_64 assembly using direct syscalls only — no libc or dependencies.

<img src="assets/Baloo.jpg" title=" भालू "></img>

I was tired of seeing

<img alt="usr/bin/true" src="https://github.com/user-attachments/assets/be6b408b-c922-411f-ae68-2a9de0ea70e0" />

When I should be seeing

<img alt="Baloo/bin/true" src="https://github.com/user-attachments/assets/a7b74b87-1a2d-4b1a-93db-c591177b76af" />

So I built

## Catalog

<table>
  <tbody>
    <tr>
      <td align="center" title="tput" style="font-size: 1.5em; padding: 5px;"><a href="src/tput.asm" style="text-decoration: none;">🎮</a></td>
      <td align="center" title="printf" style="font-size: 1.5em; padding: 5px;"><a href="src/printf.asm" style="text-decoration: none;">🖊️</a></td>
      <td align="center" title="uptime" style="font-size: 1.5em; padding: 5px;"><a href="src/uptime.asm" style="text-decoration: none;">⏰</a></td>
      <td align="center" title="stat" style="font-size: 1.5em; padding: 5px;"><a href="src/stat.asm" style="text-decoration: none;">📊</a></td>
      <td align="center" title="pax" style="font-size: 1.5em; padding: 5px;"><a href="src/pax.asm" style="text-decoration: none;">📦</a></td>
      <td align="center" title="kill" style="font-size: 1.5em; padding: 5px;"><a href="src/kill.asm" style="text-decoration: none;">💀</a></td>
      <td align="center" title="ptx" style="font-size: 1.5em; padding: 5px;"><a href="src/ptx.asm" style="text-decoration: none;">📇</a></td>
      <td align="center" title="sha512sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sha512sum.asm" style="text-decoration: none;">🔑</a></td>
      <td align="center" title="sha384sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sha384sum.asm" style="text-decoration: none;">🔓</a></td>
      <td align="center" title="cmp" style="font-size: 1.5em; padding: 5px;"><a href="src/cmp.asm" style="text-decoration: none;">🔬</a></td>
      <td align="center" title="sha224sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sha224sum.asm" style="text-decoration: none;">🔐</a></td>
      <td align="center" title="sha256sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sha256sum.asm" style="text-decoration: none;">🔒</a></td>
    </tr>
    <tr>
      <td align="center" title="comm" style="font-size: 1.5em; padding: 5px;"><a href="src/comm.asm" style="text-decoration: none;">☯️</a></td>
      <td align="center" title="whoami" style="font-size: 1.5em; padding: 5px;"><a href="src/whoami.asm" style="text-decoration: none;">🙋</a></td>
      <td align="center" title="tail" style="font-size: 1.5em; padding: 5px;"><a href="src/tail.asm" style="text-decoration: none;">⬇️</a></td>
      <td align="center" title="sort" style="font-size: 1.5em; padding: 5px;"><a href="src/sort.asm" style="text-decoration: none;">🔠</a></td>
      <td align="center" title="seq" style="font-size: 1.5em; padding: 5px;"><a href="src/seq.asm" style="text-decoration: none;">🔄</a></td>
      <td align="center" title="mktemp" style="font-size: 1.5em; padding: 5px;"><a href="src/mktemp.asm" style="text-decoration: none;">📜</a></td>
      <td align="center" title="fold" style="font-size: 1.5em; padding: 5px;"><a href="src/fold.asm" style="text-decoration: none;">📃</a></td>
      <td align="center" title="bc" style="font-size: 1.5em; padding: 5px;"><a href="src/bc.asm" style="text-decoration: none;">🧮</a></td>
      <td align="center" title="wc" style="font-size: 1.5em; padding: 5px;"><a href="src/wc.asm" style="text-decoration: none;">🔡</a></td>
      <td align="center" title="factor" style="font-size: 1.5em; padding: 5px;"><a href="src/factor.asm" style="text-decoration: none;">🔢</a></td>
      <td align="center" title="uniq" style="font-size: 1.5em; padding: 5px;"><a href="src/uniq.asm" style="text-decoration: none;">🎯</a></td>
      <td align="center" title="tsort" style="font-size: 1.5em; padding: 5px;"><a href="src/tsort.asm" style="text-decoration: none;">🧶</a></td>
    </tr>
    <tr>
      <td align="center" title="base32" style="font-size: 1.5em; padding: 5px;"><a href="src/base32.asm" style="text-decoration: none;">3️⃣</a></td>
      <td align="center" title="logname" style="font-size: 1.5em; padding: 5px;"><a href="src/logname.asm" style="text-decoration: none;">👤</a></td>
      <td align="center" title="tr" style="font-size: 1.5em; padding: 5px;"><a href="src/tr.asm" style="text-decoration: none;">🔡</a></td>
      <td align="center" title="sha1sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sha1sum.asm" style="text-decoration: none;">🔏</a></td>
      <td align="center" title="cksum" style="font-size: 1.5em; padding: 5px;"><a href="src/cksum.asm" style="text-decoration: none;">🧾</a></td>
      <td align="center" title="iconv" style="font-size: 1.5em; padding: 5px;"><a href="src/iconv.asm" style="text-decoration: none;">🔄</a></td>
      <td align="center" title="who" style="font-size: 1.5em; padding: 5px;"><a href="src/who.asm" style="text-decoration: none;">👨‍👨‍👧‍👧</a></td>
      <td align="center" title="join" style="font-size: 1.5em; padding: 5px;"><a href="src/join.asm" style="text-decoration: none;">🔗</a></td>
      <td align="center" title="runcon" style="font-size: 1.5em; padding: 5px;"><a href="src/runcon.asm" style="text-decoration: none;">🔓</a></td>
      <td align="center" title="base64" style="font-size: 1.5em; padding: 5px;"><a href="src/base64.asm" style="text-decoration: none;">6️⃣</a></td>
      <td align="center" title="baseenc" style="font-size: 1.5em; padding: 5px;"><a href="src/baseenc.asm" style="text-decoration: none;">🔡</a></td>
      <td align="center" title="stdbuf" style="font-size: 1.5em; padding: 5px;"><a href="src/stdbuf.asm" style="text-decoration: none;">📤</a></td>
    </tr>
    <tr>
      <td align="center" title="xargs" style="font-size: 1.5em; padding: 5px;"><a href="src/xargs.asm" style="text-decoration: none;">🔨</a></td>
      <td align="center" title="unexpand" style="font-size: 1.5em; padding: 5px;"><a href="src/unexpand.asm" style="text-decoration: none;">⬅️</a></td>
      <td align="center" title="chown" style="font-size: 1.5em; padding: 5px;"><a href="src/chown.asm" style="text-decoration: none;">🔐</a></td>
      <td align="center" title="cd" style="font-size: 1.5em; padding: 5px;"><a href="src/cd.asm" style="text-decoration: none;">🚶</a></td>
      <td align="center" title="head" style="font-size: 1.5em; padding: 5px;"><a href="src/head.asm" style="text-decoration: none;">⬆️</a></td>
      <td align="center" title="crontab" style="font-size: 1.5em; padding: 5px;"><a href="src/crontab.asm" style="text-decoration: none;">🗓️</a></td>
      <td align="center" title="touch" style="font-size: 1.5em; padding: 5px;"><a href="src/touch.asm" style="text-decoration: none;">👆</a></td>
      <td align="center" title="id" style="font-size: 1.5em; padding: 5px;"><a href="src/id.asm" style="text-decoration: none;">🆔</a></td>
      <td align="center" title="shuf" style="font-size: 1.5em; padding: 5px;"><a href="src/shuf.asm" style="text-decoration: none;">🎲</a></td>
      <td align="center" title="paste" style="font-size: 1.5em; padding: 5px;"><a href="src/paste.asm" style="text-decoration: none;">📌</a></td>
      <td align="center" title="uudecode" style="font-size: 1.5em; padding: 5px;"><a href="src/uudecode.asm" style="text-decoration: none;">📩</a></td>
      <td align="center" title="date" style="font-size: 1.5em; padding: 5px;"><a href="src/date.asm" style="text-decoration: none;">📅</a></td>
    </tr>
    <tr>
      <td align="center" title="umask" style="font-size: 1.5em; padding: 5px;"><a href="src/umask.asm" style="text-decoration: none;">🎭</a></td>
      <td align="center" title="unalias" style="font-size: 1.5em; padding: 5px;"><a href="src/unalias.asm" style="text-decoration: none;">🚫</a></td>
      <td align="center" title="nl" style="font-size: 1.5em; padding: 5px;"><a href="src/nl.asm" style="text-decoration: none;">🔢</a></td>
      <td align="center" title="test" style="font-size: 1.5em; padding: 5px;"><a href="src/test.asm" style="text-decoration: none;">🧪</a></td>
      <td align="center" title="diff" style="font-size: 1.5em; padding: 5px;"><a href="src/diff.asm" style="text-decoration: none;">🔍</a></td>
      <td align="center" title="ln" style="font-size: 1.5em; padding: 5px;"><a href="src/ln.asm" style="text-decoration: none;">🖇️</a></td>
      <td align="center" title="getopts" style="font-size: 1.5em; padding: 5px;"><a href="src/getopts.asm" style="text-decoration: none;">🔣</a></td>
      <td align="center" title="ls" style="font-size: 1.5em; padding: 5px;"><a href="src/ls.asm" style="text-decoration: none;">📋</a></td>
      <td align="center" title="uuencode" style="font-size: 1.5em; padding: 5px;"><a href="src/uuencode.asm" style="text-decoration: none;">📫</a></td>
      <td align="center" title="ps" style="font-size: 1.5em; padding: 5px;"><a href="src/ps.asm" style="text-decoration: none;">📈</a></td>
      <td align="center" title="grep" style="font-size: 1.5em; padding: 5px;"><a href="src/grep.asm" style="text-decoration: none;">🔦</a></td>
      <td align="center" title="users" style="font-size: 1.5em; padding: 5px;"><a href="src/users.asm" style="text-decoration: none;">👨‍👩‍👧‍👦</a></td>
    </tr>
    <tr>
      <td align="center" title="basename" style="font-size: 1.5em; padding: 5px;"><a href="src/basename.asm" style="text-decoration: none;">🔤</a></td>
      <td align="center" title="chroot" style="font-size: 1.5em; padding: 5px;"><a href="src/chroot.asm" style="text-decoration: none;">🌱</a></td>
      <td align="center" title="link" style="font-size: 1.5em; padding: 5px;"><a href="src/link.asm" style="text-decoration: none;">🔗</a></td>
      <td align="center" title="time" style="font-size: 1.5em; padding: 5px;"><a href="src/time.asm" style="text-decoration: none;">⏱️</a></td>
      <td align="center" title="cp" style="font-size: 1.5em; padding: 5px;"><a href="src/cp.asm" style="text-decoration: none;">📑</a></td>
      <td align="center" title="expand" style="font-size: 1.5em; padding: 5px;"><a href="src/expand.asm" style="text-decoration: none;">➡️</a></td>
      <td align="center" title="lp" style="font-size: 1.5em; padding: 5px;"><a href="src/lp.asm" style="text-decoration: none;">🖨️</a></td>
      <td align="center" title="sum" style="font-size: 1.5em; padding: 5px;"><a href="src/sum.asm" style="text-decoration: none;">➕</a></td>
      <td align="center" title="ar" style="font-size: 1.5em; padding: 5px;"><a href="src/ar.asm" style="text-decoration: none;">🗄️</a></td>
      <td align="center" title="dd" style="font-size: 1.5em; padding: 5px;"><a href="src/dd.asm" style="text-decoration: none;">💾</a></td>
      <td align="center" title="chmod" style="font-size: 1.5em; padding: 5px;"><a href="src/chmod.asm" style="text-decoration: none;">🔒</a></td>
      <td align="center" title="stty" style="font-size: 1.5em; padding: 5px;"><a href="src/stty.asm" style="text-decoration: none;">⌨️</a></td>
    </tr>
    <tr>
      <td align="center" title="hostid" style="font-size: 1.5em; padding: 5px;"><a href="src/hostid.asm" style="text-decoration: none;">🏷️</a></td>
      <td align="center" title="numfmt" style="font-size: 1.5em; padding: 5px;"><a href="src/numfmt.asm" style="text-decoration: none;">🔣</a></td>
      <td align="center" title="expr" style="font-size: 1.5em; padding: 5px;"><a href="src/expr.asm" style="text-decoration: none;">📊</a></td>
      <td align="center" title="csplit" style="font-size: 1.5em; padding: 5px;"><a href="src/csplit.asm" style="text-decoration: none;">📂</a></td>
      <td align="center" title="find" style="font-size: 1.5em; padding: 5px;"><a href="src/find.asm" style="text-decoration: none;">🔎</a></td>
      <td align="center" title="split" style="font-size: 1.5em; padding: 5px;"><a href="src/split.asm" style="text-decoration: none;">✂️</a></td>
      <td align="center" title="b2sum" style="font-size: 1.5em; padding: 5px;"><a href="src/b2sum.asm" style="text-decoration: none;">🧪</a></td>
      <td align="center" title="nproc" style="font-size: 1.5em; padding: 5px;"><a href="src/nproc.asm" style="text-decoration: none;">🖥️</a></td>
      <td align="center" title="md5sum" style="font-size: 1.5em; padding: 5px;"><a href="src/md5sum.asm" style="text-decoration: none;">🔑</a></td>
      <td align="center" title="getconf" style="font-size: 1.5em; padding: 5px;"><a href="src/getconf.asm" style="text-decoration: none;">⚙️</a></td>
      <td align="center" title="truncate" style="font-size: 1.5em; padding: 5px;"><a href="src/truncate.asm" style="text-decoration: none;">📏</a></td>
      <td align="center" title="mkfifo" style="font-size: 1.5em; padding: 5px;"><a href="src/mkfifo.asm" style="text-decoration: none;">📯</a></td>
    </tr>
    <tr>
      <td align="center" title="nice" style="font-size: 1.5em; padding: 5px;"><a href="src/nice.asm" style="text-decoration: none;">👌</a></td>
      <td align="center" title="readlink" style="font-size: 1.5em; padding: 5px;"><a href="src/readlink.asm" style="text-decoration: none;">👉</a></td>
      <td align="center" title="shred" style="font-size: 1.5em; padding: 5px;"><a href="src/shred.asm" style="text-decoration: none;">🔪</a></td>
      <td align="center" title="fmt" style="font-size: 1.5em; padding: 5px;"><a href="src/fmt.asm" style="text-decoration: none;">📐</a></td>
      <td align="center" title="mv" style="font-size: 1.5em; padding: 5px;"><a href="src/mv.asm" style="text-decoration: none;">🚚</a></td>
      <td align="center" title="printenv" style="font-size: 1.5em; padding: 5px;"><a href="src/printenv.asm" style="text-decoration: none;">🖼️</a></td>
      <td align="center" title="at" style="font-size: 1.5em; padding: 5px;"><a href="src/at.asm" style="text-decoration: none;">⏰</a></td>
      <td align="center" title="man" style="font-size: 1.5em; padding: 5px;"><a href="src/man.asm" style="text-decoration: none;">📚</a></td>
      <td align="center" title="realpath" style="font-size: 1.5em; padding: 5px;"><a href="src/realpath.asm" style="text-decoration: none;">🛣️</a></td>
      <td align="center" title="mesg" style="font-size: 1.5em; padding: 5px;"><a href="src/mesg.asm" style="text-decoration: none;">📨</a></td>
      <td align="center" title="cat" style="font-size: 1.5em; padding: 5px;"><a href="src/cat.asm" style="text-decoration: none;">🐱</a></td>
      <td align="center" title="renice" style="font-size: 1.5em; padding: 5px;"><a href="src/renice.asm" style="text-decoration: none;">👍</a></td>
    </tr>
    <tr>
      <td align="center" title="mknod" style="font-size: 1.5em; padding: 5px;"><a href="src/mknod.asm" style="text-decoration: none;">🧩</a></td>
      <td align="center" title="od" style="font-size: 1.5em; padding: 5px;"><a href="src/od.asm" style="text-decoration: none;">👁️</a></td>
      <td align="center" title="tac" style="font-size: 1.5em; padding: 5px;"><a href="src/tac.asm" style="text-decoration: none;">🙃</a></td>
      <td align="center" title="strings" style="font-size: 1.5em; padding: 5px;"><a href="src/strings.asm" style="text-decoration: none;">🔤</a></td>
      <td align="center" title="dirname" style="font-size: 1.5em; padding: 5px;"><a href="src/dirname.asm" style="text-decoration: none;">📁</a></td>
      <td align="center" title="cut" style="font-size: 1.5em; padding: 5px;"><a href="src/cut.asm" style="text-decoration: none;">✂️</a></td>
      <td align="center" title="localedef" style="font-size: 1.5em; padding: 5px;"><a href="src/localedef.asm" style="text-decoration: none;">🌐</a></td>
      <td align="center" title="gencat" style="font-size: 1.5em; padding: 5px;"><a href="src/gencat.asm" style="text-decoration: none;">😺</a></td>
      <td align="center" title="newgrp" style="font-size: 1.5em; padding: 5px;"><a href="src/newgrp.asm" style="text-decoration: none;">👨‍👩‍👧</a></td>
      <td align="center" title="chgrp" style="font-size: 1.5em; padding: 5px;"><a href="src/chgrp.asm" style="text-decoration: none;">👥</a></td>
      <td align="center" title="install" style="font-size: 1.5em; padding: 5px;"><a href="src/install.asm" style="text-decoration: none;">📥</a></td>
      <td align="center" title="du" style="font-size: 1.5em; padding: 5px;"><a href="src/du.asm" style="text-decoration: none;">📊</a></td>
    </tr>
    <tr>
      <td align="center" title="pathchk" style="font-size: 1.5em; padding: 5px;"><a href="src/pathchk.asm" style="text-decoration: none;">✓</a></td>
      <td align="center" title="locale" style="font-size: 1.5em; padding: 5px;"><a href="src/locale.asm" style="text-decoration: none;">🌍</a></td>
      <td align="center" title="rmdir" style="font-size: 1.5em; padding: 5px;"><a href="src/rmdir.asm" style="text-decoration: none;">🗂️</a></td>
      <td align="center" title="nohup" style="font-size: 1.5em; padding: 5px;"><a href="src/nohup.asm" style="text-decoration: none;">🏃</a></td>
      <td align="center" title="tee" style="font-size: 1.5em; padding: 5px;"><a href="src/tee.asm" style="text-decoration: none;">🔱</a></td>
      <td align="center" title="groups" style="font-size: 1.5em; padding: 5px;"><a href="src/groups.asm" style="text-decoration: none;">👪</a></td>
      <td align="center" title="uname" style="font-size: 1.5em; padding: 5px;"><a href="src/uname.asm" style="text-decoration: none;">💻</a></td>
      <td align="center" title="alias" style="font-size: 1.5em; padding: 5px;"><a href="src/alias.asm" style="text-decoration: none;">🏷️</a></td>
      <td align="center" title="batch" style="font-size: 1.5em; padding: 5px;"><a href="src/batch.asm" style="text-decoration: none;">📚</a></td>
      <td align="center" title="ngettext" style="font-size: 1.5em; padding: 5px;"><a href="src/ngettext.asm" style="text-decoration: none;">🗯️</a></td>
      <td align="center" title="df" style="font-size: 1.5em; padding: 5px;"><a href="src/df.asm" style="text-decoration: none;">💽</a></td>
      <td align="center" title="mkdir" style="font-size: 1.5em; padding: 5px;"><a href="src/mkdir.asm" style="text-decoration: none;">📁</a></td>
    </tr>
    <tr>
      <td align="center" title="yes" style="font-size: 1.5em; padding: 5px;"><a href="src/yes.asm" style="text-decoration: none;">🔁</a></td>
      <td align="center" title="wait" style="font-size: 1.5em; padding: 5px;"><a href="src/wait.asm" style="text-decoration: none;">⏳</a></td>
      <td align="center" title="echo" style="font-size: 1.5em; padding: 5px;"><a href="src/echo.asm" style="text-decoration: none;">🗣️</a></td>
      <td align="center" title="timeout" style="font-size: 1.5em; padding: 5px;"><a href="src/timeout.asm" style="text-decoration: none;">⌛</a></td>
      <td align="center" title="hash" style="font-size: 1.5em; padding: 5px;"><a href="src/hash.asm" style="text-decoration: none;">🔐</a></td>
      <td align="center" title="logger" style="font-size: 1.5em; padding: 5px;"><a href="src/logger.asm" style="text-decoration: none;">📓</a></td>
      <td align="center" title="tty" style="font-size: 1.5em; padding: 5px;"><a href="src/tty.asm" style="text-decoration: none;">📺</a></td>
      <td align="center" title="read" style="font-size: 1.5em; padding: 5px;"><a href="src/read.asm" style="text-decoration: none;">📖</a></td>
      <td align="center" title="chcon" style="font-size: 1.5em; padding: 5px;"><a href="src/chcon.asm" style="text-decoration: none;">🛡️</a></td>
      <td align="center" title="env" style="font-size: 1.5em; padding: 5px;"><a href="src/env.asm" style="text-decoration: none;">🌐</a></td>
      <td align="center" title="sleep" style="font-size: 1.5em; padding: 5px;"><a href="src/sleep.asm" style="text-decoration: none;">💤</a></td>
      <td align="center" title="unlink" style="font-size: 1.5em; padding: 5px;"><a href="src/unlink.asm" style="text-decoration: none;">🔓</a></td>
    </tr>
    <tr>
      <td align="center" title="write" style="font-size: 1.5em; padding: 5px;"><a href="src/write.asm" style="text-decoration: none;">✉️</a></td>
      <td align="center" title="tabs" style="font-size: 1.5em; padding: 5px;"><a href="src/tabs.asm" style="text-decoration: none;">📑</a></td>
      <td align="center" title="pinky" style="font-size: 1.5em; padding: 5px;"><a href="src/pinky.asm" style="text-decoration: none;">👆</a></td>
      <td align="center" title="rm" style="font-size: 1.5em; padding: 5px;"><a href="src/rm.asm" style="text-decoration: none;">🗑️</a></td>
      <td align="center" title="command" style="font-size: 1.5em; padding: 5px;"><a href="src/command.asm" style="text-decoration: none;">⚡</a></td>
      <td align="center" title="gettext" style="font-size: 1.5em; padding: 5px;"><a href="src/gettext.asm" style="text-decoration: none;">💬</a></td>
      <td align="center" title="arch" style="font-size: 1.5em; padding: 5px;"><a href="src/arch.asm" style="text-decoration: none;">🏗️</a></td>
      <td align="center" title="pwd" style="font-size: 1.5em; padding: 5px;"><a href="src/pwd.asm" style="text-decoration: none;">🧭</a></td>
      <td align="center" title="dircolors" style="font-size: 1.5em; padding: 5px;"><a href="src/dircolors.asm" style="text-decoration: none;">🎨</a></td>
      <td align="center" title="sync" style="font-size: 1.5em; padding: 5px;"><a href="src/sync.asm" style="text-decoration: none;">🔃</a></td>
      <td align="center" title="false" style="font-size: 1.5em; padding: 5px;"><a href="src/false.asm" style="text-decoration: none;">❌</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/true.asm" style="text-decoration: none;">✅</a></td>
    </tr>
    <tr>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/pr.asm" style="text-decoration: none;">📄</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/m4.asm" style="text-decoration: none;">🔁</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/patch.asm" style="text-decoration: none;">🩹</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/mailx.asm" style="text-decoration: none;">📧</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/msgfmt.asm" style="text-decoration: none;">📬</a></td>
      <td align="center" title="true" style="font-size: 1.5em; padding: 5px;"><a href="src/file.asm" style="text-decoration: none;">📎</a></td>
    </tr>
  </tbody>
</table>

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
- Makefile recipe lines use **tabs**.
- No trailing whitespace in tracked text files.
- NASM labels/directives stay at column 0; instructions use 4-space indentation; inline comments are aligned to column 40.

Commands:
- Apply formatting: `make format`
- Validate formatting only: `make lint-format`
- Single file: `python3 scripts/asmfmt.py src/example.asm`
