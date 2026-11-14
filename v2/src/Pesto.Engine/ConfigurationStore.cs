using System.Text;
using System.Security.Cryptography;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Same-volume writes, durable flush, immutable backups and a cooperating process lock.</summary>
internal static class ConfigurationStore
{
    internal sealed record Snapshot(byte[] Bytes, string Stamp)
    {
        internal string Text
        {
            get
            {
                try
                {
                    // Existing V1 files may carry a BOM. The byte stamp always includes it, even though
                    // the JSON reader does not. Invalid encoding is not silently replaced by U+FFFD.
                    var bytes = Bytes.AsSpan();
                    if (bytes.StartsWith(new byte[] { 0xff, 0xfe, 0x00, 0x00 })) return new UTF32Encoding(false, false, true).GetString(bytes[4..]);
                    if (bytes.StartsWith(new byte[] { 0x00, 0x00, 0xfe, 0xff })) return new UTF32Encoding(true, false, true).GetString(bytes[4..]);
                    if (bytes.StartsWith(new byte[] { 0xff, 0xfe })) return new UnicodeEncoding(false, false, true).GetString(bytes[2..]);
                    if (bytes.StartsWith(new byte[] { 0xfe, 0xff })) return new UnicodeEncoding(true, false, true).GetString(bytes[2..]);
                    if (bytes.StartsWith(new byte[] { 0xef, 0xbb, 0xbf })) bytes = bytes[3..];
                    return new UTF8Encoding(false, true).GetString(bytes);
                }
                catch (DecoderFallbackException)
                {
                    throw new PestoException("config.encoding", "Le fichier de configuration contient un encodage invalide. Importez explicitement une configuration valide pour le remplacer avec sauvegarde.");
                }
            }
        }
    }

    internal static string LocalPath(string value)
    {
        if (!Path.IsPathFullyQualified(value) || value.StartsWith("\\\\", StringComparison.Ordinal) || value.StartsWith("//", StringComparison.Ordinal)
            || value.Contains('\0')) throw new PestoException("config.path", "Un dossier de profil local absolu est requis.");
        var path = Path.GetFullPath(value);
        RejectLinks(path);
        return path;
    }

    internal static void RejectLinks(string path)
    {
        var current = Path.GetFullPath(path);
        while (!string.IsNullOrEmpty(current))
        {
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new PestoException("config.path", "Les liens et jonctions ne sont pas admis dans le chemin de configuration.");
            current = Path.GetDirectoryName(current);
        }
    }

    internal static Snapshot ReadSnapshot(string path)
    {
        RejectLinks(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length > ConfigurationDocument.MaximumBytes) throw ConfigurationDocument.Invalid("Fichier de configuration trop volumineux.");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        return new(bytes, Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant());
    }

    internal static Snapshot? ReadOptionalSnapshot(string path)
    {
        try { return ReadSnapshot(path); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    internal static string Read(string path) => ReadSnapshot(path).Text;
    internal static string? Stamp(string path) => ReadOptionalSnapshot(path)?.Stamp;

    internal static FileStream Lock(string profileRoot)
    {
        RejectLinks(profileRoot);
        Directory.CreateDirectory(profileRoot);
        var path = Path.Combine(profileRoot, ".configuration.lock");
        RejectLinks(path);
        try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException) { throw new PestoException("config.busy", "Une autre instance modifie la configuration. Attendez puis relisez les paramètres."); }
    }

    internal static string? Write(string path, string text, string? expectedStamp, bool backup = true)
    {
        RejectLinks(path);
        if (Stamp(path) != expectedStamp) throw new PestoException("config.changed", "La configuration a changé depuis l’aperçu. Aucun remplacement effectué ; relisez-la.");
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, ".configuration-" + Guid.NewGuid().ToString("N") + ".tmp");
        string? backupPath = null;
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                stream.Write(Encoding.UTF8.GetBytes(text));
                stream.Flush(flushToDisk: true);
            }
            if (Stamp(path) != expectedStamp) throw new PestoException("config.changed", "La configuration a changé pendant la préparation. Aucun remplacement effectué.");
            if (File.Exists(path))
            {
                if (backup)
                {
                    var backupDirectory = Path.Combine(directory, "backups");
                    RejectLinks(backupDirectory);
                    Directory.CreateDirectory(backupDirectory);
                    backupPath = Path.Combine(backupDirectory, Path.GetFileName(path) + "." + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "." + Guid.NewGuid().ToString("N") + ".bak");
                }
                File.Replace(temporary, path, backupPath);
            }
            else File.Move(temporary, path);
            return backupPath;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
