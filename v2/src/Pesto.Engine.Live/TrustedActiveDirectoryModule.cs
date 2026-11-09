using System.Security.Cryptography;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Only the known Microsoft AD bundle in the application, its legacy V1 location, or the protected Windows system module is imported.
/// Bundle fingerprints are taken from the versioned Pesto V1 reference supplied with this project.
/// The exact manifest is pinned, including its complete dependency list; arbitrary PSModulePath modules are excluded.</summary>
public static class TrustedActiveDirectoryModule
{
    public static string? Resolve(string? v1Root, string? applicationRoot = null)
    {
        // Configuration belongs to AppData; executable dependencies belong to the portable application.
        // The optional root supports isolated filesystem tests; production always uses AppContext.BaseDirectory.
        var bundled = Path.Combine(Path.GetFullPath(applicationRoot ?? AppContext.BaseDirectory), ActiveDirectoryBundle.RelativeDirectory);
        RequirePlainPath(bundled);
        if (Directory.Exists(bundled)) return VerifyBundle(bundled);
        if (!string.IsNullOrWhiteSpace(v1Root))
        {
            var configuration = V1ConfigDirectory.Resolve(v1Root)!;
            foreach (var wad in new[] { configuration, Path.Combine(configuration, "wad") })
            {
                var manifest = Path.Combine(wad, ActiveDirectoryBundle.ManifestName);
                if (!File.Exists(manifest)) continue;
                return VerifyBundle(wad);
            }
        }
        if (!OperatingSystem.IsWindows()) return null;
        var system = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "Modules", "ActiveDirectory", "ActiveDirectory.psd1");
        if (!File.Exists(system)) return null;
        RequirePlainPath(system);
        return system;
    }

    private static string VerifyBundle(string root)
    {
        foreach (var (name, expected) in ActiveDirectoryBundle.Sha256)
        {
            var path = Path.Combine(root, name.Replace('/', Path.DirectorySeparatorChar));
            RequirePlainPath(path);
            if (!File.Exists(path)) throw InvalidBundle();
            using var stream = File.OpenRead(path);
            if (!Convert.ToHexString(SHA256.HashData(stream)).Equals(expected, StringComparison.OrdinalIgnoreCase)) throw InvalidBundle();
        }
        return Path.Combine(root, ActiveDirectoryBundle.ManifestName);
    }

    private static PestoException InvalidBundle() => new("directory.module_untrusted", "Le module ActiveDirectory livré est incomplet ou ne correspond pas aux six fichiers Microsoft connus : aucun module de ce dossier n’est exécuté. Rétablissez le pack d’origine.");

    private static void RequirePlainPath(string path)
    {
        for (string? current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
        {
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new PestoException("directory.module_untrusted", "Le module ActiveDirectory traverse un lien ou une jonction : import refusé.");
        }
    }
}
