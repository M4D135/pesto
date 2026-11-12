using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record UpdatePackageInfo(string Directory, string Version, string Channel, string Distribution,
    string Fingerprint, int FileCount, long Bytes, string? ConfigurationFingerprint, string WebView2Runtime = "evergreen", bool SoclePresent = false,
    string? LocalConfigurationVersion = null, string? LocalConfigurationFingerprint = null);

/// <summary>Closed portable package format. Hashes detect corruption; only the acquisition channel can attest origin.</summary>
public static class UpdatePackage
{
    public const string ManifestPath = "wad/Pesto.package.json";
    public const string SumsPath = "wad/SHA256SUMS";
    public const string Repository = "M4D135/pesto";
    public const int MaxFiles = 20000;
    public const long MaxBytes = 4L * 1024 * 1024 * 1024;
    private static readonly StringComparer Paths = StringComparer.OrdinalIgnoreCase;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static readonly string[] Required = ["Pesto.exe", ManifestPath, "wad/web/index.html"];
    /// <summary>
    /// Exact DEV sources outside the generic source extensions (branding binaries and vendored Python checks).
    /// Builds up to de527313 do not know them: their compiled validator refuses such a pack before any
    /// replacement, so a DEV installation of those builds needs a new installation, never an in-place update.
    /// </summary>
    public static readonly IReadOnlySet<string> DevExactSourcePaths = new HashSet<string>(StringComparer.Ordinal)
    {
        "wad/dev/src/Pesto.App/Assets/Pesto.ico", "wad/dev/src/Pesto.App/Assets/pesto-master.png",
        "wad/dev/web/assets/pesto.png", "wad/dev/web/assets/pesto-favicon.png",
        "wad/dev/tools/check-ui-kit.py", "wad/dev/tools/m4d-components/components.py"
    };

    public static UpdatePackageInfo Validate(string directory, string? expectedChannel = null)
    {
        directory = Path.GetFullPath(directory);
        var files = Inventory(directory);
        foreach (var required in Required.Concat(ActiveDirectoryBundle.Sha256.Keys.Select(name => ActiveDirectoryBundle.RelativeDirectory + "/" + name)))
            if (!files.ContainsKey(required)) Fail("package.incomplete", "Le pack autonome est incomplet : " + required);
        if (!files.ContainsKey(SumsPath)) Fail("package.incomplete", "Le pack ne contient pas son inventaire SHA256SUMS.");
        var manifestFile = Path.Combine(directory, ManifestPath);
        if (new FileInfo(manifestFile).Length > 64 * 1024) Fail("package.manifest", "Le manifeste du pack est trop volumineux.");
        using var doc = ReadJson(manifestFile);
        var manifest = doc.RootElement;
        Arguments.Only(manifest, "schemaVersion", "packName", "version", "channel", "entryPoint", "layout", "repository",
            "webview2Runtime", "distribution", "official", "configurationVersion", "configurationFingerprint", "sourceCommit", "qualification", "webview2Version");
        if (!manifest.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var schemaValue) || schemaValue != 2
            || Text(manifest, "packName") != "Pesto-v2-portable" || Text(manifest, "layout") != "singlefile-wad"
            || Text(manifest, "entryPoint") != "Pesto.exe" || Text(manifest, "repository") != Repository
            || Text(manifest, "webview2Runtime") is not ("fixed" or "evergreen"))
            Fail("package.manifest", "Ce pack n’est pas un pack Pesto V2 autonome compatible.");
        var version = Text(manifest, "version");
        if (!System.Version.TryParse(version, out var parsed) || parsed.Major != 2 || parsed.Build < 0)
            Fail("package.version", "La version du pack doit être une version Pesto V2 complète.");
        var channel = Text(manifest, "channel");
        if (channel is not ("PROD" or "DEV") || expectedChannel is not null && channel != expectedChannel)
            Fail("package.channel", "Le canal du pack ne correspond pas à cette installation.");
        var runtime = Text(manifest, "webview2Runtime");
        if (runtime == "fixed")
            Fail("package.edition", "Les packs PROD avec WebView2 intégré ne sont plus publiés. Installez le pack LIGHT dans un nouveau dossier et, si Evergreen manque, y extrayez le Socle.");
        if (manifest.TryGetProperty("webview2Version", out _))
            Fail("package.manifest", "Le champ webview2Version n’est plus admis dans un pack LIGHT.");
        var distribution = Text(manifest, "distribution");
        if (distribution is not ("official" or "candidate" or "custom")) Fail("package.manifest", "Type de distribution inconnu.");
        if (manifest.TryGetProperty("official", out var official) && (official.ValueKind is not (JsonValueKind.True or JsonValueKind.False)
            || official.GetBoolean() != (distribution == "official")))
            Fail("package.manifest", "La provenance déclarée du pack est incohérente.");
        var configFingerprint = manifest.TryGetProperty("configurationFingerprint", out var fingerprintValue) ? fingerprintValue.GetString() : null;
        var sumsFile = Path.Combine(directory, SumsPath);
        if (new FileInfo(sumsFile).Length > 8 * 1024 * 1024) Fail("package.hashes", "L’inventaire est trop volumineux.");
        var declared = new Dictionary<string, string>(Paths);
        foreach (var line in File.ReadLines(sumsFile, Encoding.UTF8))
        {
            if (line.Length == 0) continue;
            if (line.Length < 67 || line[64..66] != "  " || !Regex.IsMatch(line[..64], "^[a-f0-9]{64}$"))
                Fail("package.hashes", "L’inventaire SHA256SUMS est mal formé.");
            var name = NormalizeRelative(line[66..]);
            if (name == SumsPath || !declared.TryAdd(name, line[..64])) Fail("package.hashes", "L’inventaire comporte une entrée répétée ou interdite.");
        }
        // Defaults written in place (2.0.14+) stay outside the pack identity, like an extracted Socle: an undeclared file,
        // with a manifest that declares none, is validated by its own schema and fingerprint. A legacy custom pack keeps its
        // sealed file, listed in the inventory and declared by the manifest, under the historical checks below.
        string? localVersion = null, localFingerprint = null;
        var hasDefaults = files.ContainsKey(InstallationDefaults.RelativePath);
        if (hasDefaults && !declared.ContainsKey(InstallationDefaults.RelativePath) && configFingerprint is null
            && !manifest.TryGetProperty("configurationVersion", out _))
        {
            var (localBundle, _) = InstallationDefaults.ReadValid(Path.Combine(directory, "wad", "defaults", "configuration.json"));
            localVersion = ConfigurationDocument.String(localBundle, "version");
            localFingerprint = ConfigurationDocument.String(localBundle, "fingerprint");
            files.Remove(InstallationDefaults.RelativePath);
            hasDefaults = false;
        }
        foreach (var debris in files.Keys.Where(InstallationDefaults.IsDebris).ToList()) files.Remove(debris);
        if (hasDefaults && distribution != "custom" || !hasDefaults && configFingerprint is not null)
            Fail("package.defaults", "Les paramètres distribués doivent appartenir à un pack personnalisé déclaré.");
        if (hasDefaults)
        {
            if (configFingerprint is null || !Regex.IsMatch(configFingerprint, "^[a-f0-9]{64}$"))
                Fail("package.defaults", "L’empreinte de la configuration distribuée manque.");
            var defaultsPath = Path.Combine(directory, "wad/defaults/configuration.json");
            if (new FileInfo(defaultsPath).Length > 2 * 1024 * 1024) Fail("package.defaults", "La configuration distribuée dépasse la limite admise.");
            _ = ConfigurationDocument.ValidateBundle(File.ReadAllText(defaultsPath));
            using var defaults = ReadJson(defaultsPath);
            if (Text(defaults.RootElement, "fingerprint") != configFingerprint
                || Text(defaults.RootElement, "version") != Text(manifest, "configurationVersion"))
                Fail("package.defaults", "Le manifeste et la configuration distribuée ne correspondent pas.");
        }
        // A Socle extracted into wad\ is admitted only as the exact published runtime and stays outside the pack identity.
        var soclePrefix = SocleRuntime.RelativeDirectory + "/";
        var soclePresent = files.Keys.Any(p => p.StartsWith(soclePrefix, StringComparison.OrdinalIgnoreCase))
            || System.IO.Directory.Exists(Path.Combine(directory, SocleRuntime.RelativeDirectory));
        if (soclePresent)
        {
            var (state, problem) = SocleRuntime.Inspect(directory, deep: true);
            if (state != SocleState.Valid) Fail("package.socle", SocleRuntime.InvalidMessage(problem ?? "état inconnu"));
            foreach (var key in files.Keys.Where(p => p.StartsWith(soclePrefix, StringComparison.OrdinalIgnoreCase)).ToList()) files.Remove(key);
        }
        foreach (var file in files.Keys)
            if (!Allowed(file, channel)) Fail("package.file", "Fichier hors du contenu autorisé : " + file);
        if (declared.Count != files.Count - 1 || files.Keys.Where(p => p != SumsPath).Any(p => !declared.ContainsKey(p)))
            Fail("package.hashes", "L’inventaire ne couvre pas exactement tous les fichiers du pack.");
        foreach (var (name, hash) in declared)
            if (!files.ContainsKey(name) || !string.Equals(Hash(Path.Combine(directory, name)), hash, StringComparison.Ordinal))
                Fail("package.hashes", "Un fichier du pack a été modifié ou manque : " + name);
        foreach (var (name, expected) in ActiveDirectoryBundle.Sha256)
            if (Hash(Path.Combine(directory, ActiveDirectoryBundle.RelativeDirectory, name)) != expected)
                Fail("package.ad_module", "Le module ActiveDirectory ne correspond pas aux fichiers Microsoft épinglés : " + name);
        RequirePe64(Path.Combine(directory, "Pesto.exe"));
        return new(directory, version, channel, distribution, Hash(sumsFile), files.Count, files.Values.Sum(), configFingerprint, runtime, soclePresent,
            localVersion, localFingerprint);
    }

    public static Dictionary<string, long> Inventory(string directory)
    {
        if (!System.IO.Directory.Exists(directory)) Fail("package.missing", "Le dossier sélectionné n’existe pas.");
        RequireNoLinks(directory);
        var files = new Dictionary<string, long>(Paths);
        var pending = new Stack<string>(); pending.Push(directory);
        long total = 0;
        while (pending.Count != 0)
        {
            foreach (var entry in System.IO.Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                RequireNoLinks(entry);
                var name = NormalizeRelative(Path.GetRelativePath(directory, entry).Replace(Path.DirectorySeparatorChar, '/'));
                if (System.IO.Directory.Exists(entry)) { pending.Push(entry); continue; }
                var info = new FileInfo(entry);
                total = checked(total + info.Length);
                if (total > MaxBytes || !files.TryAdd(name, info.Length) || files.Count > MaxFiles)
                    Fail("package.size", "Le pack dépasse les limites ou contient des chemins ambigus.");
            }
        }
        return files;
    }

    public static void CopyToNew(string source, string destination, string? expectedFingerprint = null)
    {
        if (expectedFingerprint is not null && !Regex.IsMatch(expectedFingerprint, "^[a-f0-9]{64}$"))
            Fail("package.hashes", "L’empreinte attendue du pack copié est invalide.");
        var files = Inventory(source);
        RequireNoLinks(destination);
        if (System.IO.Directory.Exists(destination) || File.Exists(destination)) Fail("package.destination", "Le dossier de destination existe déjà.");
        System.IO.Directory.CreateDirectory(destination);
        try
        {
            foreach (var name in files.Keys)
            {
                var target = Path.Combine(destination, name);
                System.IO.Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                RequireNoLinks(Path.Combine(source, name));
                File.Copy(Path.Combine(source, name), target, false);
            }
            // A source folder/share may be replaced coherently while it is copied. Valid hashes alone
            // would accept that different pack; bind the complete destination to the reviewed snapshot.
            if (expectedFingerprint is not null && Validate(destination).Fingerprint != expectedFingerprint)
                Fail("update.changed", "Le pack copié diffère de l’aperçu vérifié. Inspectez de nouveau la source ; aucune préparation n’est autorisée.");
        }
        catch { TryRemoveOwned(destination); throw; }
    }

    public static void ExtractZip(string archive, string destination)
    {
        RequireNoLinks(archive);
        RequireNoLinks(destination);
        if (new FileInfo(archive).Length > MaxBytes) Fail("package.size", "L’archive dépasse la taille maximale.");
        if (System.IO.Directory.Exists(destination) || File.Exists(destination)) Fail("package.destination", "Le dossier de destination existe déjà.");
        using var zip = ZipFile.OpenRead(archive);
        if (zip.Entries.Count > MaxFiles + 2000) Fail("package.size", "L’archive contient trop d’entrées.");
        var names = new HashSet<string>(Paths);
        long total = 0;
        foreach (var entry in zip.Entries)
        {
            var name = NormalizeRelative(entry.FullName.TrimEnd('/'));
            var unixType = (entry.ExternalAttributes >> 16) & 0xF000;
            if (unixType is not (0 or 0x8000 or 0x4000) || (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                Fail("package.link", "Les liens et entrées spéciales sont interdits dans les archives.");
            if (!names.Add(name)) Fail("package.path", "L’archive contient des chemins répétés ou ambigus.");
            total = checked(total + entry.Length);
            if (total > MaxBytes || entry.Length > MaxBytes) Fail("package.size", "Le contenu décompressé dépasse la taille maximale.");
        }
        System.IO.Directory.CreateDirectory(destination);
        try
        {
            long extractedBytes = 0;
            var buffer = new byte[81920];
            foreach (var entry in zip.Entries)
            {
                var target = Path.Combine(destination, NormalizeRelative(entry.FullName.TrimEnd('/')));
                if (entry.FullName.EndsWith('/')) { System.IO.Directory.CreateDirectory(target); continue; }
                System.IO.Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                using var input = entry.Open();
                using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                int count;
                while ((count = input.Read(buffer)) != 0)
                {
                    extractedBytes = checked(extractedBytes + count);
                    if (extractedBytes > MaxBytes || output.Length + count > entry.Length)
                        Fail("package.size", "Le contenu décompressé dépasse les tailles annoncées.");
                    output.Write(buffer, 0, count);
                }
                if (output.Length != entry.Length) Fail("package.size", "La taille extraite ne correspond pas à l’archive.");
            }
        }
        catch { TryRemoveOwned(destination); throw; }
    }

    public static void Rehash(string directory)
    {
        var files = Inventory(directory);
        // Defaults written in place and the writer's temporaries never enter the identity; only a manifest that declares a
        // configuration (legacy custom pack built by the qualification benches) seals the defaults file in the inventory.
        var sealedDefaults = InstallationDefaults.DeclaresSealedDefaults(directory);
        var lines = files.Keys.Where(p => p != SumsPath && !p.StartsWith(SocleRuntime.RelativeDirectory + "/", StringComparison.OrdinalIgnoreCase)
                && !InstallationDefaults.IsDebris(p) && (sealedDefaults || !p.Equals(InstallationDefaults.RelativePath, StringComparison.OrdinalIgnoreCase)))
            .Order(StringComparer.Ordinal)
            .Select(p => Hash(Path.Combine(directory, p)) + "  " + p);
        WriteAtomic(Path.Combine(directory, SumsPath), string.Join('\n', lines) + "\n");
    }

    public static string Hash(string file)
    {
        RequireNoLinks(file);
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexStringLower(SHA256.HashData(stream));
    }

    public static string NormalizeRelative(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length > 1024 || path.StartsWith('/') || path.Contains('\\')
            || path.Any(c => c < 32 || "<>:\"|?*".Contains(c))) Fail("package.path", "Chemin de pack interdit.");
        foreach (var segment in path.Split('/'))
            if (segment is "" or "." or ".." || segment.EndsWith(' ') || segment.EndsWith('.')
                || Regex.IsMatch(segment.Split('.')[0], "^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", RegexOptions.IgnoreCase))
                Fail("package.path", "Chemin de pack ambigu ou réservé sous Windows.");
        return path;
    }

    public static void RequireNoLinks(string path)
    {
        var absolute = Path.GetFullPath(path);
        for (var current = absolute; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || System.IO.Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                Fail("package.link", "Un lien symbolique ou une jonction est interdit dans ce chemin.");
    }

    public static JsonDocument ReadJson(string path)
    {
        RequireNoLinks(path);
        using var stream = File.OpenRead(path);
        var doc = JsonDocument.Parse(stream, new() { MaxDepth = 32 });
        try { RejectDuplicateProperties(doc.RootElement); return doc; }
        catch { doc.Dispose(); throw; }
    }

    private static void RejectDuplicateProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in value.EnumerateObject())
            {
                if (!names.Add(p.Name)) Fail("package.json", "Le JSON contient des propriétés répétées ou ambiguës.");
                RejectDuplicateProperties(p.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var child in value.EnumerateArray()) RejectDuplicateProperties(child);
    }

    public static void WriteAtomic(string path, string contents)
    {
        RequireNoLinks(path);
        System.IO.Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var ownsTemporary = false;
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                ownsTemporary = true;
                var bytes = Encoding.UTF8.GetBytes(contents);
                stream.Write(bytes); stream.Flush(true);
            }
            // Windows can refuse MoveFileEx replacement even when a reader shares deletion.
            // Retain the same flushed file and retry only publication, for at most 20 waits.
            // Never delete the destination first: readers must see a complete old or new record.
            for (var attempt = 0; ; attempt++)
            {
                RequireNoLinks(path);
                RequireNoLinks(temporary);
                try { File.Move(temporary, path, true); break; }
                catch (Exception error) when (attempt < 20 && OperatingSystem.IsWindows()
                    && error is IOException or UnauthorizedAccessException
                    && error.HResult is unchecked((int)0x80070005) or unchecked((int)0x80070020) or unchecked((int)0x80070021))
                { Thread.Sleep(50); }
            }
        }
        catch
        {
            // A cleanup refusal must not replace the failure that prevented publication.
            // A failed CreateNew never grants ownership of an existing file.
            if (ownsTemporary)
            {
                try { File.Delete(temporary); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            throw;
        }
    }

    internal static void WriteJson<T>(string path, T value) => WriteAtomic(path, JsonSerializer.Serialize(value, JsonOptions));
    internal static void TryRemoveOwned(string path) { try { if (System.IO.Directory.Exists(path)) System.IO.Directory.Delete(path, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    internal static string Text(JsonElement item, string name) => Arguments.Text(item, name, true, 4096);
    internal static void Fail(string code, string message) => throw new PestoException(code, message);

    private static bool Allowed(string path, string channel)
    {
        if (path is "Pesto.exe" or ManifestPath or SumsPath or "wad/defaults/configuration.json" or "wad/support/DEBLOQUER_TOUT.cmd") return true;
        var name = Path.GetFileName(path).ToLowerInvariant();
        if (name is "cfg.json" or "cfg.demo.json") return false;
        if (new[] { ".pdb", ".log", ".sqlite", ".etl", ".evtx" }.Contains(Path.GetExtension(path).ToLowerInvariant())) return false;
        if (path.StartsWith(ActiveDirectoryBundle.RelativeDirectory + "/", StringComparison.Ordinal))
            return ActiveDirectoryBundle.Sha256.ContainsKey(path[(ActiveDirectoryBundle.RelativeDirectory.Length + 1)..]);
        if (path.StartsWith("wad/web/", StringComparison.Ordinal))
            return new[] { ".html", ".js", ".css", ".json", ".svg", ".png", ".jpg", ".jpeg", ".ico", ".woff", ".woff2" }.Contains(Path.GetExtension(path).ToLowerInvariant());
        if (path.StartsWith("wad/docs/", StringComparison.Ordinal)) return new[] { ".md", ".txt", ".pdf" }.Contains(Path.GetExtension(path).ToLowerInvariant());
        if (path.StartsWith("wad/dev/vendor/nuget/", StringComparison.Ordinal) && channel == "DEV")
            return Path.GetExtension(path).Equals(".nupkg", StringComparison.OrdinalIgnoreCase) || Path.GetFileName(path) == "SHA256SUMS";
        if (channel == "DEV" && DevExactSourcePaths.Contains(path)) return true;
        if (path.StartsWith("wad/dev/", StringComparison.Ordinal) && channel == "DEV")
            return new[] { ".cs", ".csproj", ".props", ".targets", ".sln", ".slnx", ".json", ".mjs", ".js", ".css", ".html", ".md", ".txt", ".ps1", ".cmd", ".manifest", ".config" }.Contains(Path.GetExtension(path).ToLowerInvariant());
        return false;
    }

    private static void RequirePe64(string path)
    {
        using var stream = File.OpenRead(path);
        using var reader = new BinaryReader(stream);
        if (stream.Length < 128 || reader.ReadUInt16() != 0x5A4D) Fail("package.pe", "Un exécutable du pack n’est pas un PE Windows valide.");
        stream.Position = 0x3c; var offset = reader.ReadInt32();
        if (offset < 0x40 || offset > stream.Length - 26) Fail("package.pe", "En-tête PE invalide.");
        stream.Position = offset;
        if (reader.ReadUInt32() != 0x00004550 || reader.ReadUInt16() != 0x8664) Fail("package.pe", "Un exécutable du pack n’est pas destiné à Windows x64.");
        stream.Position = offset + 24;
        if (reader.ReadUInt16() != 0x20b) Fail("package.pe", "Le format PE32+ x64 est requis.");
    }
}
