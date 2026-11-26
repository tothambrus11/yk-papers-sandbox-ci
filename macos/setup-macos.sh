#!/bin/bash
# CI setup for the macOS Seatbelt matrix: TinyTeX in ~/Library/TinyTeX, extra packages, prewarmed caches,
# a dummy secret outside the sandbox, and the attack documents aimed at it. Prints the env for later steps.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ ! -x "$HOME/Library/TinyTeX/bin/universal-darwin/pdflatex" ]; then
  curl -fsSL https://yihui.org/tinytex/install-bin-unix.sh | sh >/dev/null
fi
TEX="$HOME/Library/TinyTeX"; BIN="$TEX/bin/universal-darwin"; export PATH="$BIN:$PATH"
tlmgr install biblatex biber minted latexmk pgf fontspec tex-gyre luaotfload xetex makeindex >/dev/null
luaotfload-tool -u >/dev/null 2>&1 || true
fmtutil-sys --byfmt xelatex >/dev/null 2>&1 || true
# Seatbelt matches resolved paths: Homebrew's opt/ prefix is a symlink into Cellar/, so use the real prefix
PY=$(python3 -c 'import sys, os; print(os.path.realpath(sys.prefix))')
OUT="$HOME/yk-outside"; mkdir -p "$OUT"; echo 'DUMMY-SECRET-ci (test file, not real data)' > "$OUT/secret.txt"
for f in "$ROOT"/tests/docs/*.tex "$ROOT"/tests/docs/*.py "$ROOT"/macos/docs/*.tex; do
  sed -i '' -e "s#@OUTSIDE_FWD@#$OUT#g" -e "s#@OUTSIDE_WIN@#$OUT#g" -e "s#@OUTSIDE_STR@#$OUT#g" "$f"
done
chmod +x "$ROOT"/macos/*.sh
{ echo "YK_TEX=$TEX"; echo "YK_TEXBIN=$BIN"; echo "YK_PY=$PY"; } >> "${GITHUB_ENV:-/dev/null}"
echo "TeX: $TEX  Python: $PY  ($(python3 --version))"
