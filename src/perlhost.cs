// perlhost: a relocatable (ASLR) replacement for the fixed-base PAR loader of biber.exe.
// AppContainer refuses to start images whose relocations are stripped ("Illegal System DLL Relocation"),
// and biber.exe (static PAR stub) and its inner loader are both such images. perl532.dll itself is relocatable,
// so we host it directly: this is exactly what perl.exe does (main -> RunPerl).
// Usage: perlhost.exe <perl args...>   (perl532.dll must sit next to this exe)
using System;
using System.IO;
using System.Runtime.InteropServices;
static class PerlHost
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibrary(string p);
    [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int RunPerlFn(int argc, IntPtr argv, IntPtr env);
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string dll = Directory.GetFiles(dir, "perl5*.dll")[0];
        IntPtr h = LoadLibrary(dll);
        if (h == IntPtr.Zero) { Console.Error.WriteLine("perlhost: cannot load " + dll + " err " + Marshal.GetLastWin32Error()); return 126; }
        var run = (RunPerlFn)Marshal.GetDelegateForFunctionPointer(GetProcAddress(h, "RunPerl"), typeof(RunPerlFn));
        // Copied as biber.exe: behave like biber (no .cmd wrapper: cmd.exe cannot run a batch file by an
        // absolute C:\Users\... path inside an AppContainer, same ancestor-listing problem as kpathsea).
        string self = Path.GetFileNameWithoutExtension(System.Reflection.Assembly.GetEntryAssembly().Location).ToLowerInvariant();
        if (self == "biber")
        {
            var a = new string[args.Length + 2];
            a[0] = "-I" + Path.Combine(dir, @"par\lib"); a[1] = Path.Combine(dir, @"par\script\biber-MSWIN64");
            Array.Copy(args, 0, a, 2, args.Length); args = a;
        }
        IntPtr argv = Marshal.AllocHGlobal(IntPtr.Size * (args.Length + 2));
        Marshal.WriteIntPtr(argv, 0, Marshal.StringToHGlobalAnsi(Path.Combine(dir, "perl.exe")));
        for (int i = 0; i < args.Length; i++) Marshal.WriteIntPtr(argv, (i + 1) * IntPtr.Size, Marshal.StringToHGlobalAnsi(args[i]));
        Marshal.WriteIntPtr(argv, (args.Length + 1) * IntPtr.Size, IntPtr.Zero);
        return run(args.Length + 1, argv, IntPtr.Zero);
    }
}
