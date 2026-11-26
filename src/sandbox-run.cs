// sandbox-run: run a command inside a Windows AppContainer + Job object, no admin needed.
// Prototype for Yukibana Papers native TeX compiles.  Build: build.ps1 (uses in-box .NET Framework csc, C# 5).
//
// Usage:
//   sandbox-run [options] -- program [args...]
//   sandbox-run [options] --cmdline "literal command line"
// Options:
//   --name N           AppContainer profile name (default yk.sandbox.proto)
//   --ro DIR           grant read+execute (inheritable) to the container SID   (repeatable)
//   --rw DIR           grant modify (inheritable) to the container SID          (repeatable)
//   --low-label        also put a Low mandatory label on --rw dirs (tested: NOT needed for writes)
//   --cwd DIR          working directory (default: first --rw)
//   TEMP/TMP are forced to <first rw>\.appdata\Packages\<name>\AC\Temp (see the LOCALAPPDATA gotcha below)
//   --timeout SEC      wall clock limit, whole job is killed (default 120)
//   --mem MB           job commit limit (default 2048)
//   --procs N          active process limit (default 32)
//   --cap NAME|SID     add a capability (internetClient, privateNetwork, internetClientServer, any named
//                      capability such as registryRead / lpacCom, or S-1-15-3-...)
//   --lpac             Less Privileged AppContainer (opt out of ALL APPLICATION PACKAGES)
//   --mitigation HEX   PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY flags (64-bit hex), for experiments
//   --path DIR         prepend DIR to the sandbox PATH (repeatable)
//   --env K=V          extra environment variable (repeatable)
//   --quiet            no summary line on stderr
//   --print-sid        print the container SID and exit
//   --delete-profile   delete the AppContainer profile and exit
//   --subst X:=DIR     map drive X: to DIR in this logon session first (DefineDosDevice; per logon session)
//   --as-user NAME     PRIVILEGED VARIANT: re-run this launcher as the dedicated local user NAME (created once,
//                      elevated, by setup-dedicated-user.ps1) via CreateProcessWithLogonW. No admin at run time.
//                      The outer launcher grants NAME the same ro/rw ACEs; the inner one builds the AppContainer.
//   --cred FILE        DPAPI (CurrentUser) protected password of NAME, written by setup-dedicated-user.ps1
//   --no-appcontainer  skip SECURITY_CAPABILITIES (job only). For "AppContainer escaped" simulation tests.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;

static class N
{
    [DllImport("userenv.dll", CharSet = CharSet.Unicode)]
    public static extern int CreateAppContainerProfile(string name, string display, string desc, IntPtr caps, int capCount, out IntPtr sid);
    [DllImport("userenv.dll", CharSet = CharSet.Unicode)]
    public static extern int DeriveAppContainerSidFromAppContainerName(string name, out IntPtr sid);
    [DllImport("userenv.dll", CharSet = CharSet.Unicode)]
    public static extern int DeleteAppContainerProfile(string name);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool ConvertSidToStringSid(IntPtr sid, out IntPtr str);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool ConvertStringSidToSid(string str, out IntPtr sid);
    [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
    [DllImport("kernelbase.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool DeriveCapabilitySidsFromName(string name, out IntPtr groupSids, out uint groupCount, out IntPtr capSids, out uint capCount);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attr, IntPtr val, IntPtr size, IntPtr prev, IntPtr retSize);
    [DllImport("kernel32.dll")] public static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateJobObject(IntPtr a, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, int len);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool QueryInformationJobObject(IntPtr job, int cls, IntPtr info, int len, IntPtr ret);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateIoCompletionPort(IntPtr file, IntPtr existing, UIntPtr key, uint threads);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetQueuedCompletionStatus(IntPtr port, out uint msg, out UIntPtr key, out IntPtr ov, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetExitCodeProcess(IntPtr p, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl, uint rev, out IntPtr sd, out uint size);
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool GetSecurityDescriptorSacl(IntPtr sd, out bool present, out IntPtr sacl, out bool defaulted);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool DefineDosDevice(uint flags, string dev, string target);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
    public static extern uint SetNamedSecurityInfo(string name, int type, uint info, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl);
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
struct STARTUPINFO
{
    public int cb; public IntPtr lpReserved, lpDesktop, lpTitle;
    public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
}
[StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
[StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
[StructLayout(LayoutKind.Sequential)] struct SECURITY_CAPABILITIES { public IntPtr AppContainerSid, Capabilities; public uint CapabilityCount, Reserved; }
[StructLayout(LayoutKind.Sequential)] struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }
[StructLayout(LayoutKind.Sequential)]
struct JOBOBJECT_BASIC_LIMIT_INFORMATION
{
    public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
    public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
}
[StructLayout(LayoutKind.Sequential)] struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
[StructLayout(LayoutKind.Sequential)]
struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
{
    public JOBOBJECT_BASIC_LIMIT_INFORMATION Basic; public IO_COUNTERS Io;
    public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
}
[StructLayout(LayoutKind.Sequential)] struct JOBOBJECT_ASSOCIATE_COMPLETION_PORT { public IntPtr CompletionKey, CompletionPort; }
[StructLayout(LayoutKind.Sequential)]
struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
{
    public long TotalUserTime, TotalKernelTime, ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
    public uint TotalPageFaultCount, TotalProcesses, ActiveProcesses, TotalTerminatedProcesses;
}

static class Program
{
    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000, CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    const int ATTR_SECURITY_CAPABILITIES = 0x00020009, ATTR_ALL_APP_PACKAGES_POLICY = 0x0002000F,
              ATTR_JOB_LIST = 0x0002000D, ATTR_HANDLE_LIST = 0x00020002;
    const int HR_ALREADY_EXISTS = unchecked((int)0x800700B7);

    static int Fail(string msg) { Console.Error.WriteLine("[sandbox-run] ERROR: " + msg); return 125; }
    static string W32(string what) { return what + " failed: " + new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).Message; }

    static int Main(string[] argv)
    {
        string name = "yk.sandbox.proto", cwd = null, tmp = null, rawCmd = null;
        var ro = new List<string>(); var rw = new List<string>(); var caps = new List<string>();
        var paths = new List<string>(); var extraEnv = new List<string>();
        int timeout = 120, memMb = 2048, procs = 32; bool lpac = false, quiet = false, label = false, printSid = false, delProfile = false;
        var cmd = new List<string>(); ulong mitig = 0;
        string asUser = null, credFile = null; bool noAc = false; var substs = new List<string>(); var innerArgs = new List<string>();
        int i = 0;
        for (; i < argv.Length; i++)
        {
            string a = argv[i];
            if (a == "--") { i++; break; }
            if (a == "--as-user") { asUser = argv[++i]; continue; }
            if (a == "--cred") { credFile = Path.GetFullPath(argv[++i]); continue; }
            innerArgs.Add(a);
            if (a != "--lpac" && a != "--low-label" && a != "--quiet" && a != "--print-sid" && a != "--delete-profile" && a != "--no-appcontainer" && i + 1 < argv.Length) innerArgs.Add(argv[i + 1]);
            switch (a)
            {
                case "--subst": substs.Add(argv[++i]); break;
                case "--no-appcontainer": noAc = true; break;
                case "--name": name = argv[++i]; break;
                case "--ro": ro.Add(Path.GetFullPath(argv[++i])); break;
                case "--rw": rw.Add(Path.GetFullPath(argv[++i])); break;
                case "--cwd": cwd = Path.GetFullPath(argv[++i]); break;
                case "--timeout": timeout = int.Parse(argv[++i]); break;
                case "--mem": memMb = int.Parse(argv[++i]); break;
                case "--procs": procs = int.Parse(argv[++i]); break;
                case "--cap": caps.Add(argv[++i]); break;
                case "--lpac": lpac = true; break;
                case "--mitigation": mitig = Convert.ToUInt64(argv[++i], 16); break;
                case "--low-label": label = true; break;
                case "--path": paths.Add(Path.GetFullPath(argv[++i])); break;
                case "--env": extraEnv.Add(argv[++i]); break;
                case "--cmdline": rawCmd = argv[++i]; break;
                case "--quiet": quiet = true; break;
                case "--print-sid": printSid = true; break;
                case "--delete-profile": delProfile = true; break;
                default: return Fail("unknown option " + a);
            }
        }
        for (; i < argv.Length; i++) cmd.Add(argv[i]);
        if (asUser != null) return RunAsUser(asUser, credFile, ro, rw, paths, innerArgs, cmd, cwd, timeout);
        if (delProfile) { int h = N.DeleteAppContainerProfile(name); Console.WriteLine("DeleteAppContainerProfile hr=0x" + h.ToString("X8")); return h == 0 ? 0 : 1; }
        var defined = new List<string[]>();
        foreach (var m in substs)
        {
            int eq = m.IndexOf('='); string dev = m.Substring(0, eq), target = m.Substring(eq + 1);
            if (Directory.Exists(dev + "\\")) continue;
            if (!N.DefineDosDevice(0, dev, target)) return Fail(W32("DefineDosDevice(" + m + ")"));
            defined.Add(new[] { dev, target });
        }
        try { return Run(name, cwd, tmp, rawCmd, ro, rw, caps, paths, extraEnv, timeout, memMb, procs, lpac, quiet, label, printSid, cmd, mitig, noAc); }
        finally { foreach (var d in defined) N.DefineDosDevice(2 /*DDD_REMOVE_DEFINITION*/ | 4 /*EXACT_MATCH*/, d[0], d[1]); }
    }

    static int Run(string name, string cwd, string tmp, string rawCmd, List<string> ro, List<string> rw, List<string> caps,
                   List<string> paths, List<string> extraEnv, int timeout, int memMb, int procs, bool lpac, bool quiet, bool label,
                   bool printSid, List<string> cmd, ulong mitig, bool noAc)
    {


        var sw = Stopwatch.StartNew();
        // 1. AppContainer profile -> SID
        IntPtr sid;
        int hr = N.CreateAppContainerProfile(name, name, "Yukibana Papers sandbox prototype", IntPtr.Zero, 0, out sid);
        if (hr == HR_ALREADY_EXISTS) hr = N.DeriveAppContainerSidFromAppContainerName(name, out sid);
        if (hr != 0) return Fail("AppContainer profile: hr=0x" + hr.ToString("X8"));
        IntPtr sidStrP; N.ConvertSidToStringSid(sid, out sidStrP);
        string sidStr = Marshal.PtrToStringUni(sidStrP); N.LocalFree(sidStrP);
        if (printSid) { Console.WriteLine(sidStr); return 0; }
        var sidObj = new SecurityIdentifier(sidStr);

        // 2. ACLs (idempotent)
        foreach (var d in ro) Grant(d, sidObj, FileSystemRights.ReadAndExecute | FileSystemRights.Synchronize);
        foreach (var d in rw)
        {
            Directory.CreateDirectory(d);
            Grant(d, sidObj, FileSystemRights.Modify | FileSystemRights.Synchronize);
            if (label) SetLowLabel(d);
        }
        if (cwd == null) cwd = rw.Count > 0 ? rw[0] : Environment.CurrentDirectory;
        // GOTCHA: for an AppContainer, CreateProcess fails with ERROR_ENVVAR_NOT_FOUND (203) unless LOCALAPPDATA is in the
        // environment block, and kernelbase then REWRITES LOCALAPPDATA/TEMP/TMP to <LOCALAPPDATA>\Packages\<name>\AC[\Temp].
        // So we point LOCALAPPDATA into the scratch folder and pre-create the folder it will rewrite to.
        string lad = rw.Count > 0 ? Path.Combine(rw[0], ".appdata") : null;
        if (lad != null) { tmp = Path.Combine(lad, "Packages", name, "AC", "Temp"); Directory.CreateDirectory(tmp); }
        long aclMs = sw.ElapsedMilliseconds;

        // 3. environment (scrubbed)
        string sysRoot = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
        var env = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var pathList = new List<string>(paths);
        pathList.Add(sysRoot + @"\System32"); pathList.Add(sysRoot); pathList.Add(sysRoot + @"\System32\Wbem");
        pathList.Add(sysRoot + @"\System32\WindowsPowerShell\v1.0");
        env["PATH"] = string.Join(";", pathList);
        env["SystemRoot"] = sysRoot; env["windir"] = sysRoot; env["SystemDrive"] = sysRoot.Substring(0, 2);
        env["ComSpec"] = sysRoot + @"\System32\cmd.exe";
        env["PATHEXT"] = ".COM;.EXE;.BAT;.CMD";
        env["NUMBER_OF_PROCESSORS"] = Environment.ProcessorCount.ToString();
        env["PROCESSOR_ARCHITECTURE"] = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE") ?? "AMD64";
        env["OS"] = "Windows_NT";
        env["USERNAME"] = "sandbox";
        if (tmp != null) { env["TEMP"] = tmp; env["TMP"] = tmp; }
        if (lad != null) env["LOCALAPPDATA"] = lad;
        if (rw.Count > 0) { env["HOME"] = rw[0]; env["USERPROFILE"] = rw[0]; }
        foreach (var kv in extraEnv) { int eq = kv.IndexOf('='); env[kv.Substring(0, eq)] = kv.Substring(eq + 1); }
        var envSb = new StringBuilder();
        foreach (var kv in env) envSb.Append(kv.Key).Append('=').Append(kv.Value).Append('\0');
        envSb.Append('\0');
        IntPtr envBlock = Marshal.StringToHGlobalUni(envSb.ToString());

        // command line
        string cmdLine;
        if (rawCmd != null) cmdLine = rawCmd;
        else
        {
            if (cmd.Count == 0) return Fail("no command");
            string exe = Resolve(cmd[0], pathList);
            if (exe == null) return Fail("not found on sandbox PATH: " + cmd[0]);
            var parts = new List<string>(); parts.Add(Quote(exe));
            for (int k = 1; k < cmd.Count; k++) parts.Add(Quote(cmd[k]));
            cmdLine = string.Join(" ", parts);
            string ext = Path.GetExtension(exe).ToLowerInvariant();
            if (ext == ".bat" || ext == ".cmd") cmdLine = env["ComSpec"] + " /d /s /c \"" + cmdLine + "\"";
        }

        // 4. Job object
        IntPtr job = N.CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return Fail(W32("CreateJobObject"));
        var lim = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        lim.Basic.LimitFlags = 0x2000 /*KILL_ON_JOB_CLOSE*/ | 0x8 /*ACTIVE_PROCESS*/ | 0x200 /*JOB_MEMORY*/ | 0x400 /*DIE_ON_UNHANDLED_EXCEPTION*/;
        lim.Basic.ActiveProcessLimit = (uint)procs;
        lim.JobMemoryLimit = new UIntPtr((ulong)memMb * 1024 * 1024);
        if (!SetJob(job, 9, lim)) return Fail(W32("SetInformationJobObject(limits)"));
        SetJob(job, 4, (uint)0xFF); // JOBOBJECT_BASIC_UI_RESTRICTIONS: all (desktop, clipboard, atoms, handles, ...)
        IntPtr port = N.CreateIoCompletionPort(new IntPtr(-1), IntPtr.Zero, UIntPtr.Zero, 1);
        var acp = new JOBOBJECT_ASSOCIATE_COMPLETION_PORT(); acp.CompletionKey = job; acp.CompletionPort = port;
        if (!SetJob(job, 7, acp)) return Fail(W32("SetInformationJobObject(port)"));

        // 5. SECURITY_CAPABILITIES (no capabilities unless asked)
        var capArr = new SID_AND_ATTRIBUTES[caps.Count];
        for (int k = 0; k < caps.Count; k++)
        {
            string c = caps[k];
            if (c == "internetClient") c = "S-1-15-3-1"; else if (c == "internetClientServer") c = "S-1-15-3-2"; else if (c == "privateNetwork") c = "S-1-15-3-3";
            IntPtr cs;
            if (c.StartsWith("S-")) { if (!N.ConvertStringSidToSid(c, out cs)) return Fail("bad capability " + caps[k]); }
            else
            {   // named capability (e.g. registryRead, lpacCom): derive its SID
                IntPtr g, cl; uint gc, cc;
                if (!N.DeriveCapabilitySidsFromName(c, out g, out gc, out cl, out cc) || cc == 0) return Fail(W32("DeriveCapabilitySidsFromName(" + c + ")"));
                cs = Marshal.ReadIntPtr(cl);
            }
            capArr[k].Sid = cs; capArr[k].Attributes = 4; // SE_GROUP_ENABLED
        }
        IntPtr capBuf = IntPtr.Zero;
        if (caps.Count > 0)
        {
            int sz = Marshal.SizeOf(typeof(SID_AND_ATTRIBUTES));
            capBuf = Marshal.AllocHGlobal(sz * caps.Count);
            for (int k = 0; k < caps.Count; k++) Marshal.StructureToPtr(capArr[k], capBuf + k * sz, false);
        }
        var sc = new SECURITY_CAPABILITIES(); sc.AppContainerSid = sid; sc.Capabilities = capBuf; sc.CapabilityCount = (uint)caps.Count;
        IntPtr scBuf = Marshal.AllocHGlobal(Marshal.SizeOf(sc)); Marshal.StructureToPtr(sc, scBuf, false);
        IntPtr lpacBuf = Marshal.AllocHGlobal(4); Marshal.WriteInt32(lpacBuf, 1);
        IntPtr jobBuf = Marshal.AllocHGlobal(IntPtr.Size); Marshal.WriteIntPtr(jobBuf, job);

        // inherit only the std handles
        var hs = new List<IntPtr>();
        IntPtr[] std = { N.GetStdHandle(-10), N.GetStdHandle(-11), N.GetStdHandle(-12) };
        foreach (var h in std) if (h != IntPtr.Zero && h != new IntPtr(-1) && !hs.Contains(h) && N.SetHandleInformation(h, 1, 1)) hs.Add(h);
        IntPtr hlBuf = Marshal.AllocHGlobal(IntPtr.Size * Math.Max(1, hs.Count));
        for (int k = 0; k < hs.Count; k++) Marshal.WriteIntPtr(hlBuf, k * IntPtr.Size, hs[k]);

        string skip = Environment.GetEnvironmentVariable("SBX_DEBUG_SKIP") ?? "";
        if (skip.Contains("handles")) hs.Clear();
        bool skSc = skip.Contains("sc") || noAc, skJob = skip.Contains("job");
        int nAttr = (skSc ? 0 : 1) + (skJob ? 0 : 1) + (lpac ? 1 : 0) + (hs.Count > 0 ? 1 : 0) + (mitig != 0 ? 1 : 0);
        IntPtr mitBuf = Marshal.AllocHGlobal(8); Marshal.WriteInt64(mitBuf, (long)mitig);
        IntPtr alSize = IntPtr.Zero; N.InitializeProcThreadAttributeList(IntPtr.Zero, nAttr, 0, ref alSize);
        IntPtr al = Marshal.AllocHGlobal(alSize);
        if (!N.InitializeProcThreadAttributeList(al, nAttr, 0, ref alSize)) return Fail(W32("InitializeProcThreadAttributeList"));
        if (!skSc && !N.UpdateProcThreadAttribute(al, 0, (IntPtr)ATTR_SECURITY_CAPABILITIES, scBuf, (IntPtr)Marshal.SizeOf(sc), IntPtr.Zero, IntPtr.Zero)) return Fail(W32("attr SECURITY_CAPABILITIES"));
        if (!skJob && !N.UpdateProcThreadAttribute(al, 0, (IntPtr)ATTR_JOB_LIST, jobBuf, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) return Fail(W32("attr JOB_LIST"));
        if (lpac && !N.UpdateProcThreadAttribute(al, 0, (IntPtr)ATTR_ALL_APP_PACKAGES_POLICY, lpacBuf, (IntPtr)4, IntPtr.Zero, IntPtr.Zero)) return Fail(W32("attr ALL_APPLICATION_PACKAGES_POLICY"));
        if (hs.Count > 0 && !N.UpdateProcThreadAttribute(al, 0, (IntPtr)ATTR_HANDLE_LIST, hlBuf, (IntPtr)(IntPtr.Size * hs.Count), IntPtr.Zero, IntPtr.Zero)) return Fail(W32("attr HANDLE_LIST"));

        if (mitig != 0 && !N.UpdateProcThreadAttribute(al, 0, (IntPtr)0x00020007, mitBuf, (IntPtr)8, IntPtr.Zero, IntPtr.Zero)) return Fail(W32("attr MITIGATION_POLICY"));
        var si = new STARTUPINFOEX();
        si.StartupInfo.cb = Marshal.SizeOf(si); si.lpAttributeList = al;
        si.StartupInfo.dwFlags = 0x100; // STARTF_USESTDHANDLES
        si.StartupInfo.hStdInput = std[0]; si.StartupInfo.hStdOutput = std[1]; si.StartupInfo.hStdError = std[2];
        PROCESS_INFORMATION pi;
        long t0 = sw.ElapsedMilliseconds;
        if (!N.CreateProcess(null, new StringBuilder(cmdLine), IntPtr.Zero, IntPtr.Zero, hs.Count > 0,
                EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | 0x08000000 /*CREATE_NO_WINDOW*/, envBlock, cwd, ref si, out pi))
            return Fail(W32("CreateProcess") + "  cmdline: " + cmdLine);
        N.CloseHandle(pi.hThread);

        // 6. wait: main process exit, or timeout; collect job events
        var events = new List<string>();
        long deadline = sw.ElapsedMilliseconds + timeout * 1000L;
        bool timedOut = false;
        while (true)
        {
            long left = deadline - sw.ElapsedMilliseconds;
            if (left <= 0) { timedOut = true; break; }
            uint msg; UIntPtr key; IntPtr ov;
            if (!N.GetQueuedCompletionStatus(port, out msg, out key, out ov, (uint)left))
            {
                if (Marshal.GetLastWin32Error() == 258) { timedOut = true; break; }
                continue;
            }
            if (msg == 3 && !events.Contains("PROCESS_LIMIT")) events.Add("PROCESS_LIMIT");
            if (msg == 10 && !events.Contains("JOB_MEMORY_LIMIT")) events.Add("JOB_MEMORY_LIMIT");
            if (msg == 4) break; // active process zero
            if ((msg == 7 || msg == 8) && ov.ToInt64() == pi.dwProcessId) break; // EXIT_PROCESS / ABNORMAL_EXIT_PROCESS
        }
        // grace period: the conhost.exe that serves the job's console exits just after the main process
        if (!timedOut && Accounting(job).ActiveProcesses > 0)
        {
            var grace = Stopwatch.StartNew();
            while (grace.ElapsedMilliseconds < 300)
            {
                uint msg; UIntPtr key; IntPtr ov;
                if (!N.GetQueuedCompletionStatus(port, out msg, out key, out ov, (uint)Math.Max(1, 300 - grace.ElapsedMilliseconds))) break;
                if (msg == 4) break;
            }
        }
        uint stragglers = Accounting(job).ActiveProcesses;
        if (timedOut) events.Add("TIMEOUT");
        if (stragglers > 0 && !timedOut) events.Add("KILLED_" + stragglers + "_STRAGGLERS");
        if (timedOut || stragglers > 0) { N.TerminateJobObject(job, 0xC0000001); N.WaitForSingleObject(pi.hProcess, 5000); }
        uint code; N.GetExitCodeProcess(pi.hProcess, out code);
        if (timedOut) code = 124;
        long wall = sw.ElapsedMilliseconds - t0;
        var acc = Accounting(job);
        var ext2 = QueryExt(job);
        if (!quiet)
            Console.Error.WriteLine(string.Format("[sandbox-run] exit={0} wall={1}ms setup={2}ms procs={3} peakJobMem={4}MB events={5}{6}",
                code == 0xC0000001 ? "KILLED" : ((int)code).ToString(), wall, aclMs, acc.TotalProcesses,
                ext2.PeakJobMemoryUsed.ToUInt64() / (1024 * 1024), events.Count == 0 ? "none" : string.Join(",", events), lpac ? " lpac" : ""));
        N.CloseHandle(pi.hProcess);
        N.CloseHandle(job); // KILL_ON_JOB_CLOSE
        return (int)code;
    }

    static void Grant(string dir, SecurityIdentifier sid, FileSystemRights rights)
    {
        var di = new DirectoryInfo(dir);
        var sec = di.GetAccessControl(AccessControlSections.Access);
        foreach (FileSystemAccessRule r in sec.GetAccessRules(true, false, typeof(SecurityIdentifier)))
            if (r.IdentityReference.Equals(sid) && r.AccessControlType == AccessControlType.Allow && (r.FileSystemRights & rights) == rights
                && r.InheritanceFlags == (InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit)) return;
        sec.AddAccessRule(new FileSystemAccessRule(sid, rights, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        di.SetAccessControl(sec); // SetNamedSecurityInfo propagates the inheritable ACE to existing children
    }

    // PRIVILEGED VARIANT, outer half: runs as the real user, no admin. Grants the dedicated user the same folders,
    // then starts this launcher again as that user (CreateProcessWithLogonW via .NET Process.Start + UserName).
    static int RunAsUser(string user, string credFile, List<string> ro, List<string> rw, List<string> paths,
                         List<string> innerArgs, List<string> cmd, string cwd, int timeout)
    {
        if (credFile == null) return Fail("--as-user needs --cred");
        var sw = Stopwatch.StartNew();
        string pwd;
        try { pwd = Encoding.UTF8.GetString(System.Security.Cryptography.ProtectedData.Unprotect(File.ReadAllBytes(credFile), null, System.Security.Cryptography.DataProtectionScope.CurrentUser)); }
        catch (Exception e) { return Fail("cannot decrypt " + credFile + ": " + e.Message); }
        SecurityIdentifier usid;
        try { usid = (SecurityIdentifier)new NTAccount(Environment.MachineName, user).Translate(typeof(SecurityIdentifier)); }
        catch (Exception e) { return Fail("no such local user " + user + ": " + e.Message); }
        string self = System.Reflection.Assembly.GetEntryAssembly().Location;
        foreach (var d in ro) if (Directory.Exists(d)) Grant(d, usid, FileSystemRights.ReadAndExecute | FileSystemRights.Synchronize);
        foreach (var d in rw) { Directory.CreateDirectory(d); Grant(d, usid, FileSystemRights.Modify | FileSystemRights.Synchronize); }
        GrantFile(self, usid);
        long grantMs = sw.ElapsedMilliseconds;
        var parts = new List<string>();
        foreach (var a in innerArgs) parts.Add(Quote(a));
        if (cmd.Count > 0) { parts.Add("--"); foreach (var a in cmd) parts.Add(Quote(a)); }
        var psi = new ProcessStartInfo(self, string.Join(" ", parts));
        psi.UseShellExecute = false; psi.UserName = user; psi.Domain = "."; psi.LoadUserProfile = true;
        var sec = new System.Security.SecureString(); foreach (char ch in pwd) sec.AppendChar(ch); sec.MakeReadOnly(); psi.Password = sec;
        psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
        psi.WorkingDirectory = cwd ?? (rw.Count > 0 ? rw[0] : Path.GetDirectoryName(self));
        Process p;
        try { p = Process.Start(psi); }
        catch (Exception e) { return Fail("start as " + user + " failed: " + e.Message); }
        p.StandardInput.Close();
        var so = Console.OpenStandardOutput(); var se = Console.OpenStandardError();
        var t1 = p.StandardOutput.BaseStream.CopyToAsync(so); var t2 = p.StandardError.BaseStream.CopyToAsync(se);
        if (!p.WaitForExit((timeout + 30) * 1000)) { try { p.Kill(); } catch { } Console.Error.WriteLine("[sandbox-run] outer: inner launcher hung, killed"); return 124; }
        t1.Wait(5000); t2.Wait(5000); so.Flush(); se.Flush();
        Console.Error.WriteLine(string.Format("[sandbox-run] outer as-user={0} grant={1}ms total={2}ms", user, grantMs, sw.ElapsedMilliseconds));
        return p.ExitCode;
    }

    static void GrantFile(string file, SecurityIdentifier sid)
    {
        var fi = new FileInfo(file); var sec = fi.GetAccessControl(AccessControlSections.Access);
        foreach (FileSystemAccessRule r in sec.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            if (r.IdentityReference.Equals(sid) && r.AccessControlType == AccessControlType.Allow && (r.FileSystemRights & FileSystemRights.ReadAndExecute) == FileSystemRights.ReadAndExecute) return;
        sec.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.ReadAndExecute | FileSystemRights.Synchronize, AccessControlType.Allow));
        fi.SetAccessControl(sec);
    }

    static void SetLowLabel(string dir)
    {
        IntPtr sd; uint sz; bool present, def; IntPtr sacl;
        if (!N.ConvertStringSecurityDescriptorToSecurityDescriptor("S:(ML;OICI;NW;;;LW)", 1, out sd, out sz)) throw new Exception(W32("ConvertStringSD"));
        N.GetSecurityDescriptorSacl(sd, out present, out sacl, out def);
        uint e = N.SetNamedSecurityInfo(dir, 1 /*SE_FILE_OBJECT*/, 0x10 /*LABEL_SECURITY_INFORMATION*/, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, sacl);
        N.LocalFree(sd);
        if (e != 0) throw new Exception("SetNamedSecurityInfo(label) error " + e);
    }

    static bool SetJob<T>(IntPtr job, int cls, T v)
    {
        int sz = Marshal.SizeOf(typeof(T)); IntPtr p = Marshal.AllocHGlobal(sz);
        Marshal.StructureToPtr(v, p, false); bool ok = N.SetInformationJobObject(job, cls, p, sz); Marshal.FreeHGlobal(p); return ok;
    }
    static JOBOBJECT_BASIC_ACCOUNTING_INFORMATION Accounting(IntPtr job)
    {
        int sz = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)); IntPtr p = Marshal.AllocHGlobal(sz);
        N.QueryInformationJobObject(job, 1, p, sz, IntPtr.Zero);
        var r = (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)Marshal.PtrToStructure(p, typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)); Marshal.FreeHGlobal(p); return r;
    }
    static JOBOBJECT_EXTENDED_LIMIT_INFORMATION QueryExt(IntPtr job)
    {
        int sz = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)); IntPtr p = Marshal.AllocHGlobal(sz);
        N.QueryInformationJobObject(job, 9, p, sz, IntPtr.Zero);
        var r = (JOBOBJECT_EXTENDED_LIMIT_INFORMATION)Marshal.PtrToStructure(p, typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)); Marshal.FreeHGlobal(p); return r;
    }

    static string Resolve(string c, List<string> pathList)
    {
        string[] exts = { "", ".exe", ".com", ".bat", ".cmd" };
        if (c.IndexOf('\\') >= 0 || c.IndexOf('/') >= 0)
        {
            foreach (var e in exts) if (File.Exists(c + e) && (e != "" || Path.HasExtension(c))) return Path.GetFullPath(c + e);
            return null;
        }
        foreach (var d in pathList)
            foreach (var e in exts)
            {
                if (e == "" && !Path.HasExtension(c)) continue;
                string p = Path.Combine(d, c + e); if (File.Exists(p)) return p;
            }
        return null;
    }

    static string Quote(string a)
    {
        if (a.Length > 0 && a.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return a;
        var sb = new StringBuilder("\""); int bs = 0;
        foreach (char ch in a)
        {
            if (ch == '\\') { bs++; continue; }
            if (ch == '"') { sb.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
            sb.Append('\\', bs).Append(ch); bs = 0;
        }
        sb.Append('\\', bs * 2).Append('"');
        return sb.ToString();
    }
}

