using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Observed state of an installation's distributed defaults. <c>local</c> lies outside the pack identity (written in place
/// since 2.0.14); <c>sealed</c> belongs to the inventory of a legacy custom pack; <c>invalid</c> is never used.
/// </summary>
public sealed record InstallationDefaultState(string State, string? Version, string? Fingerprint, string? Sha256)
{
    public bool Present => State is "local" or "sealed";
    public JsonObject ToJson() => new()
    {
        ["state"] = State, ["path"] = InstallationDefaults.DisplayPath,
        ["version"] = Version, ["fingerprint"] = Fingerprint, ["sha256"] = Sha256
    };
}

/// <summary>
/// The configuration file an administrator places in an installation, like GLPI-Pilot's deployment file. It is validated by
/// its own schema and fingerprint, never by the pack inventory: writing it leaves an official pack official.
/// </summary>
public static class InstallationDefaults
{
    public const string RelativePath = "wad/defaults/configuration.json";
    public const string DisplayPath = "wad\\defaults\\configuration.json";
    /// <summary>First version whose validator, writer and update helper know the local form.</summary>
    public static readonly Version MinimumVersion = new(2, 0, 14);
    internal const string InvalidMessage = "La configuration par défaut de cette installation (wad\\defaults\\configuration.json) est invalide ou illisible : Pesto refuse de l’utiliser. Supprimez ce fichier ou remplacez-le par une configuration exportée valide ; aucun profil n’a été modifié.";
    internal const string BusyMessage = "La configuration par défaut de cette installation (wad\\defaults\\configuration.json) est momentanément illisible, probablement ouverte par un autre programme. Fermez ce programme puis recommencez ; aucun profil n’a été modifié.";
    internal const string ConflictMessage = "Le pack choisi apporte une configuration par défaut différente de celle de cette installation. Aucun fichier n’a été remplacé. Retirez wad\\defaults\\configuration.json du pack source ou de cette installation, puis préparez de nouveau la mise à jour.";
    // Only the unfinished temporary of ConfigurationStore.Write. It is never read; the published file is old or new, complete.
    private static readonly Regex Debris = new("^wad/defaults/\\.configuration-[0-9a-f]{32}\\.tmp$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string PathIn(string root) => Path.Combine(root, "wad", "defaults", "configuration.json");
    public static bool IsDebris(string relative) => Debris.IsMatch(relative);

    /// <summary>Light inspection for the interface: manifest and defaults file only, never a hash of the whole pack.</summary>
    public static InstallationDefaultState Inspect(string root)
    {
        var file = PathIn(root);
        if (!File.Exists(file)) return new("missing", null, null, null);
        bool sealedForm;
        try { sealedForm = DeclaresSealedDefaults(root); }
        catch (Exception error) when (error is PestoException or IOException or UnauthorizedAccessException or JsonException) { return new("invalid", null, null, null); }
        try
        {
            var (bundle, sha) = ReadValid(file);
            return new(sealedForm ? "sealed" : "local", ConfigurationDocument.String(bundle, "version"), ConfigurationDocument.String(bundle, "fingerprint"), sha);
        }
        catch (PestoException) { return new("invalid", null, null, null); }
    }

    /// <summary>Strict reader shared by the pack validator: 1 MiB, exact encoding, no links, valid distributed bundle.</summary>
    internal static (JsonObject Bundle, string Sha256) ReadValid(string file)
    {
        try
        {
            var snapshot = ConfigurationStore.ReadSnapshot(file);
            return (ConfigurationDocument.ValidateBundle(snapshot.Text), snapshot.Stamp);
        }
        catch (Exception error) when (error is PestoException or UnauthorizedAccessException)
        {
            throw new PestoException("package.defaults", InvalidMessage);
        }
        // A sharing violation (antivirus, another Pesto window replacing it) is transient: never advise deleting the file.
        catch (IOException) { throw new PestoException("package.defaults", BusyMessage); }
    }

    internal static bool DeclaresSealedDefaults(string root)
    {
        var manifest = Path.Combine(root, "wad", "Pesto.package.json");
        if (!File.Exists(manifest)) return false;
        using var document = UpdatePackage.ReadJson(manifest);
        return document.RootElement.ValueKind == JsonValueKind.Object
            && (document.RootElement.TryGetProperty("configurationFingerprint", out _) || document.RootElement.TryGetProperty("configurationVersion", out _));
    }

    /// <summary>SHA-256 of the installation's defaults file (local or sealed), or null when there is none.</summary>
    internal static string? CurrentSha256(string root)
    {
        var state = Inspect(root);
        if (state.State == "invalid") throw new PestoException("package.defaults", InvalidMessage);
        return state.Present ? state.Sha256 : null;
    }

    /// <summary>Removes only the writer's own unfinished temporaries; a refusal leaves them tolerated and unread.</summary>
    internal static void RemoveDebris(string root, TimeSpan? olderThan = null)
    {
        var directory = Path.Combine(root, "wad", "defaults");
        if (!Directory.Exists(directory)) return;
        UpdatePackage.RequireNoLinks(directory);
        foreach (var file in Directory.EnumerateFiles(directory, ".configuration-*.tmp", SearchOption.TopDirectoryOnly))
        {
            if (!IsDebris("wad/defaults/" + Path.GetFileName(file))) continue;
            try
            {
                if (olderThan is { } age && DateTime.UtcNow - File.GetLastWriteTimeUtc(file) < age) continue;
                UpdatePackage.RequireNoLinks(file);
                File.Delete(file);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    /// <summary>Refuses early a source whose defaults differ from the installation's (GLPI 3.10.1 rule).</summary>
    internal static void RequireCompatible(string installation, string source)
    {
        var current = Inspect(installation);
        var incoming = Inspect(source);
        if (current.State == "invalid" || incoming.State == "invalid") throw new PestoException("package.defaults", InvalidMessage);
        if (current.Present && incoming.Present && current.Fingerprint != incoming.Fingerprint)
            throw new PestoException("update.default_conflict", ConflictMessage);
    }

    /// <summary>
    /// Carries the installation's defaults into a verified stage before replacement and returns their SHA-256 for the
    /// transaction marker. The stage keeps an identical sealed file; a local copy keeps the installation's exact bytes.
    /// </summary>
    internal static string? CarryIntoStage(string installation, string stage)
    {
        RemoveDebris(stage);
        var current = Inspect(installation);
        if (current.State == "invalid") throw new PestoException("package.defaults", InvalidMessage);
        if (!current.Present) return null;
        var incoming = Inspect(stage);
        if (incoming.State == "invalid") throw new PestoException("package.defaults", InvalidMessage);
        var source = PathIn(installation);
        var target = PathIn(stage);
        UpdatePackage.RequireNoLinks(source);
        UpdatePackage.RequireNoLinks(target);
        if (!incoming.Present)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(source, target, false);
        }
        else if (incoming.Fingerprint != current.Fingerprint) throw new PestoException("update.default_conflict", ConflictMessage);
        else if (incoming.State == "local" && incoming.Sha256 != current.Sha256) File.Copy(source, target, true);
        var carried = Inspect(stage);
        if (carried.Fingerprint != current.Fingerprint || carried.State == "local" && carried.Sha256 != current.Sha256)
            throw new PestoException("update.default", "La configuration par défaut de l’installation n’a pas pu être recopiée à l’identique vers la nouvelle version. Aucun fichier n’a été remplacé.");
        return current.Sha256;
    }

    /// <summary>
    /// Seals, for Execute and Rollback, the installation's defaults (<paramref name="sha256"/>) and those the prepared stage
    /// carries (<paramref name="stageSha256"/>, which may come from the source when the installation had none).
    /// </summary>
    internal static void WriteMarker(string transactionDirectory, string? sha256, string? stageSha256)
        => UpdatePackage.WriteAtomic(MarkerPath(transactionDirectory),
            new JsonObject { ["schemaVersion"] = 1, ["sha256"] = sha256, ["stageSha256"] = stageSha256 }.ToJsonString());

    /// <summary>Returns false when the transaction was prepared without a marker (helper before 2.0.14).</summary>
    internal static bool TryReadMarker(string transactionDirectory, out string? sha256, out string? stageSha256)
    {
        sha256 = null;
        stageSha256 = null;
        var path = MarkerPath(transactionDirectory);
        if (!File.Exists(path)) return false;
        if (new FileInfo(path).Length > 4096) throw InvalidMarker();
        using var document = UpdatePackage.ReadJson(path);
        var root = document.RootElement;
        Arguments.Only(root, "schemaVersion", "sha256", "stageSha256");
        if (!root.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1
            || !root.TryGetProperty("sha256", out var value) || !root.TryGetProperty("stageSha256", out var staged)) throw InvalidMarker();
        sha256 = MarkerDigest(value);
        stageSha256 = MarkerDigest(staged);
        return true;
    }

    private static string? MarkerDigest(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.String || !Regex.IsMatch(value.GetString()!, "^[0-9a-f]{64}$")) throw InvalidMarker();
        return value.GetString();
    }

    /// <summary>
    /// Before the backup is restored, the latest local defaults win, including their deliberate deletion. Sealed files belong
    /// to a pack identity and are never touched. Defaults still exactly as the transaction placed them
    /// (<paramref name="stageSha256"/>, from a source pack for instance) are not carried back: the old version keeps its own.
    /// <paramref name="latestRoot"/> is the candidate, still installed or already set aside. The copy is published by an
    /// atomic move from the transaction directory; read-only attributes never block it.
    /// </summary>
    internal static void PreserveLatestForRollback(string latestRoot, string backup, string transactionDirectory, string? stageSha256)
    {
        if (!Directory.Exists(latestRoot) || !Directory.Exists(backup)) return;
        var restored = Inspect(backup);
        var latest = Inspect(latestRoot);
        if (restored.State is "sealed" or "invalid" || latest.State is "sealed" or "invalid") return;
        var target = PathIn(backup);
        UpdatePackage.RequireNoLinks(target);
        if (latest.State == "local")
        {
            if (restored.State == "local" && restored.Sha256 == latest.Sha256) return;
            if (stageSha256 is not null && latest.Sha256 == stageSha256) return;
            var temporary = Path.Combine(transactionDirectory, "defaults-rollback." + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                File.Copy(PathIn(latestRoot), temporary, false);
                ClearReadOnly(temporary);
                if (UpdatePackage.Hash(temporary) != latest.Sha256)
                    throw new PestoException("update.default", "La configuration par défaut actuelle n’a pas pu être copiée à l’identique avant le retour arrière.");
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                if (File.Exists(target)) ClearReadOnly(target);
                File.Move(temporary, target, true);
            }
            finally { if (File.Exists(temporary)) { ClearReadOnly(temporary); File.Delete(temporary); } }
        }
        else if (restored.State == "local")
        {
            ClearReadOnly(target);
            File.Delete(target);
        }
    }

    /// <summary>
    /// What a return to this transaction's backup will do with the installation's defaults, so the confirmation says it
    /// exactly: <c>kept</c>, <c>withdrawn</c> (brought by the update and unchanged since: the old state comes back),
    /// <c>deleted</c> (deletion since the update kept), <c>setAside</c> (helper before 2.0.14), or null (nothing to say).
    /// </summary>
    internal static string? DescribeReturn(string installation, string transactionDirectory, string restoredVersion)
    {
        try
        {
            var backup = Path.Combine(transactionDirectory, "backup");
            var latestRoot = Directory.Exists(installation) ? installation : Path.Combine(transactionDirectory, "failed-candidate");
            if (!Directory.Exists(backup) || !Directory.Exists(latestRoot)) return null;
            var latest = Inspect(latestRoot);
            if (!Version.TryParse(restoredVersion, out var restoredProgram) || restoredProgram < MinimumVersion)
                return latest.State == "local" ? "setAside" : null;
            var restored = Inspect(backup);
            if (restored.State is "sealed" or "invalid" || latest.State is "sealed" or "invalid") return null;
            if (latest.State != "local") return restored.State == "local" ? "deleted" : null;
            if (restored.State == "local" && restored.Sha256 == latest.Sha256) return "kept";
            return TryReadMarker(transactionDirectory, out _, out var staged) && staged is not null && staged == latest.Sha256 ? "withdrawn" : "kept";
        }
        catch (Exception error) when (error is PestoException or IOException or UnauthorizedAccessException or JsonException) { return null; }
    }

    /// <summary>What installing this pack does with the installation's defaults: <c>kept</c>, <c>adopted</c> or null.</summary>
    internal static string? DescribeInstall(string installation, UpdatePackageInfo incoming)
    {
        var current = Inspect(installation);
        if (current.Present) return "kept";
        return incoming.LocalConfigurationFingerprint is not null || incoming.ConfigurationFingerprint is not null ? "adopted" : null;
    }

    private static void ClearReadOnly(string file)
    {
        var attributes = File.GetAttributes(file);
        if ((attributes & FileAttributes.ReadOnly) != 0) File.SetAttributes(file, attributes & ~FileAttributes.ReadOnly);
    }

    /// <summary>
    /// A helper before 2.0.14 refuses any undeclared defaults file. Its local copies and debris are moved into the transaction
    /// directory, never deleted, before such a helper restores or recovers the installation.
    /// </summary>
    internal static void SetAsideForLegacyHelper(string installation, string transactionDirectory)
    {
        foreach (var (name, root) in new[] { ("installation", installation), ("failed-candidate", Path.Combine(transactionDirectory, "failed-candidate")) })
        {
            var directory = Path.Combine(root, "wad", "defaults");
            if (!Directory.Exists(directory)) continue;
            UpdatePackage.RequireNoLinks(directory);
            var sealedForm = DeclaresSealedDefaults(root);
            var target = Path.Combine(transactionDirectory, "defaults-set-aside", name);
            foreach (var file in Directory.EnumerateFiles(directory, "*", SearchOption.TopDirectoryOnly))
            {
                var fileName = Path.GetFileName(file);
                var relative = "wad/defaults/" + fileName;
                if (!IsDebris(relative) && (sealedForm || !relative.Equals(RelativePath, StringComparison.OrdinalIgnoreCase))) continue;
                UpdatePackage.RequireNoLinks(file);
                Directory.CreateDirectory(target);
                var destination = Path.Combine(target, fileName);
                if (File.Exists(destination)) destination = Path.Combine(target, Guid.NewGuid().ToString("N") + "-" + fileName);
                File.Move(file, destination);
            }
        }
    }

    private static string MarkerPath(string transactionDirectory) => Path.Combine(transactionDirectory, "installation-default.json");
    private static PestoException InvalidMarker() => new("update.journal", "Le relevé de la configuration par défaut de la transaction est invalide. Aucun dossier n’est modifié.");
}
