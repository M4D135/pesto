using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace Pesto.Engine.Live;

/// <summary>Only a nonce-named result on one ADMIN$ path, under an ephemeral outbound token from the same explicit AD credential as COM.</summary>
public sealed class WindowsRemoteEvidenceFiles : IRemoteWindowsEvidenceFiles, IDisposable
{
    private readonly SafeAccessTokenHandle token;
    private bool disposed;

    public WindowsRemoteEvidenceFiles(PestoAdCredential credential)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("La preuve distante exige Windows.");
        if (!credential.IsAvailable) throw new InvalidOperationException("Compte AD du diagnostic indisponible.");
        var user = credential.UserName; string? domain = null;
        if (user.IndexOf('\\') is var split && split >= 0)
        {
            domain = user[..split]; user = user[(split + 1)..];
            if (domain.Length == 0 || user.Length == 0 || user.Contains('\\')) throw new InvalidOperationException("Compte AD invalide.");
        }
        var password = Marshal.StringToHGlobalUni(credential.TakePassword());
        try
        {
            if (!LogonUserW(user, domain, password, 9, 3, out token)) throw new InvalidOperationException("Contexte de lecture distante indisponible.");
        }
        finally { Marshal.ZeroFreeGlobalAllocUnicode(password); }
    }

    public static string PathFor(string computer, string nonce)
    {
        if (!RemoteWindowsEvidenceProtocol.IsName(computer) || !RemoteWindowsEvidenceProtocol.IsNonce(nonce))
            throw new ArgumentException("Cible ou nonce du résultat invalide.");
        return @"\\" + computer + @"\ADMIN$\Temp\PestoEvidence-" + nonce + ".json";
    }

    public byte[] Read(string computer, string nonce)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var path = PathFor(computer, nonce);
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        return WindowsIdentity.RunImpersonated(token, () =>
        {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
            using var stream = OpenChecked(path, delete: false);
            return ReadBounded(stream);
        });
    }

    public void DeleteExact(string computer, string nonce, string expectedSha256)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!RemoteWindowsEvidenceProtocol.IsHash(expectedSha256)) throw new ArgumentException("SHA du résultat invalide.");
        var path = PathFor(computer, nonce);
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        WindowsIdentity.RunImpersonated(token, () =>
        {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
            using var stream = OpenChecked(path, delete: true);
            var bytes = ReadBounded(stream);
            if (!string.Equals(RemoteWindowsEvidenceProtocol.Hash(bytes), expectedSha256, StringComparison.OrdinalIgnoreCase))
                throw new IOException("Résultat distant modifié ; aucune suppression.");
            var disposition = new FileDisposition { DeleteFile = 1 };
            if (!SetFileInformationByHandle(stream.SafeFileHandle, 4, ref disposition, 1))
                throw new IOException("Suppression du résultat distant non confirmée.");
            // No other handle is permitted by share-none. Closing this exact DELETE handle removes this object,
            // never a replacement at its pathname. No File.Delete or re-open-by-name is used.
        });
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static FileStream OpenChecked(string path, bool delete)
    {
        // READ_CONTROL plus GENERIC_READ; FILE_FLAG_OPEN_REPARSE_POINT, share none, OPEN_EXISTING.
        var handle = CreateFileW(path, 0x80020000 | (delete ? 0x00010000u : 0), 0, 0, 3, 0x00200080, 0);
        if (handle.IsInvalid) { handle.Dispose(); throw new IOException("Résultat distant inaccessible exclusivement."); }
        try
        {
            if (!GetFileInformationByHandle(handle, out var info) || info.Links != 1
                || (info.Attributes & ((uint)FileAttributes.ReparsePoint | (uint)FileAttributes.Directory)) != 0)
                throw new IOException("Fichier distant lié ou identité non confirmée.");
            var stream = new FileStream(handle, FileAccess.Read);
            try
            {
                var acl = stream.GetAccessControl();
                var rules = acl.GetAccessRules(includeExplicit: true, includeInherited: true, typeof(SecurityIdentifier)).Cast<FileSystemAccessRule>().ToArray();
                if (!acl.AreAccessRulesProtected || acl.GetOwner(typeof(SecurityIdentifier))?.Value != "S-1-5-18"
                    || rules.Length != 2 || rules.Select(r => r.IdentityReference.Value).Distinct(StringComparer.Ordinal).Count() != 2
                    || rules.Any(r => r.IsInherited || r.AccessControlType != AccessControlType.Allow
                        || r.IdentityReference.Value is not ("S-1-5-18" or "S-1-5-32-544")
                        || (r.FileSystemRights & FileSystemRights.FullControl) != FileSystemRights.FullControl))
                    throw new IOException("ACL SYSTEM/Administrateurs du résultat non confirmée.");
                return stream;
            }
            catch { stream.Dispose(); throw; }
        }
        catch { handle.Dispose(); throw; }
    }

    private static byte[] ReadBounded(FileStream stream)
    {
        if (stream.Length is < 1 or > RemoteWindowsEvidenceProtocol.MaximumResultBytes) throw new IOException("Résultat distant hors limites.");
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1) throw new IOException("Résultat distant instable.");
        return bytes;
    }

    public void Dispose() { if (disposed) return; disposed = true; token.Dispose(); }

    [StructLayout(LayoutKind.Sequential)] private struct FileDisposition { public byte DeleteFile; }
    [StructLayout(LayoutKind.Sequential)] private struct FileInformation
    { public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh, VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool LogonUserW(string user, string? domain, nint password, int logonType, int provider, out SafeAccessTokenHandle token);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, nint security, uint creation, uint flags, nint template);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation info);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int kind, ref FileDisposition info, uint size);
}

/// <summary>A timed-out SMB read abandons its whole result channel. Its token is disposed only when the pending call ends.</summary>
public sealed class BoundedRemoteWindowsEvidenceFiles(IRemoteWindowsEvidenceFiles inner, bool ownsInner = false,
    TimeSpan? callTimeout = null) : IRemoteWindowsEvidenceFiles, IDisposable
{
    private readonly TimeSpan timeout = callTimeout ?? TimeSpan.FromSeconds(15);
    private Task? active;
    private bool faulted, disposed;
    private T Call<T>(Func<T> operation)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (faulted) throw new TimeoutException("Canal du résultat distant déjà incertain.");
        var task = Task.Run(operation); active = task;
        try
        {
            if (!task.Wait(timeout)) { faulted = true; throw new TimeoutException("Lecture/nettoyage du résultat distant non confirmé dans le délai."); }
            return task.GetAwaiter().GetResult();
        }
        catch (AggregateException error) { throw error.InnerException ?? error; }
        finally { if (task.IsCompleted) active = null; }
    }
    public byte[] Read(string computer, string nonce) => Call(() => inner.Read(computer, nonce));
    public void DeleteExact(string computer, string nonce, string expectedSha256) => Call(() => { inner.DeleteExact(computer, nonce, expectedSha256); return true; });
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        if (!ownsInner || inner is not IDisposable value) return;
        if (active is { IsCompleted: false } pending)
            _ = pending.ContinueWith(t => { _ = t.Exception; value.Dispose(); }, TaskScheduler.Default);
        else value.Dispose();
    }
}
