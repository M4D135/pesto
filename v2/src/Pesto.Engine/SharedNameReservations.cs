using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Internal preview evidence. Only its expiration is displayed; neither a path nor ownership is accepted from the browser.</summary>
public sealed record SharedNameReservationProof(string Root, string Domain, string Name, string Owner, string PreviewId,
    string ConfigSha256, string LeaseSha256, DateTimeOffset ExpiresAt, string IntentId);

public interface IMutationNameReservations
{
    IReadOnlyList<string> OtherReservedNames(string domain);
    SharedNameReservationProof? ReservePreviewName(string domain, string name, string previewId, string configurationSha256);
    void VerifyPreviewName(SharedNameReservationProof proof, string configurationSha256);
    void ReleasePreviewName(SharedNameReservationProof proof);
}

public enum SharedNameReservationCreation { Created, AlreadyExists }

/// <summary>The production editor distinguishes a proven existing file from every ambiguous create/write error.
/// Rewrite reads, decides and flushes through one exclusive non-link handle; it never reopens a pathname to write.</summary>
public interface ISharedNameReservationFiles
{
    SharedNameReservationCreation CreateNew(string path, byte[] bytes);
    void RewriteExisting(string path, byte[] replacement, Func<byte[], bool> mayReplace);
}

/// <summary>Immutable local record, flushed before any shared create/renewal. A renewal binds our previous exact bytes.</summary>
public sealed record SharedNameReservationIntent(int Schema, SharedNameReservationProof Proof, DateTimeOffset CreatedUtc,
    string Content, string? PreviousLeaseSha256);

public sealed record SharedNameReservationConfiguration(SharedCoordinationConfiguration Coordination, int Minutes)
{
    public static SharedNameReservationConfiguration ReadBytes(byte[] bytes)
    {
        var configuration = SharedCoordinationConfiguration.ReadBytes(bytes);
        using var document = JsonDocument.Parse(new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF'));
        var minutes = 15;
        if (document.RootElement.TryGetProperty("POLICY", out var policy) && policy.ValueKind == JsonValueKind.Object
            && policy.TryGetProperty("NameReservationMinutes", out var value) && value.ValueKind != JsonValueKind.Null)
            minutes = value.GetInt32(); // V1Config already checked the closed integer range.
        if (minutes is < 5 or > 240) throw Invalid("Durée du bail hors limites (5 à 240 minutes).");
        return new(configuration, minutes);
    }
    private static PestoException Invalid(string message) => new("names.reservation_invalid", message);
}

/// <summary>V1 reservations/NAME.json protocol, separate from mutation locks which never expire.
/// Unknown/malformed evidence is conservatively occupied; it is never reclaimed using a guessed modification time.</summary>
public static class SharedNameReservationProtocol
{
    private sealed record Entry(string Name, string Domain, string Owner, DateTimeOffset CreatedUtc, DateTimeOffset ExpiresUtc);
    public const int MaximumEntries = 5000;
    public const int MaximumLeaseBytes = 8192;

    public static SharedNameReservationIntent CreateIntent(SharedNameReservationConfiguration configuration, string name,
        string previewId, string owner, string station, string user, DateTimeOffset now, SharedNameReservationProof? previous = null)
    {
        name = name.ToUpperInvariant();
        if (configuration.Coordination.Root.Length == 0 || configuration.Minutes is < 5 or > 240) throw Invalid("Aucun registre de noms configuré.");
        if (!Name(name) || !Opaque(previewId) || !Owner(owner) || !Metadata(station) || !Metadata(user)) throw Invalid("Identité du bail de nom invalide.");
        var expires = now.ToUniversalTime().AddMinutes(configuration.Minutes);
        var content = new JsonObject
        {
            ["Schema"] = 1, ["Name"] = name, ["Domain"] = configuration.Coordination.Domain,
            ["Station"] = station, ["User"] = user, ["Owner"] = owner, ["Context"] = previewId,
            ["CreatedUtc"] = now.UtcDateTime.ToString("O", CultureInfo.InvariantCulture),
            ["ExpiresUtc"] = expires.UtcDateTime.ToString("O", CultureInfo.InvariantCulture)
        }.ToJsonString();
        if (previous is not null && (previous.Owner != owner || !Same(previous.Root, configuration.Coordination.Root)
            || !Same(previous.Domain, configuration.Coordination.Domain) || !Same(previous.Name, name)))
            throw Invalid("Le bail précédent appartient à un autre nom, propriétaire ou registre.");
        var proof = new SharedNameReservationProof(configuration.Coordination.Root, configuration.Coordination.Domain,
            name, owner, previewId, configuration.Coordination.ConfigSha256, SharedCoordinationProtocol.Hash(Encoding.UTF8.GetBytes(content)),
            expires, "name-intent-" + Guid.NewGuid().ToString("N"));
        var intent = new SharedNameReservationIntent(1, proof, now.ToUniversalTime(), content, previous?.LeaseSha256);
        ValidateIntent(intent);
        return intent;
    }

    public static IReadOnlyList<string> OtherReservedNames(SharedNameReservationConfiguration configuration, string owner,
        SharedCoordinationAccessMode mode, TimeProvider? clock = null)
    {
        SharedCoordinationProtocol.Guard(mode);
        if (!Owner(owner)) throw Invalid("Propriétaire de session invalide.");
        var directory = RequirePrepared(configuration.Coordination.Root, configuration.Coordination.Domain);
        var time = clock ?? TimeProvider.System;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var count = 0;
        foreach (var path in Directory.EnumerateFiles(directory, "*.json", SearchOption.TopDirectoryOnly))
        {
            if (++count > MaximumEntries) throw new PestoException("names.reservation_unavailable", "Le registre dépasse 5 000 baux : aucun nom n’est déduit d’une lecture tronquée.");
            var name = Path.GetFileNameWithoutExtension(path).ToUpperInvariant();
            if (!Name(name)) throw Invalid("Un fichier de réservation porte un nom inattendu ; inspectez le registre.");
            Entry? entry;
            try { entry = ReadEntry(SharedCoordinationProtocol.ReadBounded(path, MaximumLeaseBytes), name, configuration.Coordination.Domain); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException)
            { names.Add(name); continue; } // A lost/locked/changed read excludes this candidate, never means free.
            if (entry is null || entry.CreatedUtc > time.GetUtcNow() || entry.ExpiresUtc > time.GetUtcNow() && entry.Owner != owner) names.Add(name);
        }
        return names.Order(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    /// <summary>The caller must have pinned the immutable durable local intent before invoking this method.</summary>
    public static void Acquire(SharedNameReservationIntent intent, SharedCoordinationAccessMode mode,
        ISharedNameReservationFiles files, TimeProvider? clock = null)
    {
        SharedCoordinationProtocol.Guard(mode); ValidateIntent(intent);
        var time = clock ?? TimeProvider.System;
        RequireFresh(intent.Proof, time.GetUtcNow());
        var directory = RequirePrepared(intent.Proof.Root, intent.Proof.Domain);
        var path = Path.Combine(directory, intent.Proof.Name + ".json");
        SharedCoordinationProtocol.RequireNoLinks(path);
        var replacement = Encoding.UTF8.GetBytes(intent.Content);
        // Only a known CREATE_NEW collision can enter the renewal path. A lost SMB response propagates as failure.
        if (files.CreateNew(path, replacement) == SharedNameReservationCreation.AlreadyExists)
            files.RewriteExisting(path, replacement, current =>
            {
                RequireFresh(intent.Proof, time.GetUtcNow());
                var previous = ReadEntry(current, intent.Proof.Name, intent.Proof.Domain);
                if (previous is null || previous.CreatedUtc > time.GetUtcNow()) return false;
                if (previous.Owner == intent.Proof.Owner)
                    return intent.PreviousLeaseSha256 is not null && SharedCoordinationProtocol.Hash(current) == intent.PreviousLeaseSha256;
                return previous.ExpiresUtc <= time.GetUtcNow();
            });
        Verify(intent.Proof, mode, time);
    }

    public static void Verify(SharedNameReservationProof proof, SharedCoordinationAccessMode mode, TimeProvider? clock = null)
    {
        SharedCoordinationProtocol.Guard(mode); ValidateProof(proof);
        var directory = RequirePrepared(proof.Root, proof.Domain);
        var bytes = SharedCoordinationProtocol.ReadBounded(Path.Combine(directory, proof.Name + ".json"), MaximumLeaseBytes);
        var entry = ReadEntry(bytes, proof.Name, proof.Domain);
        if (SharedCoordinationProtocol.Hash(bytes) != proof.LeaseSha256 || entry is null || entry.Owner != proof.Owner || entry.ExpiresUtc != proof.ExpiresAt)
            throw new PestoException("names.reservation_changed", "Le bail du nom affiché a changé. Calculez un nouvel aperçu puis confirmez de nouveau ; aucun autre nom n’est substitué.");
        RequireFresh(proof, (clock ?? TimeProvider.System).GetUtcNow());
    }

    public static void Release(SharedNameReservationProof proof, SharedCoordinationAccessMode mode, ISharedCoordinationDeletion deletion)
    {
        SharedCoordinationProtocol.Guard(mode); ValidateProof(proof);
        var directory = RequirePrepared(proof.Root, proof.Domain);
        if (deletion.DeleteExact(Path.Combine(directory, proof.Name + ".json"), proof.LeaseSha256, MaximumLeaseBytes) == CoordinationDeletionResult.Changed)
            throw new PestoException("names.reservation_changed", "Le bail ne contient plus les octets de ce propriétaire ; il est conservé.");
    }

    public static void ValidateIntent(SharedNameReservationIntent intent)
    {
        if (intent is null || intent.Schema != 1 || intent.Content is null) throw Invalid("Intention de bail absente.");
        ValidateProof(intent.Proof);
        if (Encoding.UTF8.GetByteCount(intent.Content) > MaximumLeaseBytes
            || SharedCoordinationProtocol.Hash(Encoding.UTF8.GetBytes(intent.Content)) != intent.Proof.LeaseSha256
            || intent.PreviousLeaseSha256 is not null && !Hash(intent.PreviousLeaseSha256)) throw Invalid("Intention de bail modifiée.");
        var entry = ReadEntry(Encoding.UTF8.GetBytes(intent.Content), intent.Proof.Name, intent.Proof.Domain);
        if (entry is null || entry.Owner != intent.Proof.Owner || entry.CreatedUtc != intent.CreatedUtc || entry.ExpiresUtc != intent.Proof.ExpiresAt
            || entry.ExpiresUtc - entry.CreatedUtc < TimeSpan.FromMinutes(5)) throw Invalid("Durée ou identité de bail incohérente.");
    }

    public static void ValidateProof(SharedNameReservationProof proof)
    {
        if (proof is null || proof.Root is not { Length: > 0 and <= 240 } || proof.Root.Any(char.IsControl)
            || !SharedCoordinationProtocol.IsDomainName(proof.Domain) || !Name(proof.Name) || proof.Name != proof.Name.ToUpperInvariant()
            || !Owner(proof.Owner) || !Opaque(proof.PreviewId) || !Hash(proof.ConfigSha256) || !Hash(proof.LeaseSha256)
            || proof.IntentId is null || !Regex.IsMatch(proof.IntentId, "^name-intent-[a-f0-9]{32}$", RegexOptions.CultureInvariant)
            || proof.ExpiresAt == default) throw Invalid("Preuve du bail invalide.");
    }

    private static string RequirePrepared(string root, string domain)
    {
        var state = SharedCoordinationProtocol.InspectRegistry(root, domain);
        if (!state.Ready) throw new PestoException("coordination.unprepared", "Le registre de noms doit être préparé explicitement, avec locks et reservations. Aucun dossier créé par l’aperçu.");
        return Path.Combine(state.Root, "reservations");
    }

    private static Entry? ReadEntry(byte[] bytes, string name, string domain)
    {
        if (bytes.Length is < 1 or > MaximumLeaseBytes) return null;
        try
        {
            using var document = JsonDocument.Parse(new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF'), new JsonDocumentOptions { MaxDepth = 4 });
            var value = document.RootElement;
            string[] keys = ["Schema", "Name", "Domain", "Station", "User", "Owner", "Context", "CreatedUtc", "ExpiresUtc"];
            if (value.ValueKind != JsonValueKind.Object) return null;
            var fields = value.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Length != keys.Length || fields.Distinct(StringComparer.OrdinalIgnoreCase).Count() != keys.Length
                || fields.Any(p => !keys.Contains(p, StringComparer.Ordinal)) || !value.GetProperty("Schema").TryGetInt32(out var schema) || schema != 1) return null;
            string? Text(string key) => value.GetProperty(key).ValueKind == JsonValueKind.String ? value.GetProperty(key).GetString() : null;
            if (!Same(Text("Name"), name) || !Same(Text("Domain"), domain) || !Owner(Text("Owner"))
                || !Metadata(Text("Station")) || !Metadata(Text("User")) || !Metadata(Text("Context"))
                || !DateTimeOffset.TryParse(Text("CreatedUtc"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var created)
                || !DateTimeOffset.TryParse(Text("ExpiresUtc"), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var expires)
                || expires <= created || expires - created > TimeSpan.FromMinutes(240)) return null;
            return new(name, domain, Text("Owner")!, created, expires);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or DecoderFallbackException) { return null; }
    }

    private static void RequireFresh(SharedNameReservationProof proof, DateTimeOffset now)
    {
        if (proof.ExpiresAt <= now) throw new PestoException("names.reservation_expired", "Le bail du nom affiché a expiré. Un nouvel aperçu et une nouvelle confirmation sont nécessaires.");
    }
    private static bool Name(string? value) => value is { Length: >= 1 and <= 15 } && Regex.IsMatch(value, "^[A-Z0-9-]+$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    private static bool Owner(string? value) => Guid.TryParseExact(value, "N", out var id) && id != Guid.Empty;
    private static bool Opaque(string? value) => value is { Length: > 0 and <= 128 } && Regex.IsMatch(value, "^[A-Za-z0-9._-]+$", RegexOptions.CultureInvariant);
    private static bool Hash(string? value) => value is not null && Regex.IsMatch(value, "^[a-f0-9]{64}$", RegexOptions.CultureInvariant);
    private static bool Metadata(string? value) => value is { Length: <= 256 } && !value.Any(char.IsControl);
    private static bool Same(string? first, string? second) => string.Equals(first, second, StringComparison.OrdinalIgnoreCase);
    private static PestoException Invalid(string message) => new("names.reservation_invalid", message);
}
