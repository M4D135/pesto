using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public enum SharedCoordinationAccessMode { Live, Demo, HealthCheck, BinaryRecovery }

/// <summary>Execution context supplied by the native adapter; no credential is part of the protocol or receipt.</summary>
public interface ISharedCoordinationAccess
{
    T Run<T>(Func<T> operation);
}

public sealed class CurrentIdentityCoordinationAccess : ISharedCoordinationAccess
{
    public T Run<T>(Func<T> operation) => operation();
}

/// <summary>Deletion must compare the exact bytes and delete the same opened file, not look the pathname up again.
/// Production Windows uses a DELETE-capable exclusive handle and FileDispositionInfo, including on SMB.</summary>
public interface ISharedCoordinationDeletion
{
    CoordinationDeletionResult DeleteExact(string path, string expectedSha256, int maximumBytes);
}

public enum CoordinationDeletionResult { Missing, Deleted, Changed }

public sealed record SharedCoordinationCleanupStatus(string State, string? ReceiptId = null, string? FailureCode = null, int Failures = 0);
public interface ISharedCoordinationDisclosure
{
    SharedCoordinationCleanupStatus CoordinationCleanupStatus { get; }
}

public sealed record SharedCoordinationConfiguration(string Domain, string Root, bool Required, string ConfigSha256)
{
    public static SharedCoordinationConfiguration ReadBytes(byte[] bytes)
    {
        if (bytes.Length is < 1 or > ConfigurationDocument.MaximumBytes)
            throw new PestoException("coordination.config", "Configuration absente ou trop volumineuse ; aucune coordination ouverte.");
        var text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
        return Read(text) with { ConfigSha256 = SharedCoordinationProtocol.Hash(bytes) };
    }

    public static SharedCoordinationConfiguration Read(string configurationJson)
    {
        if (Encoding.UTF8.GetByteCount(configurationJson) > ConfigurationDocument.MaximumBytes)
            throw new PestoException("coordination.config", "Configuration trop volumineuse ; aucune coordination ouverte.");
        var config = V1Config.ValidateText(configurationJson);
        return new(config.Domain, config.OperationPolicy.CoordinationRoot, config.OperationPolicy.CoordinationRequired,
            SharedCoordinationProtocol.Hash(Encoding.UTF8.GetBytes(configurationJson)));
    }
}

public sealed record SharedCoordinationIdentity(string Domain, string Computer, string? NewName, string? ComputerGuid);
public sealed record SharedCoordinationEntry(string Key, string Owner, string Sha256, string? Content, bool Inherited);

/// <summary>Durable local intent, recorded before the first remote CreateNew. Parent-owned locks are never transferred.</summary>
public sealed record SharedCoordinationIntent(int Schema, bool Enabled, string Root, string Domain, string ReceiptId,
    string Owner, string ConfigSha256, string CreatedUtc, string? ResumeFrom, SharedCoordinationIdentity Identity,
    IReadOnlyList<SharedCoordinationEntry> Entries, IReadOnlyList<string> BorrowedOwners,
    IReadOnlyList<JoinReservationParent> ReservationParents)
{
    public JsonObject ToJson() => JsonSerializer.SerializeToNode(this)!.AsObject();
}

public sealed record SharedCoordinationRegistryState(string Root, bool RootExists, bool MarkerPresent, bool LocksPresent, bool ReservationsPresent,
    string? MarkerSha256, string Fingerprint)
{
    public bool Ready => RootExists && MarkerPresent && LocksPresent && ReservationsPresent;
}

/// <summary>V1 file protocol. No directory, share, ACL, expiry or reservation is invented by mutation acquisition.</summary>
public static class SharedCoordinationProtocol
{
    public const int MaximumMarkerBytes = 4096;
    public const int MaximumLeaseBytes = 8192;
    private static readonly Regex ShaPattern = new("^[a-f0-9]{64}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private static readonly Regex OpaquePattern = new("^[A-Za-z0-9._-]{1,128}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);

    public static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    public static bool IsDomainName(string? value) => value is { Length: >= 3 and <= 253 }
        && Regex.IsMatch(value, @"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$",
            RegexOptions.CultureInvariant | RegexOptions.IgnoreCase | RegexOptions.NonBacktracking);

    public static IReadOnlyList<string> Keys(SharedCoordinationIdentity identity)
    {
        ValidateIdentity(identity);
        var values = new List<string>();
        if (!string.IsNullOrEmpty(identity.ComputerGuid))
            values.Add("machine|" + identity.Domain.ToUpperInvariant() + "|" + Guid.Parse(identity.ComputerGuid).ToString("N"));
        foreach (var name in new[] { identity.Computer, identity.NewName })
            if (!string.IsNullOrEmpty(name)) values.Add("name|" + identity.Domain.ToUpperInvariant() + "|" + name.ToUpperInvariant());
        // V1 Get-PestoStableHash hashes ConvertTo-Json -Compress of the STRING, including its quotes.
        return values.Select(value => Hash(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value))))
            .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
    }

    public static string OwnerForReceipt(string receiptId)
    {
        if (!OpaquePattern.IsMatch(receiptId)) throw Invalid("Identifiant de reçu de coordination invalide.");
        var suffix = receiptId.StartsWith("receipt-", StringComparison.Ordinal) ? receiptId[8..] : receiptId;
        if (Guid.TryParse(suffix, out var guid) && guid != Guid.Empty) return guid.ToString("N");
        // Legacy/test opaque V2 IDs still map deterministically to the GUID-shaped V1 owner field.
        return new Guid(SHA256.HashData(Encoding.UTF8.GetBytes("pesto-v2-receipt|" + receiptId)).AsSpan(0, 16)).ToString("N");
    }

    public static SharedCoordinationIntent? CreateIntent(SharedCoordinationConfiguration configuration,
        SharedCoordinationIdentity identity, string receiptId, DateTimeOffset now, SharedCoordinationIntent? parent = null,
        IReadOnlyList<JoinReservationParent>? reservationParents = null)
    {
        ValidateIdentity(identity);
        if (!configuration.Domain.Equals(identity.Domain, StringComparison.OrdinalIgnoreCase)) throw Invalid("Le domaine de coordination diffère du plan.");
        if (configuration.Root.Length == 0)
        {
            if (configuration.Required || parent is not null) throw Invalid("La coordination requise ou celle du reçu parent ne peut pas être désactivée pendant cette opération.");
            return null;
        }
        ValidateRootSyntax(configuration.Root);
        if (!ShaPattern.IsMatch(configuration.ConfigSha256)) throw Invalid("Empreinte de configuration absente.");
        if (parent is not null)
        {
            ValidateIntent(parent);
            if (!parent.Domain.Equals(configuration.Domain, StringComparison.OrdinalIgnoreCase)
                || !SameRoot(parent.Root, configuration.Root)) throw Invalid("Le registre de coordination du reçu parent a changé.");
        }
        var owner = OwnerForReceipt(receiptId);
        var created = now.UtcDateTime.ToString("O", CultureInfo.InvariantCulture);
        var entries = new List<SharedCoordinationEntry>();
        foreach (var key in Keys(identity))
        {
            var inherited = parent?.Entries.FirstOrDefault(e => e.Key == key);
            if (inherited is not null)
            {
                entries.Add(new(key, inherited.Owner, inherited.Sha256, null, true));
                continue;
            }
            var content = new JsonObject { ["Schema"] = 1, ["OperationId"] = owner, ["Key"] = key, ["Domain"] = identity.Domain,
                ["CreatedUtc"] = created, ["State"] = "Prepared" }.ToJsonString();
            entries.Add(new(key, owner, Hash(Encoding.UTF8.GetBytes(content)), content, false));
        }
        var result = new SharedCoordinationIntent(1, true, configuration.Root, identity.Domain, receiptId, owner,
            configuration.ConfigSha256, created, parent?.Owner, identity, entries,
            entries.Where(e => e.Inherited).Select(e => e.Owner).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray(),
            reservationParents?.ToArray() ?? []);
        ValidateIntent(result);
        return result;
    }

    public static SharedCoordinationIntent ReadIntent(JsonElement node)
    {
        try
        {
            Closed(node, "Schema", "Enabled", "Root", "Domain", "ReceiptId", "Owner", "ConfigSha256", "CreatedUtc", "ResumeFrom", "Identity", "Entries", "BorrowedOwners", "ReservationParents");
            Closed(node.GetProperty("Identity"), "Domain", "Computer", "NewName", "ComputerGuid");
            var entries = node.GetProperty("Entries");
            if (entries.ValueKind != JsonValueKind.Array || entries.GetArrayLength() is < 1 or > 3) throw Invalid("Liste de verrous inattendue.");
            foreach (var entry in entries.EnumerateArray()) Closed(entry, "Key", "Owner", "Sha256", "Content", "Inherited");
            if (node.GetProperty("ReservationParents").ValueKind != JsonValueKind.Array) throw Invalid("Liste de reçus parents invalide.");
            foreach (var entry in node.GetProperty("ReservationParents").EnumerateArray()) Closed(entry, "ReceiptId", "Sha256");
            var value = node.Deserialize<SharedCoordinationIntent>() ?? throw Invalid("Intention de coordination absente.");
            ValidateIntent(value);
            return value;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or ArgumentException)
        { throw Invalid("Intention de coordination invalide ; aucun fichier partagé modifié."); }
    }

    public static void ValidateIntent(SharedCoordinationIntent intent)
    {
        if (intent.Schema != 1 || !intent.Enabled || intent.Identity is null || intent.Entries is null
            || intent.BorrowedOwners is null || intent.ReservationParents is null
            || intent.Entries.Count is < 1 or > 3 || string.IsNullOrEmpty(intent.ReceiptId) || !OpaquePattern.IsMatch(intent.ReceiptId)
            || intent.Owner != OwnerForReceipt(intent.ReceiptId) || !ShaPattern.IsMatch(intent.ConfigSha256 ?? "")
            || !DateTimeOffset.TryParse(intent.CreatedUtc, CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
            throw Invalid("Intention de coordination incomplète.");
        ValidateRootSyntax(intent.Root);
        ValidateIdentity(intent.Identity);
        if (!string.Equals(intent.Domain, intent.Identity.Domain, StringComparison.OrdinalIgnoreCase)) throw Invalid("Domaine de verrou incohérent.");
        var expected = Keys(intent.Identity);
        if (intent.Entries.Any(e => e is null) || !intent.Entries.Select(e => e.Key).SequenceEqual(expected, StringComparer.Ordinal)) throw Invalid("Clés de coordination différentes des identités du plan.");
        var owners = intent.Entries.Where(e => e.Inherited).Select(e => e.Owner).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
        if (!intent.BorrowedOwners.SequenceEqual(owners, StringComparer.Ordinal)
            || intent.ResumeFrom is not null && (!Guid.TryParseExact(intent.ResumeFrom, "N", out var parentOwner) || parentOwner == Guid.Empty)
            || owners.Length > 0 && intent.ResumeFrom is null
            || intent.ReservationParents.Count > 32 || intent.ReservationParents.Any(p => p is null
                || !OpaquePattern.IsMatch(p.ReceiptId ?? "") || p.ReceiptId == intent.ReceiptId || !ShaPattern.IsMatch(p.Sha256 ?? ""))
            || intent.ReservationParents.Select(p => p.ReceiptId).Distinct(StringComparer.Ordinal).Count() != intent.ReservationParents.Count)
            throw Invalid("Preuves des propriétaires parents invalides.");
        foreach (var entry in intent.Entries)
        {
            if (!ShaPattern.IsMatch(entry.Sha256 ?? "") || !Guid.TryParseExact(entry.Owner, "N", out var owner) || owner == Guid.Empty)
                throw Invalid("Propriétaire ou empreinte de verrou invalide.");
            if (entry.Inherited)
            {
                if (entry.Content is not null || !intent.BorrowedOwners.Contains(entry.Owner, StringComparer.Ordinal))
                    throw Invalid("Un verrou parent ne peut être transféré ou réécrit.");
            }
            else
            {
                if (entry.Owner != intent.Owner || entry.Content is null || Encoding.UTF8.GetByteCount(entry.Content) > MaximumLeaseBytes
                    || Hash(Encoding.UTF8.GetBytes(entry.Content)) != entry.Sha256) throw Invalid("Contenu du verrou différent de son intention.");
                ValidateLease(Encoding.UTF8.GetBytes(entry.Content), entry, intent.Domain);
            }
        }
    }

    public static SharedCoordinationRegistryState InspectRegistry(string root, string domain)
    {
        var normalized = FullRoot(root);
        if (!IsDomainName(domain)) throw Invalid("Domaine de registre invalide.");
        RequireNoLinks(normalized);
        if (File.Exists(normalized)) throw Invalid("Le registre configuré est un fichier, pas un dossier.");
        var exists = Directory.Exists(normalized);
        var marker = Path.Combine(normalized, "pesto-coordination.json");
        var locks = Path.Combine(normalized, "locks");
        var reservations = Path.Combine(normalized, "reservations");
        RequireNoLinks(marker); RequireNoLinks(locks); RequireNoLinks(reservations);
        if (Directory.Exists(marker) || File.Exists(locks) || File.Exists(reservations)) throw Invalid("Structure du registre de coordination invalide.");
        byte[]? markerBytes = null;
        if (File.Exists(marker))
        {
            markerBytes = ReadBounded(marker, MaximumMarkerBytes);
            using var document = Parse(markerBytes);
            var value = document.RootElement;
            Closed(value, "Schema", "Domain", "Purpose");
            if (!One(value.GetProperty("Schema")) || Text(value, "Purpose") != "PestoCoordination"
                || !Text(value, "Domain").Equals(domain, StringComparison.OrdinalIgnoreCase))
                throw Invalid("Ce registre préparé ne correspond pas au domaine du plan.");
        }
        var locksPresent = Directory.Exists(locks);
        var reservationsPresent = Directory.Exists(reservations);
        var markerHash = markerBytes is null ? null : Hash(markerBytes);
        var fingerprint = Hash(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { RootExists = exists, MarkerSha256 = markerHash, LocksPresent = locksPresent, ReservationsPresent = reservationsPresent })));
        return new(normalized, exists, markerBytes is not null, locksPresent, reservationsPresent, markerHash, fingerprint);
    }

    public static void RequirePrepared(SharedCoordinationIntent intent)
    {
        ValidateIntent(intent);
        var state = InspectRegistry(intent.Root, intent.Domain);
        // V1 mutation locking predates the temporary-name directory. Existing valid V1 locks remain usable.
        if (!state.RootExists || !state.MarkerPresent || !state.LocksPresent)
            throw new PestoException("coordination.unprepared", "Le registre de coordination n’est pas préparé. Aucune création implicite de dossier, partage ou droits.");
    }

    public static void Acquire(SharedCoordinationIntent intent, SharedCoordinationAccessMode mode, ISharedCoordinationDeletion deletion)
    {
        Guard(mode); RequirePrepared(intent);
        var created = new List<SharedCoordinationEntry>();
        try
        {
            foreach (var entry in intent.Entries)
            {
                var path = LeasePath(intent, entry.Key);
                RequireNoLinks(path);
                if (entry.Inherited)
                {
                    ValidateLease(ReadExistingLease(path), entry, intent.Domain);
                    continue;
                }
                try
                {
                    using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
                    var bytes = Encoding.UTF8.GetBytes(entry.Content!);
                    stream.Write(bytes); stream.Flush(true);
                    created.Add(entry);
                }
                catch (IOException) when (File.Exists(path) && !created.Contains(entry))
                { throw new PestoException("coordination.held", "Une intervention, réservation ou écriture inachevée détient cette cible. Aucun verrou partagé n’expire automatiquement."); }
            }
            Verify(intent, mode);
        }
        catch
        {
            // The receipt already carries the exact intended bytes. Only this attempt's newly created locks qualify.
            foreach (var entry in created)
                try { _ = deletion.DeleteExact(LeasePath(intent, entry.Key), entry.Sha256, MaximumLeaseBytes); }
                catch (Exception) { } // Preserve any changed/unreachable evidence; never clean another owner's file.
            throw;
        }
    }

    public static void Verify(SharedCoordinationIntent intent, SharedCoordinationAccessMode mode)
    {
        Guard(mode); RequirePrepared(intent);
        foreach (var entry in intent.Entries) ValidateLease(ReadExistingLease(LeasePath(intent, entry.Key)), entry, intent.Domain);
    }

    /// <summary>Called only for a proven pre-send abort or a durable terminal receipt. Uncertainty never calls it.</summary>
    public static void ReleaseOwned(SharedCoordinationIntent intent, SharedCoordinationAccessMode mode, ISharedCoordinationDeletion deletion)
    {
        Guard(mode); RequirePrepared(intent);
        foreach (var entry in intent.Entries.Where(e => !e.Inherited && e.Owner == intent.Owner))
            if (deletion.DeleteExact(LeasePath(intent, entry.Key), entry.Sha256, MaximumLeaseBytes) == CoordinationDeletionResult.Changed)
                throw new PestoException("coordination.changed", "Un verrou partagé a changé. Il est conservé ; aucune suppression par son seul nom.");
    }

    public static bool IsCompletedReceipt(JsonElement receipt)
    {
        if (receipt.ValueKind != JsonValueKind.Object) return false;
        var phase = OptionalText(receipt, "Phase");
        if (phase is "Failed" or "Verified") return true;
        if (StoredMutationBarrier.IsAcknowledged(receipt)) return true;
        // V2 stores Code rather than ResultCode and lacks V1's per-effect evidence: retain its PendingRestart locks.
        if (phase != "PendingRestart" || !receipt.TryGetProperty("ResultCode", out var result)
            || result.ValueKind != JsonValueKind.Number || !result.TryGetInt32(out var code) || receipt.TryGetProperty("OfflineJoin", out var offline) && offline.ValueKind != JsonValueKind.Null)
            return false;
        if (code is not (10 or 20 or 77) && !(code == 89 && OptionalText(receipt, "Rename") == "Confirmed" && OptionalText(receipt, "Move") == "Confirmed")) return false;
        if (OptionalText(receipt, "Protection") is not ("NotChanged" or "Restored")
            || OptionalText(receipt, "Entra") is not ("NotRequested" or "Skipped" or "Confirmed")) return false;
        foreach (var key in new[] { "Rename", "Move" })
            if (OptionalText(receipt, key) is not ("NotRequested" or "Confirmed")) return false;
        return !receipt.TryGetProperty("JoinEvidence", out var join) || join.ValueKind == JsonValueKind.Null
            || join.ValueKind == JsonValueKind.Object && OptionalText(join, "NativeStatus") == "Accepted";
    }

    public static string FullRoot(string root)
    {
        ValidateRootSyntax(root);
        if (!Path.IsPathFullyQualified(root)) throw Invalid("Le chemin de coordination n’est pas utilisable sur ce système.");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
    }

    public static void Guard(SharedCoordinationAccessMode mode)
    {
        if (mode != SharedCoordinationAccessMode.Live)
            throw new PestoException("coordination.isolated", "La démonstration, le contrôle de santé et la reprise binaire n’accèdent jamais au registre partagé.");
    }

    public static void RequireNoLinks(string path)
    {
        for (string? part = Path.GetFullPath(path); part is not null; part = Path.GetDirectoryName(part))
            if ((Directory.Exists(part) || File.Exists(part)) && (File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0)
                throw Invalid("Le registre de coordination ne peut pas traverser un lien ou une jonction.");
    }

    public static byte[] ReadBounded(string path, int maximum)
    {
        RequireNoLinks(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is < 1 || stream.Length > maximum) throw Invalid("Document de coordination absent ou hors limites.");
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1) throw Invalid("Le document de coordination a changé pendant sa lecture.");
        return bytes;
    }

    private static string LeasePath(SharedCoordinationIntent intent, string key) => Path.Combine(FullRoot(intent.Root), "locks", key + ".json");
    private static byte[] ReadExistingLease(string path)
    {
        try { return ReadBounded(path, MaximumLeaseBytes); }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException)
        { throw new PestoException("coordination.changed", "Le verrou partagé attendu n’existe plus. Aucune recréation implicite ni mutation."); }
    }
    private static bool SameRoot(string first, string second) => first.TrimEnd('\\', '/').Equals(second.TrimEnd('\\', '/'), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal);

    private static void ValidateRootSyntax(string root)
    {
        if (string.IsNullOrWhiteSpace(root) || root.Length > 240 || root.Any(c => char.IsControl(c) || c is '"' or '*' or '?' or '|')
            || root.StartsWith(@"\\?\", StringComparison.Ordinal) || root.StartsWith(@"\\.\", StringComparison.Ordinal)
            || !(Path.IsPathFullyQualified(root) || Regex.IsMatch(root, @"^[A-Za-z]:[\\/]") || root.StartsWith(@"\\", StringComparison.Ordinal)))
            throw Invalid("Chemin absolu du registre invalide.");
        if (OperatingSystem.IsWindows() && root.Contains(':') && (root.IndexOf(':') != 1 || root.LastIndexOf(':') != 1))
            throw Invalid("Flux alternatif ou chemin de registre ambigu interdit.");
    }

    private static void ValidateIdentity(SharedCoordinationIdentity identity)
    {
        if (identity is null || !IsDomainName(identity.Domain) || !Name(identity.Computer)
            || identity.NewName is { Length: > 0 } && !Name(identity.NewName)
            || !string.IsNullOrEmpty(identity.ComputerGuid) && (!Guid.TryParse(identity.ComputerGuid, out var guid) || guid == Guid.Empty))
            throw Invalid("Identité du plan de coordination invalide.");
    }
    private static bool Name(string? value) => value is { Length: >= 1 and <= 15 }
        && Regex.IsMatch(value, "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", RegexOptions.CultureInvariant);

    private static void ValidateLease(byte[] bytes, SharedCoordinationEntry expected, string domain)
    {
        if (bytes.Length is < 1 or > MaximumLeaseBytes || Hash(bytes) != expected.Sha256)
            throw new PestoException("coordination.changed", "Les octets du verrou partagé diffèrent de l’intention durable ; aucune mutation ni suppression.");
        using var document = Parse(bytes);
        var value = document.RootElement;
        Closed(value, "Schema", "OperationId", "Key", "Domain", "CreatedUtc", "State");
        if (!One(value.GetProperty("Schema")) || Text(value, "OperationId") != expected.Owner || Text(value, "Key") != expected.Key
            || !Text(value, "Domain").Equals(domain, StringComparison.OrdinalIgnoreCase) || Text(value, "State") != "Prepared"
            || !DateTimeOffset.TryParse(Text(value, "CreatedUtc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
            throw Invalid("Le propriétaire ou les identités du verrou partagé ont changé.");
    }
    private static JsonDocument Parse(byte[] bytes)
    {
        try { return JsonDocument.Parse(new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF'), new JsonDocumentOptions { MaxDepth = 8 }); }
        catch (Exception error) when (error is JsonException or DecoderFallbackException) { throw Invalid("Document de coordination illisible."); }
    }
    private static void Closed(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object) throw Invalid("Objet de coordination attendu.");
        var fields = value.EnumerateObject().Select(p => p.Name).ToArray();
        if (fields.Length != keys.Length || fields.Distinct(StringComparer.OrdinalIgnoreCase).Count() != keys.Length
            || fields.Any(key => !keys.Contains(key, StringComparer.Ordinal))) throw Invalid("Schéma de coordination fermé invalide.");
    }
    private static bool One(JsonElement value) => value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var n) && n == 1;
    private static string Text(JsonElement value, string key) => OptionalText(value, key) ?? throw Invalid("Texte de coordination absent : " + key);
    private static string? OptionalText(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
    private static PestoException Invalid(string reason) => new("coordination.invalid", reason);
}
