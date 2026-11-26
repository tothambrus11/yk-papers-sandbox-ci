# Shared helpers for the sandbox test matrix.
$Root    = Split-Path $PSScriptRoot -Parent
$Sbx     = Join-Path $Root 'sandbox-run.exe'
$TeX     = $(if ($env:YK_TEX) { $env:YK_TEX } else { Join-Path $Root 'TinyTeX' })   # YK_TEX: alternative tree (run-full.ps1)
$TeXBin  = Join-Path $TeX 'bin\windows'     # host-side path (native runs)
# GOTCHA: kpathsea calls GetLongPathName on its own exe path, which needs LIST access on every ancestor
# directory starting at the drive root. An AppContainer cannot list C:\ (nor C:\Users), so TeX dies with
# "Can't get long name for C:\Users". No-admin fix: a per-user subst drive whose root IS the TeX tree.
$script:TeXDrive = $null; $script:SbxTeXBin = $null
function Mount-TeX {
    $free = [char[]](75..90) | ? { -not (Test-Path "$($_):\") } | Select -Last 1
    subst "$($free):" $TeX | Out-Null
    $script:TeXDrive = "$($free):"; $script:SbxTeXBin = "$($free):\bin\windows"
    $script:TeXDrive
}
function Dismount-TeX { if ($script:TeXDrive) { subst $script:TeXDrive /d | Out-Null; $script:TeXDrive = $null; $script:SbxTeXBin = $null } }
$Py      = Join-Path $Root 'python'
$Biber   = Join-Path $Root 'biber-unpacked'
$Session = Join-Path $Root $(if ($env:YK_SESSION) { $env:YK_SESSION } else { 'scratch\session' })     # the one read-write folder of a "session"

function Invoke-Raw([string]$exe, [string]$argString, [int]$waitSec = 300) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argString
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($waitSec * 1000)) { $p.Kill() }
    [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}

# Common sandbox options: TeX tree + Python read-only, session folder read-write.
function Get-SbxBase([string]$extra = '') {
    $v = Join-Path $Session 'texmf-var'
    # biber-unpacked (see src\stage-biber.ps1) goes first on PATH so `biber` resolves to biber.cmd, not the fixed-base biber.exe
    ('--ro "{0}" --ro "{1}" --ro "{6}" --rw "{2}" --path "{6}" --path "{6}\par\shlib\MSWin32-x64-multi-thread" --path "{3}" --path "{1}" ' +
     '--env TEXMFVAR="{4}" --env TEXMFCONFIG="{4}" --env TEXMFHOME="{2}\texmf" {5} {7}') -f $TeX, $Py, $Session, $(if ($script:SbxTeXBin) { $script:SbxTeXBin } else { $TeXBin }), $v, $extra, $Biber, $script:SbxGlobalExtra
}

# Run inside the sandbox. $cmd is a raw command line (passed via --cmdline when it starts with 'cmd:'),
# otherwise it is appended after '--'.  $cwd is relative to the session folder.
function Invoke-Sbx([string]$cmd, [string]$cwd = '.', [string]$extra = '', [int]$waitSec = 300) {
    $dir = Join-Path $Session $cwd
    New-Item -ItemType Directory -Force $dir | Out-Null
    $a = (Get-SbxBase $extra) + (' --cwd "{0}" ' -f $dir)
    if ($cmd.StartsWith('cmd:')) { $a += '--cmdline "' + ($cmd.Substring(4) -replace '"', '\"') + '"' }
    else { $a += '-- ' + $cmd }
    Invoke-Raw $Sbx $a $waitSec
}
