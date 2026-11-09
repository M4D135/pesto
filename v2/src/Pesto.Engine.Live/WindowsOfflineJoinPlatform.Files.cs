using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace Pesto.Engine.Live;

public sealed partial class WindowsOfflineJoinPlatform
{
    public byte[] ProtectBlob(byte[] plaintext)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        if (plaintext.Length is < 1 or > OfflineJoinRules.MaximumBlobBytes) throw Invalid();
        return Dpapi(plaintext, protect: true);
    }

    public byte[] UnprotectBlob(byte[] protectedBytes)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        if (protectedBytes.Length is < 1 or > OfflineJoinRules.MaximumSecretBytes) throw Invalid();
        return Dpapi(protectedBytes, protect: false);
    }

    private static byte[] Dpapi(byte[] value, bool protect)
    {
        var memory = Marshal.AllocHGlobal(value.Length);
        try
        {
            Marshal.Copy(value, 0, memory, value.Length); var input = new DataBlob { Size = value.Length, Data = memory };
            DataBlob output;
            // CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE. The secret is never a session credential.
            var ok = protect ? CryptProtectData(ref input, null, 0, 0, 0, 5, out output)
                : CryptUnprotectData(ref input, 0, 0, 0, 0, 1, out output);
            if (!ok) throw Invalid();
            try
            {
                if (output.Size is < 1 || output.Size > (protect ? OfflineJoinRules.MaximumSecretBytes : OfflineJoinRules.MaximumBlobBytes)) throw Invalid();
                var result = new byte[output.Size]; Marshal.Copy(output.Data, result, 0, result.Length); return result;
            }
            finally { Zero(output.Data, output.Size); _ = LocalFree(output.Data); }
        }
        finally { Zero(memory, value.Length); Marshal.FreeHGlobal(memory); }
    }

    public void SecureDirectory(string directory)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        OfflineJoinStore.RequirePlain(directory); RequireOwnedDirectory(directory);
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var acl = new DirectorySecurity(); acl.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        foreach (var sid in new[] { WellKnownSidType.LocalSystemSid, WellKnownSidType.BuiltinAdministratorsSid })
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid, null), FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(directory).SetAccessControl(acl);
        var read = new DirectoryInfo(directory).GetAccessControl();
        var rules = read.GetAccessRules(true, true, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>().ToArray();
        if (!read.AreAccessRulesProtected || rules.Length != 2) throw Invalid();
        foreach (var rule in rules)
            if (rule.AccessControlType != AccessControlType.Allow || rule.IdentityReference.Value is not ("S-1-5-18" or "S-1-5-32-544")
                || (rule.FileSystemRights & FileSystemRights.FullControl) != FileSystemRights.FullControl) throw Invalid();
    }

    private void RequireOwnedDirectory(string directory)
    {
        OfflineJoinStore.RequirePlain(gpRoot);
        var root = Path.Combine(Path.GetFullPath(gpRoot), "V2", "offline-join");
        var full = Path.GetFullPath(directory);
        if (OfflineJoinRules.Same(full, Path.Combine(Path.GetFullPath(gpRoot), "V2", "receipts")) || OfflineJoinRules.Same(full, root)) return;
        var relative = Path.GetRelativePath(root, full).Split(Path.DirectorySeparatorChar);
        if (relative.Length is not (1 or 2) || !OfflineJoinRules.IsHash(relative[0])
            || relative.Length == 2 && relative[1] != "events") throw Invalid();
    }

    public void DeleteExact(string path, string expectedSha256)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        if (!OfflineJoinRules.IsHash(expectedSha256) || Path.GetFileName(path) is not ("blob.protected" or "blob.odj.tmp")) throw Invalid();
        OfflineJoinStore.RequirePlain(path); var directory = Path.GetDirectoryName(path) ?? throw Invalid(); RequireOwnedDirectory(directory);
        if (!OfflineJoinRules.IsHash(Path.GetFileName(directory))) throw Invalid();
        // Share-none, OPEN_REPARSE_POINT, GENERIC_READ + DELETE. Closing this handle deletes this exact object.
        using var handle = CreateFileW(path, 0x80010000, 0, 0, 3, 0x00200080, 0);
        if (handle.IsInvalid || !GetFileInformationByHandle(handle, out var info) || info.Links != 1
            || (info.Attributes & ((uint)FileAttributes.ReparsePoint | (uint)FileAttributes.Directory)) != 0) throw Invalid();
        using var stream = new FileStream(handle, FileAccess.Read);
        if (stream.Length is < 1 or > OfflineJoinRules.MaximumSecretBytes
            || !OfflineJoinRules.Same(Convert.ToHexString(SHA256.HashData(stream)), expectedSha256)) throw Invalid();
        var disposition = new FileDisposition { DeleteFile = 1 };
        if (!SetFileInformationByHandle(handle, 4, ref disposition, 1)) throw Invalid();
    }

    private static void Zero(nint pointer, int bytes)
    {
        if (pointer == 0) return;
        for (var n = 0; n < bytes; n++) Marshal.WriteByte(pointer, n, 0);
    }
    [StructLayout(LayoutKind.Sequential)] private struct DataBlob { public int Size; public nint Data; }
    [StructLayout(LayoutKind.Sequential)] private struct FileDisposition { public byte DeleteFile; }
    [StructLayout(LayoutKind.Sequential)] private struct FileInformation
    { public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh, VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CryptProtectData(ref DataBlob input, string? description,
        nint entropy, nint reserved, nint prompt, uint flags, out DataBlob output);
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CryptUnprotectData(ref DataBlob input, nint description,
        nint entropy, nint reserved, nint prompt, uint flags, out DataBlob output);
    [DllImport("kernel32.dll", ExactSpelling = true)] private static extern nint LocalFree(nint pointer);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, nint security, uint creation, uint flags, nint template);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation info);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int kind, ref FileDisposition info, uint size);
}
