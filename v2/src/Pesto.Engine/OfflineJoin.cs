using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pesto.Engine;

/// <summary>Observed local facts only. Null is unknown, never a stand-in for a machine outside a domain.</summary>
public sealed record OfflineJoinLocalState(string? Computer, string? ActiveName, string? ConfiguredName,
    string? MachineId, string? Domain, bool? PartOfDomain, int? DomainRole, DateTimeOffset? BootUtc,
    bool? Administrator, string? Error)
{
    public static OfflineJoinLocalState Unknown(string reason) => new(null, null, null, null, null, null, null, null, null, reason);
}

/// <summary>The AD GUID/OU are operator declarations until a later post-boot observation proves them.</summary>
public sealed record OfflineJoinBinding(string Id, string Computer, string Domain, string ExpectedAdGuid,
    string TargetOu, string MachineId, string ConfigurationSha256, string ProtectedSha256,
    DateTimeOffset ImportedUtc, DateTimeOffset ExpiresUtc, DateTimeOffset InitialBootUtc,
    string InitialWindowsDomain, int InitialDomainRole, bool AuditEventLogEnabled);

public sealed record OfflineJoinObservation(OfflineJoinLocalState Local, string? AdGuid, string? AdName,
    string? AdOu, string? AdDomain, bool? DomainController, bool? SecureChannel,
    DateTimeOffset ObservedUtc, string? Error);

/// <summary>Append-only evidence. Requested consumes the blob even if an interruption loses all later replies.</summary>
public sealed record OfflineJoinEvent(int Schema, int Sequence, string PreviousSha256, OfflineJoinBinding Binding,
    string State, DateTimeOffset Utc, string? ReceiptId, string? PlanId, int? NativeCode, bool WorkerMayRun,
    OfflineJoinObservation? Observation, string? SourceReceiptSha256, OfflineJoinLocalState? Baseline);
public sealed record OfflineJoinSnapshot(OfflineJoinEvent Event, string Sha256);

/// <summary>Native-only command. No file path, secret or executable can be supplied through a browser.</summary>
public sealed record OfflineJoinCommand(OfflineJoinBinding Binding, string ReceiptId, string PlanId,
    string IntentSha256, DateTimeOffset RequestedUtc, OfflineJoinLocalState Baseline, DateTimeOffset PlanExpiresUtc);
public sealed record OfflineJoinNativeResult(bool Started, int? NativeCode, bool WorkerMayRun, string Message);

/// <summary>Windows integration injected into the portable ODJ service. Constructors must not probe any environment.</summary>
public interface IOfflineJoinPlatform : IDisposable
{
    string? UnavailableReason { get; }
    OfflineJoinLocalState ReadLocal();
    MutationManagedPolicy ReadManagedPolicy();
    byte[] ProtectBlob(byte[] plaintext);
    byte[] UnprotectBlob(byte[] protectedBytes);
    void SecureDirectory(string directory);
    void DeleteExact(string path, string expectedSha256);
    OfflineJoinNativeResult Apply(OfflineJoinCommand command);
    OfflineJoinObservation Observe(OfflineJoinBinding binding);
    void Audit(bool enabled, string durableReceiptJson);
}

public static class OfflineJoinReceipt
{
    public static readonly string[] Fields = ["OfflineJoin", "OfflineJoinId", "OfflineJoinSha256", "ExpectedAdGuid"];

    public static string Message(string state) => state switch
    {
        "Importing" => "Import local incomplet ; aucune application ni réimportation automatique.",
        "Imported" => "Blob protégé localement. GUID AD et OU déclarés, à prouver après application et redémarrage.",
        "Requested" => "Intention ODJ durable : l’envoi a pu commencer. Aucun rejeu, même après interruption.",
        "PendingRestart" => "Windows a accepté la demande ODJ. Un redémarrage puis une observation explicite restent nécessaires ; jonction non encore vérifiée.",
        "Uncertain" => "Résultat ODJ incertain. Observez après un nouveau démarrage ; aucune nouvelle application ni réparation implicite.",
        "Verified" => "Nouveau démarrage, identité Windows, GUID AD déclaré, nom, OU et canal sécurisé vérifiés ensemble.",
        _ => "État ODJ non exploitable ; aucune application."
    };

    public static JsonObject Create(OfflineJoinSnapshot snapshot)
    {
        var e = snapshot.Event; var b = e.Binding;
        if (e.State is not ("Requested" or "PendingRestart" or "Uncertain" or "Verified") || e.Baseline is null
            || !OfflineJoinRules.IsHash(snapshot.Sha256)) throw OfflineJoinRules.Refused("offlineJoin.receipt", "Aucun reçu métier avant une intention ODJ complète.");
        return new JsonObject
        {
            ["Schema"] = 1, ["Version"] = "2.0", ["Adapter"] = "ODJ local Windows", ["Kind"] = "offlineJoin",
            ["ReceiptId"] = e.ReceiptId, ["PlanId"] = e.PlanId, ["Phase"] = e.State == "Requested" ? "Running" : e.State,
            ["Utc"] = e.Utc.ToString("O"), ["CreatedUtc"] = b.ImportedUtc.ToString("O"), ["Computer"] = b.Computer,
            ["NewName"] = b.Computer, ["TargetOu"] = b.TargetOu, ["Domain"] = b.Domain, ["Dc"] = null,
            ["Code"] = e.State == "Verified" ? 30 : e.State == "PendingRestart" ? 10 : 97,
            ["Message"] = Message(e.State), ["RestartRequired"] = e.State == "PendingRestart",
            ["ComputerGuid"] = e.State == "Verified" ? b.ExpectedAdGuid : null,
            ["MachineId"] = b.MachineId, ["LocalTarget"] = true, ["InitialBootUtc"] = e.Baseline.BootUtc!.Value.ToString("O"),
            ["InitialWindowsDomain"] = e.Baseline.Domain, ["InitialPartOfDomain"] = false,
            ["InitialDomainRole"] = e.Baseline.DomainRole, ["ConfigurationSha256"] = b.ConfigurationSha256,
            ["AuditEventLogEnabled"] = b.AuditEventLogEnabled, ["OfflineJoin"] = e.State,
            ["OfflineJoinId"] = b.Id, ["OfflineJoinSha256"] = snapshot.Sha256, ["ExpectedAdGuid"] = b.ExpectedAdGuid
        };
    }

    /// <summary>The mirror is a projection of this exact immutable event, never authority on its own.</summary>
    public static bool Matches(OfflineJoinSnapshot snapshot, JsonElement receipt)
    {
        try { return ValidateEvidence(receipt) && JsonNode.DeepEquals(Create(snapshot), JsonNode.Parse(receipt.GetRawText())); }
        catch (Exception) { return false; }
    }

    public static bool ValidateStored(string gpRoot, ReadOnlyMemory<byte> receiptBytes)
    {
        try
        {
            if (receiptBytes.Length is < 1 or > 65536) return false;
            using var document = JsonDocument.Parse(receiptBytes); var root = document.RootElement;
            if (!root.TryGetProperty("Kind", out var kind) || kind.ValueKind != JsonValueKind.String || kind.GetString() != "offlineJoin") return true;
            OfflineJoinStore.RequireUnique(root);
            if (!ValidateEvidence(root)) return false;
            var id = root.GetProperty("OfflineJoinId").GetString()!; var eventHash = root.GetProperty("OfflineJoinSha256").GetString()!;
            var store = new OfflineJoinStore(gpRoot, ConfigurationAccessMode.Live);
            var head = store.Read(id); var linked = store.ReadEvent(id, eventHash);
            return head is not null && linked is not null && Matches(linked, root)
                && head.Event.ReceiptId == linked.Event.ReceiptId
                && (eventHash == head.Sha256 || OfflineJoinRules.Hash(receiptBytes.Span) == head.Event.SourceReceiptSha256);
        }
        catch (Exception) { return false; }
    }

    public static JsonObject Public(OfflineJoinSnapshot snapshot)
    {
        var e = snapshot.Event; var b = e.Binding;
        return new JsonObject
        {
            ["id"] = e.ReceiptId, ["kind"] = "offlineJoin", ["computer"] = b.Computer, ["newName"] = b.Computer,
            ["targetOU"] = b.TargetOu, ["status"] = e.State == "Verified" ? "succeeded" : e.State == "PendingRestart" ? "pendingRestart" : "uncertain",
            ["code"] = e.State == "Verified" ? 30 : e.State == "PendingRestart" ? 10 : 97,
            ["restartRequired"] = e.State == "PendingRestart", ["mode"] = "live", ["message"] = Message(e.State), ["utc"] = e.Utc.ToString("O")
        };
    }

    /// <summary>Closed history admission for the ODJ extension; generic name/OU reconciliation is insufficient.</summary>
    public static bool ValidateEvidence(JsonElement receipt)
    {
        try
        {
            static string? Text(JsonElement r, string key) => r.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            if (Text(receipt, "Kind") != "offlineJoin") return Fields.All(field => !receipt.TryGetProperty(field, out var v) || v.ValueKind == JsonValueKind.Null);
            var effect = Text(receipt, "OfflineJoin"); var phase = Text(receipt, "Phase");
            if (effect is not ("Requested" or "PendingRestart" or "Uncertain" or "Verified")
                || phase != (effect == "Requested" ? "Running" : effect)
                || !OfflineJoinRules.IsHash(Text(receipt, "OfflineJoinId")) || !OfflineJoinRules.IsHash(Text(receipt, "OfflineJoinSha256"))
                || !OfflineJoinRules.IsGuid(Text(receipt, "ExpectedAdGuid"))
                || !OfflineJoinRules.IsGuid(Text(receipt, "MachineId")) || !OfflineJoinRules.IsHash(Text(receipt, "ConfigurationSha256"))
                || Text(receipt, "Computer") != Text(receipt, "NewName")
                || !receipt.TryGetProperty("LocalTarget", out var local) || local.ValueKind != JsonValueKind.True
                || !receipt.TryGetProperty("Code", out var code) || !code.TryGetInt32(out var number)
                || number != (effect == "Verified" ? 30 : effect == "PendingRestart" ? 10 : 97)
                || !receipt.TryGetProperty("RestartRequired", out var restart) || restart.ValueKind is not (JsonValueKind.True or JsonValueKind.False)
                || restart.GetBoolean() != (effect == "PendingRestart")) return false;
            return effect == "Verified" ? OfflineJoinRules.Same(Text(receipt, "ComputerGuid"), Text(receipt, "ExpectedAdGuid"))
                : !receipt.TryGetProperty("ComputerGuid", out var guid) || guid.ValueKind == JsonValueKind.Null;
        }
        catch (Exception) { return false; }
    }
}
