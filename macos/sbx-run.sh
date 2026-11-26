#!/bin/bash
# sbx-run.sh [-t seconds] [-m MB] [-p procs] -- command...    (run from inside the scratch folder you want)
# Runs a command under the Seatbelt profile with a scrubbed environment, its own process group,
# optional ulimits and a wall-time kill of the whole group. Prints "[sbx] exit=… wall=…ms" on stderr.
set -u
T=120; M=""; P=""
while [ $# -gt 0 ]; do case "$1" in -t) T=$2; shift 2;; -m) M=$2; shift 2;; -p) P=$2; shift 2;; --) shift; break;; *) break;; esac; done
HERE=$(cd "$(dirname "$0")" && pwd)
SCR=$(pwd -P)
: "${YK_TEX:?set YK_TEX to the TeX tree}" "${YK_PY:?set YK_PY to the Python prefix}"
LIM=""
[ -n "$M" ] && LIM="$LIM ulimit -v $((M*1024)) 2>/dev/null || echo '[sbx] ulimit -v not supported' >&2; ulimit -d $((M*1024)) 2>/dev/null || echo '[sbx] ulimit -d not supported' >&2;"
[ -n "$P" ] && LIM="$LIM ulimit -u $P 2>/dev/null || echo '[sbx] ulimit -u refused' >&2;"
mkdir -p "$SCR/.tmp" "$SCR/.texmf-var"
s=$(perl -MTime::HiRes=time -e 'printf "%.0f", time*1000')
# perl setpgrp: new process group so the whole tree can be killed at the deadline
perl -e 'setpgrp(0,0); exec @ARGV' /usr/bin/env -i \
  PATH="$YK_TEXBIN:$YK_PY/bin:/usr/bin:/bin" HOME="$SCR" TMPDIR="$SCR/.tmp" LANG=en_US.UTF-8 \
  TEXMFVAR="$SCR/.texmf-var" TEXMFCONFIG="$SCR/.texmf-var" TEXMFHOME="$SCR/texmf" \
  /usr/bin/sandbox-exec -f "$HERE/yk.sb" -D TEX="$YK_TEX" -D PY="$YK_PY" -D SCRATCH="$SCR" \
  /bin/bash -c "$LIM exec \"\$@\"" sbx "$@" &
pid=$!
( sleep "$T"; if kill -0 $pid 2>/dev/null; then echo "[sbx] TIMEOUT after ${T}s: killing process group $pid" >&2; kill -KILL -- -$pid 2>/dev/null; fi ) &
wd=$!
wait $pid; rc=$?
kill $wd 2>/dev/null; wait $wd 2>/dev/null
left=$(pgrep -g $pid 2>/dev/null | wc -l | tr -d ' ')
[ "$left" != "0" ] && { kill -KILL -- -$pid 2>/dev/null; echo "[sbx] killed $left stragglers" >&2; }
e=$(perl -MTime::HiRes=time -e 'printf "%.0f", time*1000')
echo "[sbx] exit=$rc wall=$((e-s))ms" >&2
exit $rc
