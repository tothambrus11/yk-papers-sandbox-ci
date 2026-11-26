#!/bin/bash
# macOS Seatbelt test matrix. Needs YK_TEX (TeX tree), YK_TEXBIN (its bin dir), YK_PY (Python prefix), and
# ~/yk-outside/secret.txt (made by setup-macos.sh). Writes results.md next to this script.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
DOCS="$ROOT/tests/docs"; MDOCS="$HERE/docs"; OUT="$HOME/yk-outside"
SES="$ROOT/scratch/session"; rm -rf "$SES"; mkdir -p "$SES"; SES=$(cd "$SES" && pwd -P)
RUN="$HERE/sbx-run.sh"; RES="$HERE/results.md"; LOG="$HERE/matrix-log.txt"; : > "$LOG"
printf '| Group | Test | Result | Detail |\n|---|---|---|---|\n' > "$RES"
pass=0; fail=0
add() { # group name ok(0/1) detail
  local r=FAIL; [ "$3" = 1 ] && r=PASS && pass=$((pass+1)) || fail=$((fail+1))
  local d=$(printf '%s' "$4" | tr '\n|' '  ' | cut -c1-220)
  printf '| %s | %s | **%s** | %s |\n' "$1" "$2" "$r" "$d" >> "$RES"; printf '%-4s [%s] %s: %s\n' "$r" "$1" "$2" "$d"
}
case_dir() { local d="$SES/$1"; rm -rf "$d"; mkdir -p "$d"; shift; for f in "$@"; do cp "$f" "$d/"; done; echo "$d"; }
sbx() { # dir args... ; captures out/err, returns code
  local d=$1; shift; ( cd "$d" && "$RUN" "$@" ) > "$d/.out" 2> "$d/.err"; local c=$?
  { echo "==== $d: $*"; cat "$d/.out" "$d/.err"; } >> "$LOG"; return $c
}
summary() { grep '^\[sbx\]' "$1/.err" | tail -1; }
pdf_test() { # group name case job files... -- cmds...
  local g=$1 n=$2 c=$3 job=$4; shift 4; local files=(); while [ "$1" != "--" ]; do files+=("$1"); shift; done; shift
  local d=$(case_dir "$c" "${files[@]}") ok=1
  for cmd in "$@"; do sbx "$d" -- /bin/sh -c "$cmd" || { ok=0; break; }; done
  [ -f "$d/$job.pdf" ] || ok=0
  local det; if [ $ok = 1 ]; then det="pdf ok; $(summary "$d")"; else det="$(grep -m2 '^!' "$d/$job.log" 2>/dev/null | tr '\n' ' ') $(tail -3 "$d/.err" | tr '\n' ' ')"; fi
  add "$g" "$n" $ok "$det"
}

# host-side controls: a loopback listener and a victim process outside the sandbox
python3 -m http.server 47123 --bind 127.0.0.1 > /dev/null 2>&1 & LST=$!
sleep 600 & VICTIM=$!
rm -f "$OUT"/pwned_*.txt
sleep 1

g=works
for e in pdflatex xelatex lualatex; do pdf_test $g "$e small doc" w_$e basic "$DOCS/basic.tex" -- "$e -interaction=nonstopmode basic.tex"; done
pdf_test $g bibtex w_bibtex bibtex "$DOCS/bibtex.tex" "$DOCS/refs.bib" -- "pdflatex -interaction=nonstopmode bibtex.tex" "bibtex bibtex" "pdflatex -interaction=nonstopmode bibtex.tex"
pdf_test $g biber w_biber biber "$DOCS/biber.tex" "$DOCS/refs.bib" -- "pdflatex -interaction=nonstopmode biber.tex" "biber biber" "pdflatex -interaction=nonstopmode biber.tex"
pdf_test $g makeindex w_index index "$DOCS/index.tex" -- "pdflatex -interaction=nonstopmode index.tex" "makeindex index" "pdflatex -interaction=nonstopmode index.tex"
pdf_test $g "latexmk full biber build" w_latexmk biber "$DOCS/biber.tex" "$DOCS/refs.bib" -- "latexmk -pdf -interaction=nonstopmode biber.tex"
pdf_test $g "minted, restricted shell escape" w_minted minted "$DOCS/minted.tex" -- "pdflatex -interaction=nonstopmode minted.tex"
pdf_test $g "minted, -shell-escape" w_minted_se minted "$DOCS/minted.tex" -- "pdflatex -shell-escape -interaction=nonstopmode minted.tex"
pdf_test $g "TikZ externalize (nested pdflatex)" w_tikz tikzext "$DOCS/tikzext.tex" -- "pdflatex -shell-escape -interaction=nonstopmode tikzext.tex"
[ -f "$SES/w_tikz/tikzext-figure0.pdf" ] && add $g "TikZ externalize: figure pdf produced" 1 "tikzext-figure0.pdf exists" || add $g "TikZ externalize: figure pdf produced" 0 "no externalized figure"
for e in xelatex lualatex; do
  d=$(case_dir w_ff_$e "$DOCS/fontfile.tex"); mkdir -p "$d/fonts"; cp "$DOCS/texgyrepagella-regular.otf" "$d/fonts/"
  sbx "$d" -- $e -interaction=nonstopmode fontfile.tex; [ -f "$d/fontfile.pdf" ] && add $g "fontspec font file from scratch ($e)" 1 "$(summary "$d")" || add $g "fontspec font file from scratch ($e)" 0 "$(grep -m2 '^!' "$d/fontfile.log" | tr '\n' ' ')"
  pdf_test $g "fontspec system font by name, Arial ($e)" w_fs_$e fontsys_mac "$MDOCS/fontsys_mac.tex" -- "$e -interaction=nonstopmode fontsys_mac.tex"
done

g=confined
d=$(case_dir c_input "$DOCS/att_input.tex"); sbx "$d" -- pdflatex -shell-escape -interaction=nonstopmode att_input.tex
grep -q 'SECRET-NOT-READABLE' "$d/att_input.log" && ! grep -q DUMMY-SECRET "$d/att_input.log" && add $g '\input of a file outside scratch' 1 "not readable" || add $g '\input of a file outside scratch' 0 "$(grep -m1 PROBE "$d/att_input.log")"
d=$(case_dir c_shell "$MDOCS/att_shell_mac.tex"); sbx "$d" -- pdflatex -shell-escape -interaction=nonstopmode att_shell_mac.tex
grep -q DUMMY-SECRET "$d/leak_cat.txt" 2>/dev/null && add $g '\write18 cat secret' 0 "LEAKED" || add $g '\write18 cat secret' 1 "$(cat "$d/leak_cat.txt" 2>/dev/null)"
[ -f "$OUT/pwned_sh.txt" ] && add $g '\write18 write outside scratch' 0 "FILE WRITTEN" || add $g '\write18 write outside scratch' 1 "$(cat "$d/pwned_err.txt" 2>/dev/null)"
[ -s "$d/net_ext.txt" ] && add $g '\write18 curl example.com' 0 "CONNECTED" || add $g '\write18 curl example.com' 1 "$(cat "$d/net_ext_err.txt" 2>/dev/null)"
[ -s "$d/net_lo.txt" ] && add $g '\write18 curl 127.0.0.1 host listener' 0 "CONNECTED" || add $g '\write18 curl 127.0.0.1 host listener' 1 "$(cat "$d/net_lo_err.txt" 2>/dev/null)"
sleep 8; [ -f "$d/outlive.txt" ] && add $g 'detached child outlives the run' 0 "child survived" || add $g 'detached child outlives the run' 1 "child killed with the process group; $(summary "$d")"
d=$(case_dir c_lua "$MDOCS/att_lua_mac.tex"); sbx "$d" -- lualatex -shell-escape -interaction=nonstopmode att_lua_mac.tex
pr=$(grep PROBE "$d/att_lua_mac.log" | tr '\n' ' '); echo "$pr" | grep -q 'OPENED\|CONNECTED' || grep -q DUMMY "$d/leak_lua.txt" 2>/dev/null && add $g 'lualatex io.open / os.execute / luasocket' 0 "$pr" || add $g 'lualatex io.open / os.execute / luasocket' 1 "$pr"
for k in read write net; do
  d=$(case_dir c_py_$k "$DOCS/probe.py"); sbx "$d" -- python3 -I probe.py $k; o=$(grep PROBE "$d/.out" | tr '\n' ' ')
  echo "$o" | grep -q 'READ-OK\|WRITE-OK\|: CONNECTED' && add $g "python direct: $k" 0 "$o" || add $g "python direct: $k" 1 "$o"
done
d=$(case_dir c_misc)
sbx "$d" -- /bin/sh -c "kill -TERM $VICTIM && echo KILLED || echo denied"; kill -0 $VICTIM 2>/dev/null && add $g "signal a process outside the sandbox" 1 "$(head -1 "$d/.out") $(head -1 "$d/.err")" || add $g "signal a process outside the sandbox" 0 "victim died"
sbx "$d" -- /bin/sh -c "ps -ax | wc -l"; n=$(head -1 "$d/.out" | tr -d ' '); add $g "list other processes (ps -ax)" $([ "${n:-0}" -le 5 ] && echo 1 || echo 0) "ps lines: ${n:-none}; $(head -1 "$d/.err")"
sbx "$d" -- /bin/sh -c "ls $HOME > /dev/null 2>&1 && echo LISTABLE || echo denied"; grep -q LISTABLE "$d/.out" && add $g "list home folder" 0 LISTABLE || add $g "list home folder" 1 "$(head -1 "$d/.out")"
echo "clipboard-probe" | pbcopy 2>/dev/null
sbx "$d" -- /bin/sh -c "pbpaste 2>&1 | head -c 40"; grep -q clipboard-probe "$d/.out" && add $g "read pasteboard" 0 "READ" || add $g "read pasteboard" 1 "$(head -c 120 "$d/.out" "$d/.err" | tr '\n' ' ')"
sbx "$d" -- /bin/sh -c "launchctl list 2>&1 | head -3"; o=$(cat "$d/.out"); echo "$o" | grep -q 'com\.apple' && add $g "launchctl list" 0 "listed services" || add $g "launchctl list" 1 "$(echo "$o" | head -2 | tr '\n' ' ')"
sbx "$d" -- /bin/sh -c "osascript -e 'tell application \"Finder\" to get name of startup disk' 2>&1"; o=$(cat "$d/.out"); echo "$o" | grep -qiv 'error\|denied\|not allowed\|execution' && [ -n "$o" ] && add $g "osascript (Apple Events to Finder)" 0 "$o" || add $g "osascript (Apple Events to Finder)" 1 "$(echo "$o" | head -1)"
sbx "$d" -- /bin/sh -c "open -a TextEdit 2>&1; echo rc=\$?"; o=$(cat "$d/.out" | tr '\n' ' '); echo "$o" | grep -q 'rc=0' && add $g "open -a TextEdit" 0 "$o" || add $g "open -a TextEdit" 1 "$o"

g=limits
d=$(case_dir c_lim "$DOCS/probe.py" "$DOCS/att_loop.tex" "$DOCS/att_mem.tex" "$DOCS/mem.lua")
sbx "$d" -m 512 -- python3 -I probe.py mem; o="$(grep PROBE "$d/.out") $(grep 'ulimit' "$d/.err" | head -2 | tr '\n' ' ')"; echo "$o" | grep -q ALLOCATED && add $g "memory 512 MB via ulimit (python wants 4 GB)" 0 "$o" || add $g "memory 512 MB via ulimit (python wants 4 GB)" 1 "$o"
sbx "$d" -t 5 -- pdflatex -interaction=nonstopmode att_loop.tex; grep -q TIMEOUT "$d/.err" && add $g "wall time 5 s, TeX infinite loop (kill process group)" 1 "$(grep TIMEOUT "$d/.err") $(summary "$d")" || add $g "wall time 5 s, TeX infinite loop (kill process group)" 0 "$(summary "$d")"
before=$(ps -u "$(id -u)" | wc -l | tr -d ' ')
sbx "$d" -p $((before + 6)) -- python3 -I probe.py procs; o="$(grep PROBE "$d/.out") $(grep ulimit "$d/.err" | head -1)"; echo "$o" | grep -q 'failed [1-9]' && add $g "process limit via ulimit -u (user has $before processes; limit +6)" 1 "$o" || add $g "process limit via ulimit -u (user has $before processes; limit +6)" 0 "$o"

g=overhead
t() { perl -MTime::HiRes=time -e 'printf "%.0f", time*1000'; }
d=$(case_dir perf "$DOCS/basic.tex"); nat=(); sb=(); tn=(); ts=()
for i in 1 2 3 4 5 6 7; do
  a=$(t); ( cd "$d" && pdflatex -interaction=batchmode basic.tex > /dev/null 2>&1 ); b=$(t); nat+=($((b-a)))
  a=$(t); sbx "$d" -- pdflatex -interaction=batchmode basic.tex; b=$(t); sb+=($((b-a)))
  a=$(t); /usr/bin/true; b=$(t); tn+=($((b-a)))
  a=$(t); sbx "$d" -- /usr/bin/true; b=$(t); ts+=($((b-a)))
done
med() { printf '%s\n' "$@" | sort -n | sed -n 4p; }
add $g "pdflatex one page: native vs sandboxed, median of 7" 1 "native $(med "${nat[@]}") ms, sandboxed $(med "${sb[@]}") ms"
add $g "/usr/bin/true: native vs sandboxed, median of 7" 1 "native $(med "${tn[@]}") ms, sandboxed $(med "${ts[@]}") ms"

kill $LST $VICTIM 2>/dev/null
echo; echo "PASS: $pass  FAIL: $fail"; echo "| | | **PASS $pass / FAIL $fail** | |" >> "$RES"
