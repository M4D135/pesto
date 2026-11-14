using System.Text;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Session-scoped preview authority with immutable, flushed local intent and confirmation files.
/// Configuration is pinned throughout the shared IO; no constructor, status page or isolated mode opens a share.</summary>
public sealed class SharedNameReservationService(string configurationPath, string journalDirectory,
    SharedCoordinationAccessMode mode, ISharedNameReservationFiles files, ISharedCoordinationDeletion deletion,
    ISharedCoordinationAccess? access = null, TimeProvider? clock = null, Action<string>? protectJournal = null,
    string? sessionOwner = null, string? station = null, string? user = null) : IMutationNameReservations
{
    private readonly object gate = new();
    private readonly ISharedCoordinationAccess context = access ?? new CurrentIdentityCoordinationAccess();
    private readonly TimeProvider time = clock ?? TimeProvider.System;
    private readonly string owner = sessionOwner ?? Guid.NewGuid().ToString("N");
    private readonly string stationName = station ?? Environment.MachineName;
    private readonly string userName = user ?? Environment.UserName;
    private readonly Dictionary<string, SharedNameReservationIntent> issued = new(StringComparer.Ordinal);
    private readonly Dictionary<string, SharedNameReservationProof> latest = new(StringComparer.OrdinalIgnoreCase);
    private const int MaximumJournalBytes = 32768;

    public IReadOnlyList<string> OtherReservedNames(string domain)
    {
        SharedCoordinationProtocol.Guard(mode);
        lock (gate) return WithConfiguration<IReadOnlyList<string>>(null, configuration =>
        {
            RequireDomain(configuration, domain);
            if (configuration.Coordination.Root.Length == 0) return Array.Empty<string>();
            var observed = context.Run(() => SharedNameReservationProtocol.OtherReservedNames(configuration, owner, mode, time));
            RequireUnchanged(configuration);
            return observed;
        });
    }

    public SharedNameReservationProof? ReservePreviewName(string domain, string name, string previewId, string configurationSha256)
    {
        MutationSessionGuard.RequireWritableSession();
        SharedCoordinationProtocol.Guard(mode);
        lock (gate) return WithConfiguration<SharedNameReservationProof?>(configurationSha256, configuration =>
        {
            RequireDomain(configuration, domain);
            if (configuration.Coordination.Root.Length == 0) return null;
            if (issued.Count >= 5000) throw new PestoException("names.reservation_busy", "Trop de baux dans cette session ; fermez les préparations et relancez Pesto.");
            var key = Key(configuration.Coordination.Root, domain, name);
            var previous = latest.GetValueOrDefault(key);
            var intent = SharedNameReservationProtocol.CreateIntent(configuration, name, previewId, owner, stationName, userName, time.GetUtcNow(), previous);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(intent);
            EnsureJournal();
            var pendingPath = JournalPath(intent.Proof, confirmed: false);
            WriteNew(pendingPath, bytes);
            // Keep the immutable local proof open against replacement before the first shared CreateNew and renewal.
            WithExactFile(pendingPath, bytes, () =>
            {
                RequireUnchanged(configuration);
                context.Run(() => { MutationSessionGuard.RequireWritableSession(); SharedNameReservationProtocol.Acquire(intent, mode, files, time); return true; });
                RequireUnchanged(configuration);
                WriteNew(JournalPath(intent.Proof, confirmed: true), ConfirmationBytes(intent));
                if (intent.Proof.ExpiresAt <= time.GetUtcNow())
                    throw new PestoException("names.reservation_expired", "Le bail a expiré avant la confirmation locale ; aucun aperçu validé.");
                return true;
            });
            issued[intent.Proof.IntentId] = intent;
            latest[key] = intent.Proof;
            return intent.Proof;
        });
    }

    public void VerifyPreviewName(SharedNameReservationProof proof, string configurationSha256)
    {
        SharedCoordinationProtocol.Guard(mode);
        lock (gate) WithConfiguration(configurationSha256, configuration =>
        {
            var intent = RequireIssued(proof);
            if (proof.ConfigSha256 != configuration.Coordination.ConfigSha256
                || !string.Equals(proof.Root, configuration.Coordination.Root, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(proof.Domain, configuration.Coordination.Domain, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("names.reservation_changed", "La configuration n’est plus celle du nom affiché ; préparez un nouvel aperçu.");
            WithProofFiles(intent, () => context.Run(() => { SharedNameReservationProtocol.Verify(proof, mode, time); return true; }));
            RequireUnchanged(configuration);
            return true;
        });
    }

    public void ReleasePreviewName(SharedNameReservationProof proof)
    {
        MutationSessionGuard.RequireWritableSession();
        SharedCoordinationProtocol.Guard(mode);
        lock (gate)
        {
            var intent = RequireIssued(proof);
            // Cleanup remains bound to the original immutable root, owner and exact bytes even if settings changed.
            WithProofFiles(intent, () => context.Run(() => { MutationSessionGuard.RequireWritableSession(); SharedNameReservationProtocol.Release(proof, mode, deletion); return true; }));
            issued.Remove(proof.IntentId);
            var key = Key(proof.Root, proof.Domain, proof.Name);
            if (latest.GetValueOrDefault(key) == proof) latest.Remove(key);
        }
    }

    private SharedNameReservationIntent RequireIssued(SharedNameReservationProof proof)
    {
        SharedNameReservationProtocol.ValidateProof(proof);
        if (proof.Owner != owner || !issued.TryGetValue(proof.IntentId, out var intent) || intent.Proof != proof)
            throw new PestoException("names.reservation_changed", "Ce bail n’a pas été confirmé par cette session ; aucun accès partagé pour une preuve fabriquée.");
        return intent;
    }

    private T WithProofFiles<T>(SharedNameReservationIntent intent, Func<T> operation) =>
        WithExactFile(JournalPath(intent.Proof, false), JsonSerializer.SerializeToUtf8Bytes(intent), () =>
            WithExactFile(JournalPath(intent.Proof, true), ConfirmationBytes(intent), operation));

    private T WithConfiguration<T>(string? expected, Func<SharedNameReservationConfiguration, T> operation)
    {
        SharedCoordinationProtocol.RequireNoLinks(configurationPath);
        using var file = new FileStream(configurationPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        var bytes = Read(file, ConfigurationDocument.MaximumBytes);
        var configuration = SharedNameReservationConfiguration.ReadBytes(bytes);
        if (expected is not null && configuration.Coordination.ConfigSha256 != expected)
            throw new PestoException("names.reservation_changed", "La configuration a changé depuis l’aperçu ; aucun bail écrit ni confirmé.");
        return operation(configuration);
    }

    private void RequireUnchanged(SharedNameReservationConfiguration configuration)
    {
        var bytes = SharedCoordinationProtocol.ReadBounded(configurationPath, ConfigurationDocument.MaximumBytes);
        if (SharedCoordinationProtocol.Hash(bytes) != configuration.Coordination.ConfigSha256)
            throw new PestoException("names.reservation_changed", "La configuration a changé pendant la lecture du registre ; le candidat reste non confirmé.");
    }

    private void EnsureJournal()
    {
        SharedCoordinationProtocol.RequireNoLinks(journalDirectory);
        Directory.CreateDirectory(journalDirectory);
        SharedCoordinationProtocol.RequireNoLinks(journalDirectory);
        protectJournal?.Invoke(journalDirectory);
        if (Directory.EnumerateFiles(journalDirectory, "*.json").Take(10001).Count() > 10000)
            throw new PestoException("names.reservation_busy", "Le journal des baux dépasse sa limite ; aucune preuve supprimée automatiquement.");
    }

    private string JournalPath(SharedNameReservationProof proof, bool confirmed)
    {
        SharedNameReservationProtocol.ValidateProof(proof);
        return Path.Combine(journalDirectory, proof.IntentId + (confirmed ? ".confirmed.json" : ".intent.json"));
    }
    private static byte[] ConfirmationBytes(SharedNameReservationIntent intent) => JsonSerializer.SerializeToUtf8Bytes(new
    { Schema = 1, intent.Proof.IntentId, IntentSha256 = SharedCoordinationProtocol.Hash(JsonSerializer.SerializeToUtf8Bytes(intent)), Proof = intent.Proof });
    private static string Key(string root, string domain, string name) => root + "|" + domain + "|" + name;
    private static void RequireDomain(SharedNameReservationConfiguration configuration, string domain)
    {
        if (!string.Equals(configuration.Coordination.Domain, domain, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("names.reservation_invalid", "Le domaine du nom diffère de la configuration.");
    }
    private static void WriteNew(string path, byte[] bytes)
    {
        if (bytes.Length > MaximumJournalBytes) throw new PestoException("names.reservation_invalid", "Intention de bail trop volumineuse.");
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        file.Write(bytes); file.Flush(true);
    }
    private static T WithExactFile<T>(string path, byte[] expected, Func<T> operation)
    {
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (!Read(file, MaximumJournalBytes).AsSpan().SequenceEqual(expected))
            throw new PestoException("names.reservation_changed", "La preuve locale du bail a changé ; aucune écriture ni suppression partagée.");
        return operation();
    }
    private static byte[] Read(FileStream file, int maximum)
    {
        if (file.Length is < 1 || file.Length > maximum) throw new PestoException("names.reservation_invalid", "Document local du bail absent ou hors limites.");
        var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
        if (file.ReadByte() != -1) throw new PestoException("names.reservation_changed", "Document local modifié pendant sa lecture.");
        return bytes;
    }
}
