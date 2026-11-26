# CI setup for the Windows AppContainer matrix: TinyTeX, embeddable Python, the launcher, staged biber,
# a dummy "user file" outside the sandbox, and the attack documents pointed at it.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
$ProgressPreference = 'SilentlyContinue'

# 1. TinyTeX-1 (TeX Live, about 100 packages) plus what the matrix needs
if (-not (Test-Path "$Root\TinyTeX\bin\windows\pdflatex.exe")) {
    # the Windows asset is a 7-Zip self-extracting archive named TinyTeX-1-windows-<version>.exe
    $rel = Invoke-RestMethod 'https://api.github.com/repos/rstudio/tinytex-releases/releases/latest'
    $asset = $rel.assets | Where-Object { $_.name -like 'TinyTeX-1-windows-*.exe' } | Select-Object -First 1
    "TinyTeX release $($rel.tag_name): $($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile tinytex-sfx.exe
    & 7z x tinytex-sfx.exe "-o$Root" -y | Out-Null; Remove-Item tinytex-sfx.exe
}
$env:PATH = "$Root\TinyTeX\bin\windows;$env:PATH"
tlmgr update --self | Out-Host   # the release's tlmgr can be older than the repository requires
tlmgr install biblatex biber minted latexmk epstopdf epstopdf-pkg grfext pgf fontspec tex-gyre luaotfload xetex | Out-Host
luaotfload-tool -u | Out-Host

# 2. embeddable Python (never the runner's own Python)
if (-not (Test-Path "$Root\python\python.exe")) {
    # newest 3.13.x that has an embeddable build
    $idx = (Invoke-WebRequest 'https://www.python.org/ftp/python/' -UseBasicParsing).Content
    $vers = [regex]::Matches($idx, 'href="(3\.13\.\d+)/"') | % { [version]$_.Groups[1].Value } | Sort-Object -Descending
    foreach ($v in $vers) { try { Invoke-WebRequest "https://www.python.org/ftp/python/$v/python-$v-embed-amd64.zip" -OutFile py.zip; break } catch { } }
    "embeddable Python $v"
    Expand-Archive py.zip -DestinationPath "$Root\python"; Remove-Item py.zip
    Get-ChildItem "$Root\python\*._pth" | Rename-Item -NewName { $_.Name + '.bak' }
}

# 3. the launcher and the relocatable biber host
& "$Root\src\build.ps1"
& "$Root\src\stage-biber.ps1"

# 4. a dummy secret outside the sandbox, in the runner user's profile, and the attack documents aimed at it
$out = Join-Path $env:USERPROFILE 'yk-outside'
New-Item -ItemType Directory -Force $out | Out-Null
'DUMMY-SECRET-ci (test file, not real data)' | Set-Content "$out\secret.txt" -Encoding ascii
New-Item -ItemType Directory -Force "$Root\outside" | Out-Null   # the matrix checks $Root\outside for pwned_*.txt
$fwd = $out -replace '\\', '/'
$str = ($out -split '\\') -join '\string\'
Get-ChildItem "$Root\tests\docs" -Include *.tex, *.py -Recurse | ForEach-Object {
    $t = [IO.File]::ReadAllText($_.FullName)
    $t = $t.Replace('@OUTSIDE_FWD@', $fwd).Replace('@OUTSIDE_STR@', $str).Replace('@OUTSIDE_WIN@', $out)
    [IO.File]::WriteAllText($_.FullName, $t)
}
"outside folder: $out"
