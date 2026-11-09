using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32;

namespace Pesto.Engine.Live;

public sealed record WindowsAutomationIdentity(string MachineId, string ComputerName, string OperatorSid,
    bool AlreadyElevated, bool DomainJoined);

/// <summary>Local native observations only. This never constructs an AD adapter, prompts, elevates or restarts.</summary>
public static class WindowsAutomationSupport
{
    public static WindowsAutomationIdentity ReadLocalIdentity()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("L'automatisation native exige Windows.");
        var raw = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography", "MachineGuid", null) as string;
        if (!Guid.TryParse(raw, out var machine) || machine == Guid.Empty)
            throw new IOException("L'identité locale MachineGuid n'est pas lisible.");
        using var identity = WindowsIdentity.GetCurrent();
        var sid = identity.User?.Value ?? throw new IOException("Le SID de l'opérateur effectif est absent.");
        return new(machine.ToString("D"), Environment.MachineName, sid,
            new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator), ReadDomainJoined());
    }

    /// <summary>Local NetGetJoinInformation only; never discovers a DC, opens AD or authenticates a user.</summary>
    public static bool ReadDomainJoined()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("L'appartenance locale exige Windows.");
        var result = NetGetJoinInformation(null, out var buffer, out var status);
        try
        {
            if (result != 0 || status is not (2 or 3))
                throw new IOException("L'appartenance locale Windows n'a pas été prouvée ; aucune action automatique.");
            return status == 3;
        }
        finally { if (buffer != IntPtr.Zero) _ = NetApiBufferFree(buffer); }
    }

    public static void SecureDirectory(string path)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("ACL Windows requise pour le registre d'automatisation.");
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal))
            throw new IOException("Le registre d'automatisation doit être local et absolu.");
        for (var current = new DirectoryInfo(Path.GetFullPath(path)); current is not null; current = current.Parent)
            if (current.Exists && (current.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Un dossier lié ne peut pas recevoir le registre d'automatisation.");
        var directory = Directory.CreateDirectory(path);
        var acl = new DirectorySecurity();
        acl.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        foreach (var sid in new[] { new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
            acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        directory.SetAccessControl(acl);
    }

    [DllImport("Netapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int NetGetJoinInformation(string? server, out IntPtr nameBuffer, out int joinStatus);
    [DllImport("Netapi32.dll")]
    private static extern int NetApiBufferFree(IntPtr buffer);
}
