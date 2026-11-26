# One-time, OUTSIDE the sandbox: turn TeX Live's biber.exe into something an AppContainer can start.
#
# Why: biber.exe is a PAR::Packer static stub linked without relocations (fixed base 0x400000), and so is the
# inner loader it extracts. An AppContainer refuses to create such a process ("{Illegal System DLL Relocation}").
# perl532.dll inside the archive IS relocatable, so we host it with perlhost.exe (C#, ASLR) and run biber's
# Perl sources from an unpacked, read-only copy of the archive.
#
# Result: <root>\biber-unpacked\biber.exe (= perlhost.exe), perl532.dll + helper DLLs, par\lib, par\script, par\shlib.
# Put <root>\biber-unpacked and its par\shlib\MSWin32-x64-multi-thread on the sandbox PATH before the TeX bin dir.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Exe  = Join-Path $Root 'TinyTeX\bin\windows\biber.exe'
$dst  = Join-Path $Root 'biber-unpacked'
$tmp  = Join-Path $Root 'scratch\par-stage'
foreach ($p in $dst, $tmp) { if (Test-Path $p) { Remove-Item -Recurse -Force $p } }
New-Item -ItemType Directory $tmp, $dst | Out-Null

# 1. let the stub extract its runtime (perl532.dll, XS dlls, the bootstrap modules) natively
$env:TEMP = $tmp; $env:TMP = $tmp
& $Exe --version | Out-Host
$cache = (Get-ChildItem $tmp -Recurse -Directory -Filter 'cache-*' | Select-Object -First 1).FullName
Get-ChildItem $cache -File | Where-Object { $_.Extension -eq '.dll' } | Copy-Item -Destination $dst

# 2. the full module tree lives in the zip appended to the exe; the bootstrap modules (lib.pm, PAR*.pm, ...)
#    are embedded separately and show up in the cache under hashed names: map them back by their package line
$py = Join-Path $Root 'python\python.exe'
$script = @'
import zipfile, glob, re, os, shutil, sys
exe, cache, dst = sys.argv[1:4]
zipfile.ZipFile(exe).extractall(os.path.join(dst, "par"))
for f in glob.glob(os.path.join(cache, "*.pm")):
    m = re.search(r"^\s*package\s+([\w:]+)\s*;", open(f, encoding="latin-1").read(), re.M)
    if not m: continue
    rel = os.path.join(dst, "par", "lib", *m.group(1).split("::")) + ".pm"
    if not os.path.exists(rel):
        os.makedirs(os.path.dirname(rel), exist_ok=True); shutil.copy(f, rel)
'@
$sf = Join-Path $PSScriptRoot 'stage-biber-unzip.py'; Set-Content $sf $script -Encoding ascii
& $py -I $sf $Exe $cache $dst

# 3. the relocatable host, under the name biber.exe
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /optimize+ /platform:x64 /out:"$dst\biber.exe" "$PSScriptRoot\perlhost.cs"
Copy-Item "$dst\biber.exe" "$dst\perlhost.exe"
Remove-Item -Recurse -Force $tmp
$env:PATH = "$dst;$dst\par\shlib\MSWin32-x64-multi-thread;$env:PATH"
& "$dst\biber.exe" --version | Out-Host
"staged: $dst  ({0:n0} MB)" -f ((Get-ChildItem $dst -Recurse -File | Measure-Object Length -Sum).Sum / 1MB)
