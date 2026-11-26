| Group | Test | Result | Detail |
|---|---|---|---|
| works | pdflatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=392ms |
| works | xelatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=406ms |
| works | lualatex small doc | **PASS** | pdf ok; [sbx] exit=0 wall=5928ms |
| works | bibtex | **PASS** | pdf ok; [sbx] exit=0 wall=158ms |
| works | biber | **FAIL** |  lipo: error: developer directory '/Applications/Xcode_16.4.app/Contents/Developer' isn't accessible (errno=Operation not permitted) biber: extracting x86_64 binary with lipo failed (wstatus=18944) [sbx] exit=255 wall=12 |
| works | makeindex | **PASS** | pdf ok; [sbx] exit=0 wall=151ms |
| works | latexmk full biber build | **FAIL** |    In some cases, it is best to clean out generated files before rerunning   latexmk after you've corrected the files. [sbx] exit=12 wall=924ms  |
| works | minted, restricted shell escape | **PASS** | pdf ok; [sbx] exit=0 wall=1374ms |
| works | minted, -shell-escape | **PASS** | pdf ok; [sbx] exit=0 wall=1339ms |
| works | TikZ externalize (nested pdflatex) | **PASS** | pdf ok; [sbx] exit=0 wall=681ms |
| works | TikZ externalize: figure pdf produced | **PASS** | tikzext-figure0.pdf exists |
| works | fontspec font file from scratch (xelatex) | **PASS** | [sbx] exit=0 wall=449ms |
| works | fontspec system font by name, Arial (xelatex) | **PASS** | pdf ok; [sbx] exit=0 wall=554ms |
| works | fontspec font file from scratch (lualatex) | **PASS** | [sbx] exit=0 wall=6149ms |
| works | fontspec system font by name, Arial (lualatex) | **PASS** | pdf ok; [sbx] exit=0 wall=6626ms |
| confined | \input of a file outside scratch | **PASS** | not readable |
| confined | \write18 cat secret | **PASS** | cat: /Users/runner/yk-outside/secret.txt: Operation not permitted |
| confined | \write18 write outside scratch | **PASS** |  |
| confined | \write18 curl example.com | **PASS** | curl: (6) Could not resolve host: example.com |
| confined | \write18 curl 127.0.0.1 host listener | **PASS** | curl: (7) Failed to connect to 127.0.0.1 port 47123 after 0 ms: Couldn't connect to server |
| confined | detached child outlives the run | **PASS** | child killed with the process group; [sbx] exit=0 wall=301ms |
| confined | lualatex io.open / os.execute / luasocket | **PASS** | PROBE: lua io.open secret -> denied PROBE: os.execute ran -> 256 PROBE: luasocket connect -> Operation not permitted PROBE: luasocket loopback -> Operation not permitted [1  |
| confined | python direct: read | **PASS** | PROBE read: denied (PermissionError: Operation not permitted)  |
| confined | python direct: write | **PASS** | PROBE write: denied (PermissionError)  |
| confined | python direct: net | **PASS** | PROBE tcp example.com:80: blocked (gaierror: [Errno 8] nodename nor servname provided, or not known) PROBE tcp 93.184.215.14:80: blocked (PermissionError: [Errno 1] Operation not permitted) PROBE tcp 1.1.1.1:443: blocked |
| confined | signal a process outside the sandbox | **PASS** | denied /bin/sh: line 0: kill: (6560) - Operation not permitted |
| confined | list other processes (ps -ax) | **PASS** | ps lines: 0; /bin/sh: /bin/ps: Operation not permitted |
| confined | list home folder | **PASS** | denied |
| confined | read pasteboard | **PASS** | ==> /Users/runner/work/yk-papers-sandbox-ci/yk-papers-sandbox-ci/scratch/session/c_misc/.out <==  ==> /Users/runner/work/yk-papers-sandbox-ci/yk-papers-sandbox-ci/scratch/session/c_misc/.err <== [sbx] exit=0 wall=83ms  |
| confined | launchctl list | **PASS** |   |
| confined | osascript (Apple Events to Finder) | **PASS** | 2026-11-26 01:28:49.540 osascript[8018:24832] Connection Invalid error for service com.apple.hiservices-xpcservice. |
| confined | open -a TextEdit | **PASS** | Unable to find application named 'TextEdit' rc=1  |
| limits | memory 512 MB via ulimit (python wants 4 GB) | **FAIL** | PROBE mem: ALLOCATED 4096 MB [sbx] ulimit -v not supported [sbx] ulimit -d not supported  |
| limits | wall time 5 s, TeX infinite loop (kill process group) | **PASS** | [sbx] TIMEOUT after 5s: killing process group 8625 [sbx] exit=137 wall=5152ms |
| limits | process limit via ulimit -u (user has 265 processes; limit +6) | **PASS** | PROBE procs: started 11, failed 9 ([Errno 35] Resource temporarily unavailable)  |
| overhead | pdflatex one page: native vs sandboxed, median of 7 | **PASS** | native 11 ms, sandboxed 181 ms |
| overhead | /usr/bin/true: native vs sandboxed, median of 7 | **PASS** | native 12 ms, sandboxed 97 ms |
| | | **PASS 34 / FAIL 3** | |
