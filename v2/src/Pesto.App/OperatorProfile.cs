using Microsoft.Win32;
using Pesto.Core;
using System.Security.Principal;

namespace Pesto.App;

/// <summary>The original operator's SID, not the UAC administrator, owns application preferences and configuration.</summary>
internal sealed record OperatorProfile(string Sid, string LocalData)
{
    public static (OperatorProfile Profile, string[] Arguments) Resolve(string[] args)
    {
        string? requestedSid = null;
        var remaining = new List<string>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] != "--operator-sid") { remaining.Add(args[i]); continue; }
            if (requestedSid is not null || ++i == args.Length) throw Invalid();
            requestedSid = args[i];
        }
        using var identity = WindowsIdentity.GetCurrent();
        var currentSid = identity.User?.Value ?? throw Invalid();
        var sid = requestedSid ?? currentSid;
        try { if (new SecurityIdentifier(sid).Value != sid) throw Invalid(); }
        catch (ArgumentException) { throw Invalid(); }
        // A non-elevated caller cannot redirect writes to another Windows user's profile.
        if (sid != currentSid && !new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator)) throw Invalid();
        // Resolve both sides of UAC from the same machine-owned profile record. HKU Shell Folders is
        // user-writable and must not redirect an elevated process to an arbitrary filesystem path.
        using var entry = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\" + sid);
        var registered = entry?.GetValue("ProfileImagePath", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
        if (string.IsNullOrWhiteSpace(registered) || registered.Contains('%')) throw Invalid();
        var localData = Path.Combine(registered, "AppData", "Local");
        if (!Path.IsPathFullyQualified(localData) || localData.StartsWith(@"\\", StringComparison.Ordinal)
            || localData.StartsWith("//", StringComparison.Ordinal)) throw Invalid();
        localData = Path.GetFullPath(localData);
        if (sid == currentSid)
        {
            var observed = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (!Path.IsPathFullyQualified(observed)
                || !Path.GetFullPath(observed).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                    .Equals(localData.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), StringComparison.OrdinalIgnoreCase))
                throw new PestoException("profile.redirected", "Le dossier LocalAppData de ce profil est redirigé. Pesto ne peut pas garantir le même profil après une élévation avec un autre compte ; aucune configuration n’a été importée ou remplacée.");
        }
        if (new DriveInfo(Path.GetPathRoot(localData)!).DriveType == DriveType.Network) throw Invalid();
        RejectLinks(localData);
        return (new(sid, localData), remaining.ToArray());
    }

    public static void RejectLinks(string path)
    {
        for (var part = Path.GetFullPath(path); !string.IsNullOrEmpty(part); part = Path.GetDirectoryName(part) ?? "")
            if ((Directory.Exists(part) || File.Exists(part)) && (File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0)
                throw new PestoException("profile.link", "Le profil Pesto doit utiliser un chemin local sans jonction ni lien symbolique.");
    }
    private static PestoException Invalid() => new("profile.identity", "Le profil Windows d’origine ne peut pas être confirmé. Relancez Pesto depuis votre session habituelle.");
}
