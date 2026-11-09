using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Pesto.Engine.Live;

/// <summary>Owns only the PowerShell process created for one fixed mutation worker and its descendants.
/// Attach must precede stdin: the worker cannot reach AD before membership in this kill-on-close job.
/// A parent crash therefore cannot leave a live worker after its GP mutex is abandoned. An AD command
/// already accepted remotely still remains uncertain; terminating the worker is never a rollback proof.</summary>
internal sealed class OwnedMutationJob : IDisposable
{
    private const uint KillOnJobClose = 0x00002000;
    private readonly JobHandle handle;
    private OwnedMutationJob(JobHandle handle) => this.handle = handle;

    public static OwnedMutationJob Attach(Process process)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Les mutations natives exigent Windows.");
        var job = CreateJobObjectW(0, null); // unnamed and non-inheritable; no foreign process can be attached by name
        try
        {
            if (job.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Impossible de créer le conteneur du worker ; aucune commande AD envoyée.");
            var limits = new ExtendedLimits { Basic = new BasicLimits { Flags = KillOnJobClose } };
            if (!SetInformationJobObject(job, 9, ref limits, checked((uint)Marshal.SizeOf<ExtendedLimits>())))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "La terminaison du worker avec son parent n’est pas garantie ; aucune commande AD envoyée.");
            if (!AssignProcessToJobObject(job, process.SafeHandle))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Le worker ne peut pas être rattaché au parent ; aucune commande AD envoyée.");
            return new(job);
        }
        catch
        {
            // This Process object is the direct result of Process.Start. No input was supplied yet.
            // Never enumerate or terminate a foreign Pesto/PowerShell session to make a job assignment succeed.
            try { if (!process.HasExited) process.Kill(); } catch (Exception) { }
            job.Dispose();
            throw;
        }
    }

    public void Dispose() => handle.Dispose();

    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimits
    {
        public long PerProcessUserTime, PerJobUserTime;
        public uint Flags;
        public nuint MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public nuint Affinity;
        public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimits
    {
        public BasicLimits Basic;
        public IoCounters Io;
        public nuint ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }
    private sealed class JobHandle() : SafeHandleZeroOrMinusOneIsInvalid(ownsHandle: true)
    {
        protected override bool ReleaseHandle() => CloseHandle(handle);
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern JobHandle CreateJobObjectW(nint attributes, string? name);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(JobHandle job, int informationClass, ref ExtendedLimits information, uint informationLength);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(JobHandle job, SafeProcessHandle process);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);
}
