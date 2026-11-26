# Builds sandbox-run.exe with the in-box .NET Framework 4 C# compiler (no SDK, no admin).
$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
& $csc /nologo /optimize+ /platform:x64 /r:System.Security.dll /out:"$PSScriptRoot\..\sandbox-run.exe" "$PSScriptRoot\sandbox-run.cs"
