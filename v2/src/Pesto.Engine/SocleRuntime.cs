using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public enum SocleState { Absent, Valid, Invalid }

/// <summary>Embedded index of the Socle WebView2 fixed pack (156.0.4314.42). Lazy, thread-safe, fail-closed.</summary>
public static class SocleRuntime
{
    public const string Version = "156.0.4314.42";
    public const string RelativeDirectory = "wad/runtime/webview2";
    public const string ReleaseUrl = "https://github.com/M4D135/socle-windows/releases/tag/webview2-156.0.4314.42";
    private const string ExpectedSha256 = "a846d3785426fabe872f7e53188e3ba998d4a0ebde34f6af66ac4fe04acf77d3";
    private const string ResourceName = "Pesto.Socle.WebView2Index";

    private static readonly AsyncLocal<IReadOnlyDictionary<string, (long Bytes, string Sha256)>?> Override = new();
    private static readonly object Gate = new();
    private static IReadOnlyDictionary<string, (long Bytes, string Sha256)>? Index;

    public static string MissingMessage => "Pesto a besoin de Microsoft Edge WebView2. Installez le WebView2 Runtime (Evergreen), ou extrayez le pack WebView2 "
        + Version + " du Socle dans le dossier wad\\ de Pesto, puis redémarrez. " + ReleaseUrl;

    public static string InvalidMessage(string problem) => "Le dossier wad\\runtime\\webview2 ne correspond pas exactement au pack WebView2 "
        + Version + " du Socle (" + problem + "). Réextrayez le ZIP du Socle dans wad\\ ou installez Evergreen. " + ReleaseUrl;

    internal static IDisposable OverrideForTests(IReadOnlyDictionary<string, (long Bytes, string Sha256)> files)
    {
        Override.Value = files;
        return new OverrideScope(Override);
    }

    private sealed class OverrideScope(AsyncLocal<IReadOnlyDictionary<string, (long Bytes, string Sha256)>?> slot) : IDisposable
    {
        public void Dispose() => slot.Value = null;
    }

    private static IReadOnlyDictionary<string, (long Bytes, string Sha256)> Load()
    {
        if (Override.Value is { } test) return test;
        lock (Gate) { return Index ??= Parse(); }
    }

    private static IReadOnlyDictionary<string, (long Bytes, string Sha256)> Parse()
    {
        using var stream = typeof(SocleRuntime).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new PestoException("package.socle", "La ressource embarquée de l’index Socle est introuvable.");
        var hash = Convert.ToHexStringLower(SHA256.HashData(stream));
        if (!string.Equals(hash, ExpectedSha256, StringComparison.Ordinal))
            throw new PestoException("package.socle", "L’empreinte de la ressource embarquée de l’index Socle ne correspond pas.");
        stream.Position = 0;
        using var doc = JsonDocument.Parse(stream, new() { MaxDepth = 4 });
        var root = doc.RootElement;
        if (root.GetProperty("component").GetString() != "webview2-fixed")
            throw new PestoException("package.socle", "Le composant déclaré dans l’index Socle est incorrect.");
        if (root.GetProperty("version").GetString() != Version)
            throw new PestoException("package.socle", "La version déclarée dans l’index Socle ne correspond pas.");
        if (root.GetProperty("root").GetString() != "runtime/webview2")
            throw new PestoException("package.socle", "La racine déclarée dans l’index Socle est incorrecte.");
        var fileCount = root.GetProperty("file_count").GetInt32();
        var result = new Dictionary<string, (long Bytes, string Sha256)>(StringComparer.OrdinalIgnoreCase);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        int count = 0;
        foreach (var entry in root.GetProperty("files").EnumerateArray())
        {
            count++;
            var path = entry.GetProperty("path").GetString()!;
            if (!path.StartsWith("runtime/webview2/", StringComparison.Ordinal) || path.Contains("..") || path.Contains('\\')
                || path.Split('/').Any(s => s.Length == 0))
                throw new PestoException("package.socle", "Chemin invalide dans l’index Socle : " + path);
            var sha = entry.GetProperty("sha256").GetString()!;
            if (!Regex.IsMatch(sha, "^[a-f0-9]{64}$"))
                throw new PestoException("package.socle", "Empreinte invalide dans l’index Socle : " + path);
            var bytes = entry.GetProperty("bytes").GetInt64();
            if (bytes < 0)
                throw new PestoException("package.socle", "Taille négative dans l’index Socle : " + path);
            if (!seen.Add(path))
                throw new PestoException("package.socle", "Doublon dans l’index Socle : " + path);
            result["wad/" + path] = (bytes, sha);
        }
        if (count != fileCount)
            throw new PestoException("package.socle", "Le nombre de fichiers déclaré dans l’index Socle ne correspond pas.");
        if (!result.ContainsKey("wad/runtime/webview2/msedgewebview2.exe"))
            throw new PestoException("package.socle", "L’exécutable msedgewebview2.exe est absent de l’index Socle.");
        return result;
    }

    public static (SocleState State, string? Problem) Inspect(string packRoot, bool deep)
    {
        var socleDir = Path.Combine(packRoot, RelativeDirectory);
        if (!System.IO.Directory.Exists(socleDir)) return (SocleState.Absent, null);
        UpdatePackage.RequireNoLinks(socleDir);
        var index = Load();
        var actual = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        var pending = new Stack<string>(); pending.Push(socleDir);
        while (pending.Count != 0)
        {
            foreach (var entry in System.IO.Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                UpdatePackage.RequireNoLinks(entry);
                if (System.IO.Directory.Exists(entry)) { pending.Push(entry); continue; }
                var name = Path.GetRelativePath(packRoot, entry).Replace(Path.DirectorySeparatorChar, '/');
                actual[name] = new FileInfo(entry).Length;
            }
        }
        foreach (var key in index.Keys)
            if (!actual.ContainsKey(key)) return (SocleState.Invalid, "Fichier manquant : " + key);
        foreach (var key in actual.Keys)
            if (!index.ContainsKey(key)) return (SocleState.Invalid, "Fichier inattendu : " + key);
        foreach (var (key, (expectedBytes, _)) in index)
            if (actual[key] != expectedBytes) return (SocleState.Invalid, "Taille incorrecte : " + key);
        if (deep)
        {
            foreach (var (key, (_, expectedSha)) in index)
            {
                var filePath = Path.Combine(packRoot, key.Replace('/', Path.DirectorySeparatorChar));
                if (UpdatePackage.Hash(filePath) != expectedSha) return (SocleState.Invalid, "Empreinte incorrecte : " + key);
            }
        }
        else
        {
            var exeKey = "wad/runtime/webview2/msedgewebview2.exe";
            var exePath = Path.Combine(packRoot, exeKey.Replace('/', Path.DirectorySeparatorChar));
            if (UpdatePackage.Hash(exePath) != index[exeKey].Sha256) return (SocleState.Invalid, "Empreinte incorrecte : " + exeKey);
        }
        return (SocleState.Valid, null);
    }
}
