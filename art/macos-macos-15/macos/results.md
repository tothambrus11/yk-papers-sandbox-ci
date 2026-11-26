| Group | Test | Result | Detail |
|---|---|---|---|
| works | pdflatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=235ms |
| works | xelatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=369ms |
| works | lualatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=4485ms |
| works | bibtex | **PASS** | pdf ok; [sbx] exit=0 wall=160ms |
| works | biber | **FAIL** |  xcrun: error: unable to load libxcrun (dlopen(/Applications/Xcode_16.4.app/Contents/Developer/usr/lib/libxcrun.dylib, 0x0005): tried: '/Applications/Xcode_16.4.app/Contents/Developer/usr/lib/libxcrun.dylib' (file system |
| works | makeindex | **PASS** | pdf ok; [sbx] exit=0 wall=126ms |
| works | latexmk full biber build | **FAIL** |    In some cases, it is best to clean out generated files before rerunning   latexmk after you've corrected the files. [sbx] exit=12 wall=1071ms  |
| works | minted, restricted shell escape | **FAIL** | ! Package minted Error: minted v3+ executable is not installed, is not added to PATH, or is not permitted with restricted shell escape; or MiKTeX is being used with -aux-directory or -output-directory without setting a T |
| works | minted, -shell-escape | **FAIL** | ! Package minted Error: minted v3+ executable is not installed or is not added to PATH; or MiKTeX is being used with -aux-directory or -output-directory without setting a TEXMF_OUTPUT_DIRECTORY environment variable. ! Pa |
| works | TikZ externalize (nested pdflatex) | **PASS** | pdf ok; [sbx] exit=0 wall=669ms |
| works | TikZ externalize: figure pdf produced | **PASS** | tikzext-figure0.pdf exists |
| works | fontspec font file from scratch (xelatex) | **PASS** | [sbx] exit=0 wall=336ms |
| works | fontspec system font by name, Arial (xelatex) | **PASS** | pdf ok; [sbx] exit=0 wall=520ms |
| works | fontspec font file from scratch (lualatex) | **PASS** | [sbx] exit=0 wall=3927ms |
| works | fontspec system font by name, Arial (lualatex) | **PASS** | pdf ok; [sbx] exit=0 wall=4223ms |
| confined | \input of a file outside scratch | **PASS** | not readable |
| confined | \write18 cat secret | **PASS** | cat: /Users/runner/yk-outside/secret.txt: Operation not permitted |
| confined | \write18 write outside scratch | **PASS** |  |
| confined | \write18 curl example.com | **PASS** | curl: (6) Could not resolve host: example.com |
| confined | \write18 curl 127.0.0.1 host listener | **PASS** | curl: (7) Failed to connect to 127.0.0.1 port 47123 after 0 ms: Couldn't connect to server |
| confined | detached child outlives the run | **PASS** | child killed with the process group; [sbx] exit=0 wall=252ms |
| confined | lualatex io.open / os.execute / luasocket | **PASS** | PROBE: lua io.open secret -> denied PROBE: os.execute ran -> 256 PROBE: luasocket connect -> Operation not permitted PROBE: luasocket loopback -> Operation not permitted [1  |
| confined | python direct: read | **PASS** |  |
| confined | python direct: write | **PASS** |  |
| confined | python direct: net | **PASS** |  |
| confined | signal a process outside the sandbox | **PASS** | denied /bin/sh: line 0: kill: (1942) - Operation not permitted |
| confined | list other processes (ps -ax) | **PASS** | ps lines: 0; /bin/sh: /bin/ps: Operation not permitted |
| confined | list home folder | **PASS** | denied |
| confined | read pasteboard | **PASS** | ==> /Users/runner/work/yk-papers-sandbox-ci/yk-papers-sandbox-ci/scratch/session/c_misc/.out <==  ==> /Users/runner/work/yk-papers-sandbox-ci/yk-papers-sandbox-ci/scratch/session/c_misc/.err <== [sbx] exit=0 wall=70ms  |
| confined | launchctl list | **PASS** |   |
| confined | osascript (Apple Events to Finder) | **PASS** | 2026-11-26 00:03:57.552 osascript[3222:11775] Connection Invalid error for service com.apple.hiservices-xpcservice. |
| confined | open -a TextEdit | **PASS** | Unable to find application named 'TextEdit' rc=1  |
| limits | memory 512 MB via ulimit (python wants 4 GB) | **PASS** |  [sbx] ulimit -v not supported [sbx] ulimit -d not supported  |
| limits | wall time 5 s, TeX infinite loop (kill process group) | **PASS** | [sbx] TIMEOUT after 5s: killing process group 3309 [sbx] exit=137 wall=5096ms |
| limits | process limit via ulimit -u (user has 277 processes; limit +6) | **FAIL** |   |
| overhead | pdflatex one page: native vs sandboxed, median of 7 | **PASS** | native 111 ms, sandboxed 230 ms |
| overhead | /usr/bin/true: native vs sandboxed, median of 7 | **PASS** | native 18 ms, sandboxed 127 ms |
| | | **PASS 32 / FAIL 5** | |
