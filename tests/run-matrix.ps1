# Reruns the whole test matrix. Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-matrix.ps1 [-Lpac]
# One-time prerequisites: TinyTeX in .\TinyTeX, embeddable Python in .\python, src\build.ps1, src\stage-biber.ps1.
# -Lpac runs every sandboxed command as a Less Privileged AppContainer (separate profile yk.sandbox.lpac).
param([switch]$Lpac)
. "$PSScriptRoot\lib.ps1"
if ($Lpac) { $script:SbxGlobalExtra = '--lpac --name yk.sandbox.lpac --cap registryRead' }
$sfx = $(if ($Lpac) { '-lpac' } else { '' }) + $env:YK_SUFFIX   # YK_SUFFIX: set by run-full.ps1
$Docs = Join-Path $PSScriptRoot 'docs'
$Outside = Join-Path $env:USERPROFILE 'yk-outside'
$results = New-Object System.Collections.ArrayList
$log = Join-Path $Root "tests\matrix-log$sfx.txt"; '' | Set-Content $log

function Add-Result($group, $name, $pass, $detail, $r) {
    $line = ($detail -replace '\r?\n', ' ').Trim(); if ($line.Length -gt 220) { $line = $line.Substring(0, 220) + '...' }
    [void]$results.Add([pscustomobject]@{ Group = $group; Test = $name; Result = $(if ($pass) { 'PASS' } else { 'FAIL' }); Detail = $line })
    Add-Content $log ("==== [$group] $name -> " + $(if ($pass) { 'PASS' } else { 'FAIL' }))
    if ($r) { Add-Content $log $r.Out; Add-Content $log $r.Err }
    Write-Host ("{0,-5} [{1}] {2}: {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $group, $name, $line)
}
function New-Case($name, [string[]]$files) {
    $d = Join-Path $Session $name
    if (Test-Path $d) { Remove-Item -Recurse -Force $d }
    New-Item -ItemType Directory -Force $d | Out-Null
    foreach ($f in $files) { Copy-Item (Join-Path $Docs $f) $d }
    $d
}
function Summary($r) { ($r.Err -split "`n" | ? { $_.StartsWith('[sandbox-run]') } | Select -Last 1) }
function LastErr($r, $dir, $job) {
    $t = ''
    $lf = Join-Path $dir "$job.log"
    if (Test-Path $lf) { $t = (Select-String -Path $lf -Pattern '^! ' | Select -First 2 | % { $_.Line }) -join ' | ' }
    if (-not $t) { $t = (($r.Out + $r.Err) -split "`n" | ? { $_ -match 'error|denied|cannot|not found|fail' } | Select -First 2) -join ' | ' }
    $t
}
function Test-Pdf($group, $name, $case, $files, $cmds, $job, [string]$extra = '') {
    $d = New-Case $case $files; $ok = $true; $r = $null; $sw = [Diagnostics.Stopwatch]::StartNew()
    foreach ($c in $cmds) { $r = Invoke-Sbx $c $case $extra; if ($r.Code -ne 0) { $ok = $false; break } }
    $pdf = Join-Path $d "$job.pdf"
    $pass = $ok -and (Test-Path $pdf)
    $det = if ($pass) { "pdf ok, {0:n1}s; {1}" -f $sw.Elapsed.TotalSeconds, (Summary $r) } else { "exit $($r.Code): " + (LastErr $r $d $job) + ' ' + (Summary $r) }
    Add-Result $group $name $pass $det $r
    @{ dir = $d; r = $r }
}

$drive = Mount-TeX; Write-Host "TeX tree mounted as $drive (subst)"
try {
# ---------- loopback listener on the host (to prove 127.0.0.1 is blocked from inside) ----------
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 47123); $listener.Start()
Remove-Item -Force -ErrorAction SilentlyContinue "$Outside\pwned*.txt"
$hostCtl = Invoke-Raw 'curl.exe' '-s -m 5 -o NUL -w "%{http_code}" http://example.com/'
Write-Host "control: host curl example.com -> $($hostCtl.Out)"

# ---------------------------------- WORKS? ----------------------------------
$g = 'works'
foreach ($e in 'pdflatex', 'xelatex', 'lualatex') { Test-Pdf $g "$e small doc" "w_$e" @('basic.tex') @("$e -interaction=nonstopmode basic.tex") 'basic' | Out-Null }
Test-Pdf $g 'bibtex' 'w_bibtex' @('bibtex.tex', 'refs.bib') @('pdflatex -interaction=nonstopmode bibtex.tex', 'bibtex bibtex', 'pdflatex -interaction=nonstopmode bibtex.tex') 'bibtex' | Out-Null
$x = Test-Pdf $g 'biber (PAR-packed exe)' 'w_biber' @('biber.tex', 'refs.bib') @('pdflatex -interaction=nonstopmode biber.tex', 'biber biber', 'pdflatex -interaction=nonstopmode biber.tex') 'biber'
$parDir = Get-ChildItem -Directory (Join-Path $Session '.appdata\Packages\yk.sandbox.proto\AC\Temp') -Filter 'par-*' -ErrorAction SilentlyContinue | Select -First 1
if ($parDir) { Add-Content $log ("biber PAR cache: " + $parDir.FullName + " size MB: " + [math]::Round(((Get-ChildItem $parDir.FullName -Recurse -File | Measure-Object Length -Sum).Sum / 1MB), 1)) }
Test-Pdf $g 'makeindex' 'w_index' @('index.tex') @('pdflatex -interaction=nonstopmode index.tex', 'makeindex index', 'pdflatex -interaction=nonstopmode index.tex') 'index' | Out-Null
$x = Test-Pdf $g 'latexmk (Perl) full biber build' 'w_latexmk' @('biber.tex', 'refs.bib') @('latexmk -pdf -interaction=nonstopmode biber.tex') 'biber'
$x = Test-Pdf $g 'minted, no -shell-escape (restricted)' 'w_minted' @('minted.tex') @('pdflatex -interaction=nonstopmode minted.tex') 'minted'
$x = Test-Pdf $g 'minted, -shell-escape' 'w_minted_se' @('minted.tex') @('pdflatex -shell-escape -interaction=nonstopmode minted.tex') 'minted'
$x = Test-Pdf $g 'epstopdf via restricted shell escape (Ghostscript tlgs)' 'w_eps' @('eps.tex', 'fig.eps') @('pdflatex -interaction=nonstopmode eps.tex') 'eps'
$x = Test-Pdf $g 'TikZ externalize (nested pdflatex)' 'w_tikz' @('tikzext.tex') @('pdflatex -shell-escape -interaction=nonstopmode tikzext.tex') 'tikzext'
if ($x.r.Code -eq 0) { $fig = Get-ChildItem $x.dir -Filter 'tikzext-figure0.pdf'; Add-Result $g 'TikZ externalize: figure pdf produced' ([bool]$fig) $(if ($fig) { 'tikzext-figure0.pdf exists' } else { 'no externalized figure' }) $null }
# control: the same two shell-escape documents OUTSIDE the sandbox, to tell a TeX crash from a sandbox effect
foreach ($c in @(@('eps', @('eps.tex', 'fig.eps'), 'pdflatex -interaction=nonstopmode eps.tex'), @('tikzext', @('tikzext.tex'), 'pdflatex -shell-escape -interaction=nonstopmode tikzext.tex'))) {
    $nd = Join-Path $Root "scratch\native_$($c[0])"; if (Test-Path $nd) { Remove-Item -Recurse -Force $nd }; New-Item -ItemType Directory $nd | Out-Null
    foreach ($f in $c[1]) { Copy-Item (Join-Path $Docs $f) $nd }
    Push-Location $nd; $env:PATH = "$TeXBin;$env:PATH"; $p = Start-Process -FilePath cmd.exe -ArgumentList "/d /c $($c[2]) > out.txt 2>&1" -Wait -PassThru -NoNewWindow; Pop-Location
    Add-Result 'control' "native (no sandbox): $($c[0]) exit code" $true ("exit $($p.ExitCode); pdf: " + (Test-Path (Join-Path $nd "$($c[0]).pdf"))) $null
}
foreach ($e in 'xelatex', 'lualatex') {
    $d = New-Case "w_ff_$e" @('fontfile.tex'); New-Item -ItemType Directory "$d\fonts" | Out-Null; Copy-Item "$Docs\texgyrepagella-regular.otf" "$d\fonts\"
    $r = Invoke-Sbx "$e -interaction=nonstopmode fontfile.tex" "w_ff_$e"
    $pass = ($r.Code -eq 0) -and (Test-Path "$d\fontfile.pdf")
    Add-Result $g "fontspec font file from scratch ($e)" $pass $(if ($pass) { Summary $r } else { "exit $($r.Code): " + (LastErr $r $d 'fontfile') }) $r
    Test-Pdf $g "fontspec system font by name, Arial ($e)" "w_fs_$e" @('fontsys.tex') @("$e -interaction=nonstopmode fontsys.tex") 'fontsys' | Out-Null
}

# ---------------------------------- CONFINED? ----------------------------------
$g = 'confined'
# \input of a file outside scratch
$d = New-Case 'c_input' @('att_input.tex'); $r = Invoke-Sbx 'pdflatex -shell-escape -interaction=nonstopmode att_input.tex' 'c_input'
$leak = ($r.Out -match 'DUMMY-SECRET') -or ((Get-Content "$d\att_input.log" -Raw) -match 'DUMMY-SECRET')
Add-Result $g '\input of user file outside scratch' ((-not $leak) -and ($r.Out -match 'SECRET-NOT-READABLE')) (($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ') $r

# \write18 cmd / powershell / write outside / network / outliving child
$d = New-Case 'c_shell' @('att_shell.tex', 'sleeper.py'); $r = Invoke-Sbx 'pdflatex -shell-escape -interaction=nonstopmode att_shell.tex' 'c_shell'
$sum = Summary $r
foreach ($f in 'leak_cmd.txt', 'leak_ps.txt') {
    $c = if (Test-Path "$d\$f") { (Get-Content "$d\$f" -Raw) } else { '(no output file)' }
    Add-Result $g "\write18 reads secret via $($f -replace 'leak_|\.txt','')" (-not ($c -match 'DUMMY-SECRET')) ("output: " + $c) $null
}
Add-Result $g '\write18 writes file outside scratch' (-not (Test-Path "$Outside\pwned_cmd.txt")) $(if (Test-Path "$Outside\pwned_cmd.txt") { 'FILE WAS WRITTEN' } else { 'no file outside' }) $null
$ne = if (Test-Path "$d\net_ext_err.txt") { Get-Content "$d\net_ext_err.txt" -Raw } else { '' }
Add-Result $g '\write18 curl http://example.com' (-not ((Test-Path "$d\net_ext.txt") -and ((Get-Item "$d\net_ext.txt").Length -gt 0))) ("curl: " + $ne) $null
$nl = if (Test-Path "$d\net_lo_err.txt") { Get-Content "$d\net_lo_err.txt" -Raw } else { '' }
Add-Result $g '\write18 curl http://127.0.0.1 (host listener)' (-not ($nl -match 'Empty reply|reset' -or ((Test-Path "$d\net_lo.txt") -and (Get-Item "$d\net_lo.txt").Length -gt 0) -or $listener.Pending())) ("curl: " + $nl + " listener pending=" + $listener.Pending()) $null
Add-Result $g 'shell-escape run summary' $true $sum $r
Start-Sleep -Seconds 8
Add-Result $g 'detached child outlives the job (start /b)' (-not (Test-Path "$d\outlive.txt")) $(if (Test-Path "$d\outlive.txt") { 'CHILD SURVIVED and wrote outlive.txt' } else { "child killed with the job; $sum" }) $null

# luatex: io.open, os.execute, luasocket
$d = New-Case 'c_lua' @('att_lua.tex'); $r = Invoke-Sbx 'lualatex -shell-escape -interaction=nonstopmode att_lua.tex' 'c_lua'
$probes = (Get-Content "$d\att_lua.log" -ErrorAction SilentlyContinue | ? { $_ -match 'PROBE' }) -join ' ; '
$ll = if (Test-Path "$d\leak_lua.txt") { Get-Content "$d\leak_lua.txt" -Raw } else { '' }
Add-Result $g 'lualatex io.open / os.execute / luasocket' (-not ($probes -match 'OPENED|CONNECTED') -and -not ($ll -match 'DUMMY-SECRET')) ($probes + ' ; os.execute output: ' + $ll) $r

# direct attacker code (python) inside the sandbox
foreach ($k in 'read', 'write', 'net') {
    $d = New-Case "c_py_$k" @('probe.py'); $r = Invoke-Sbx "python -I probe.py $k" "c_py_$k"
    $out = ($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ; '
    Add-Result $g "python direct: $k" (-not ($out -match 'READ-OK|WRITE-OK|CONNECTED')) $out $r
}
# WMI escape, registry write, listing Documents, clipboard
$d = New-Case 'c_misc' @()
$wmiMarker = "$d\wmi_escaped.txt"
$r = Invoke-Sbx ('cmd:powershell -NoProfile -Command "try { $x = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine=''cmd /c echo esc > ' + $wmiMarker + '''} -ErrorAction Stop; ''PROBE wmi: ReturnValue='' + $x.ReturnValue } catch { ''PROBE wmi: '' + $_.Exception.Message }"') 'c_misc'
Start-Sleep 2
Add-Result $g 'spawn outside job via WMI Win32_Process.Create' (-not (Test-Path $wmiMarker)) ((($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ') + $(if (Test-Path $wmiMarker) { ' ESCAPED' } else { '' })) $r
$r = Invoke-Sbx 'cmd:cmd /c "reg add HKCU\Software\YkSandboxProbe /f >nul 2>&1 && echo PROBE reg: WRITTEN || echo PROBE reg: denied"' 'c_misc'
$regWritten = Test-Path 'HKCU:\Software\YkSandboxProbe'; if ($regWritten) { Remove-Item 'HKCU:\Software\YkSandboxProbe' -Force }
Add-Result $g 'write HKCU registry key' (-not $regWritten) $r.Out.Trim() $r
$r = Invoke-Sbx ('cmd:cmd /c "dir ' + $env:USERPROFILE + '\Documents >nul 2>&1 && echo PROBE docs: LISTABLE || echo PROBE docs: denied"') 'c_misc'
Add-Result $g 'list user Documents folder (names not printed)' (-not ($r.Out -match 'LISTABLE')) $r.Out.Trim() $r
$r = Invoke-Sbx 'cmd:powershell -NoProfile -Command "try { $c = Get-Clipboard -ErrorAction Stop; ''PROBE clipboard: readable='' + [bool]$c } catch { ''PROBE clipboard: '' + $_.Exception.Message }"' 'c_misc'
Add-Result $g 'read clipboard (only a boolean is printed)' (-not ($r.Out -match 'readable=True')) $r.Out.Trim() $r

# limits
$d = New-Case 'c_lim' @('probe.py', 'att_loop.tex', 'att_mem.tex', 'mem.lua')
$r = Invoke-Sbx 'python -I probe.py mem' 'c_lim' '--mem 512'
Add-Result $g 'memory limit 512 MB (python allocates 4 GB)' ((-not ($r.Out -match 'ALLOCATED')) -and ((Summary $r) -match 'MEMORY')) ((($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ') + ' ' + (Summary $r)) $r
$r = Invoke-Sbx 'lualatex -interaction=nonstopmode att_mem.tex' 'c_lim' '--mem 512'
$mp = (Get-Content "$dtt_mem.log" -ErrorAction SilentlyContinue | ? { $_ -match 'PROBE|not enough memory' }) -join ' '
Add-Result $g 'memory limit 512 MB (lualatex lua table, wants ~100 GB)' ((Summary $r) -match 'MEMORY' -and -not ($mp -match 'allocated')) ($mp + ' ' + (LastErr $r $d 'att_mem') + ' ' + (Summary $r)) $r
$r = Invoke-Sbx 'pdflatex -interaction=nonstopmode att_loop.tex' 'c_lim' '--timeout 5'
Add-Result $g 'wall-time limit 5 s (TeX infinite loop)' ((Summary $r) -match 'TIMEOUT') (Summary $r) $r
$r = Invoke-Sbx 'python -I probe.py spin' 'c_lim' '--timeout 3'
Add-Result $g 'wall-time limit 3 s (python busy loop)' ((Summary $r) -match 'TIMEOUT') (Summary $r) $r
$r = Invoke-Sbx 'python -I probe.py procs' 'c_lim' '--procs 6'
Add-Result $g 'active process limit 6 (python spawns 20 sleepers)' (($r.Out -match 'failed [1-9]') -and ((Summary $r) -match 'PROCESS_LIMIT')) ((($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ') + ' ' + (Summary $r)) $r
$r = Invoke-Sbx 'python -I probe.py breakaway' 'c_lim'
Add-Result $g 'CREATE_BREAKAWAY_FROM_JOB' (-not ($r.Out -match 'STARTED')) (($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ') $r

# ---------------------------------- CONTROLS / VARIANTS ----------------------------------
$g = 'variant'
$d = New-Case 'v_netcap' @('probe.py'); $r = Invoke-Sbx 'python -I probe.py net' 'v_netcap' '--cap internetClient'
Add-Result $g 'control: python net WITH internetClient capability' ($r.Out -match 'example.com:80: CONNECTED') (($r.Out -split "`n" | ? { $_ -match 'PROBE' }) -join ' ; ') $r
Test-Pdf $g 'LPAC: pdflatex small doc' 'v_lpac' @('basic.tex') @('pdflatex -interaction=nonstopmode basic.tex') 'basic' '--lpac --name yk.sandbox.lpac' | Out-Null
Test-Pdf $g 'LPAC: lualatex small doc' 'v_lpac_lua' @('basic.tex') @('lualatex -interaction=nonstopmode basic.tex') 'basic' '--lpac --name yk.sandbox.lpac' | Out-Null
$d = New-Case 'v_lpac_cmd' @(); $r = Invoke-Sbx 'cmd:cmd /c echo ok' 'v_lpac_cmd' '--lpac --name yk.sandbox.lpac'
Add-Result $g 'LPAC: cmd /c echo' ($r.Code -eq 0 -and $r.Out -match 'ok') ($r.Out.Trim() + ' ' + (Summary $r)) $r

$listener.Stop()

# ---------------------------------- OVERHEAD ----------------------------------
$n = 7
$d = New-Case 'perf_sbx' @('basic.tex'); $dn = Join-Path $Root 'scratch\perf_native'
if (Test-Path $dn) { Remove-Item -Recurse -Force $dn }; New-Item -ItemType Directory $dn | Out-Null; Copy-Item "$Docs\basic.tex" $dn
$native = @(); $sbxT = @()
$oldPath = $env:PATH; $env:PATH = "$TeXBin;$env:PATH"
for ($i = 0; $i -lt $n; $i++) {
    Push-Location $dn; $t = Measure-Command { & "$TeXBin\pdflatex.exe" -interaction=batchmode basic.tex | Out-Null }; Pop-Location; $native += $t.TotalMilliseconds
    $t = Measure-Command { Invoke-Sbx 'pdflatex -interaction=batchmode basic.tex' 'perf_sbx' '--quiet' | Out-Null }; $sbxT += $t.TotalMilliseconds
}
$env:PATH = $oldPath
$tAcp = Measure-Command { for ($i = 0; $i -lt 5; $i++) { Invoke-Sbx 'cmd:cmd /c exit 0' 'perf_sbx' '--quiet' | Out-Null } }
$tNat = Measure-Command { for ($i = 0; $i -lt 5; $i++) { Invoke-Raw "$env:SystemRoot\System32\cmd.exe" '/c exit 0' | Out-Null } }
function Med($a) { $s = $a | Sort-Object; $s[[int][math]::Floor($s.Count / 2)] }
$perf = [pscustomobject]@{
    runs = $n; native_ms = ($native | % { [int]$_ }) -join ', '; sandbox_ms = ($sbxT | % { [int]$_ }) -join ', '
    native_median = [int](Med $native); sandbox_median = [int](Med $sbxT)
    cmd_exit_native_avg = [int]($tNat.TotalMilliseconds / 5); cmd_exit_sandbox_avg = [int]($tAcp.TotalMilliseconds / 5)
}
Write-Host ($perf | Format-List | Out-String)

} finally { Dismount-TeX; if ($listener) { $listener.Stop() } }
$results | Export-Csv (Join-Path $Root "tests\matrix-results$sfx.csv") -NoTypeInformation -Encoding UTF8
$perf | ConvertTo-Json | Set-Content (Join-Path $Root "tests\perf$sfx.json") -Encoding UTF8
$md = "| Group | Test | Result | Detail |`n|---|---|---|---|`n"
foreach ($x in $results) { $md += "| $($x.Group) | $($x.Test -replace '\|','/') | **$($x.Result)** | $(($x.Detail -replace '\|','/') -replace '\\','\\') |`n" }
$md | Set-Content (Join-Path $Root "tests\matrix-table$sfx.md") -Encoding UTF8
"`nPASS: {0}  FAIL: {1}" -f ($results | ? Result -eq 'PASS').Count, ($results | ? Result -eq 'FAIL').Count
