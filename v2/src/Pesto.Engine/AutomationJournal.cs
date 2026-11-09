using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed record AutomationJournalRequest(int Schema, string KeyHash, string PayloadSha256, string ReceiptId, string PlanIntegrity,
    string ProfileSid, string OperatorSid, string MachineId, string ConfigurationSha256, DateTimeOffset Utc, string State);
internal sealed record AutomationJournalResult(int Schema, string RequestSha256, string PayloadSha256, string? ReceiptSha256, DateTimeOffset Utc, PestoCliResult Result);

/// <summary>Immutable Started + immutable Completed. An interrupted intent is never replayed, even if no receipt is visible yet.</summary>
public sealed class AutomationJournal : IDisposable
{
    private readonly AutomationHostContext context;
    private readonly string keyHash;
    private readonly string requestPath;
    private readonly string resultPath;
    private readonly Mutex mutex;
    private bool owned;
    private const int MaximumBytes = 196608;

    public AutomationJournal(AutomationHostContext context, string idempotencyKey)
    {
        AutomationPolicy.RequireContext(context);
        if (context.GpRoot.StartsWith(@"\\", StringComparison.Ordinal)) throw Refused("Le registre d'idempotence doit rester local.");
        this.context = context;
        keyHash = KeyHash(idempotencyKey);
        mutex = new Mutex(false, @"Global\GP_Automation_" + keyHash);
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw Refused("Cette clé d'idempotence est déjà utilisée par un autre processus ; aucun envoi concurrent.");
            var legacy = Path.Combine(context.GpRoot, "Automation", keyHash + ".json");
            SharedCoordinationProtocol.RequireNoLinks(legacy);
            if (File.Exists(legacy)) throw Refused("Cette clé existe déjà dans le registre V1 ; aucune intention V2 ne remplace ni ne rejoue un état historique.");
            var folder = Path.Combine(context.GpRoot, "V2", "automation");
            SharedCoordinationProtocol.RequireNoLinks(folder);
            requestPath = Path.Combine(folder, keyHash + ".request.json");
            resultPath = Path.Combine(folder, keyHash + ".result.json");
            SharedCoordinationProtocol.RequireNoLinks(requestPath); SharedCoordinationProtocol.RequireNoLinks(resultPath);
        }
        catch { Dispose(); throw; }
    }

    public static string KeyHash(string key)
    {
        _ = PestoCliOptions.Parse(["--cli", "move", "--execute", "--plan", Path.GetFullPath("pesto-key-validation.json"), "--idempotency-key", key]);
        // The ASCII key uses exactly the V1 Get-PestoStableHash string representation, including JSON quotes.
        return AutomationPlanRules.Digest(JsonSerializer.Serialize("PestoAutomation|" + key));
    }

    public static string PayloadHash(AutomationPlan plan, AutomationHostContext context, bool entraLeaveConfirmed, string? approvalJson)
    {
        AutomationPlanRules.Validate(plan);
        return ConfigurationDocument.Fingerprint(new JsonObject
        {
            ["Schema"] = 1, ["Purpose"] = "PestoV2AutomationIntent", ["PlanIntegrity"] = plan.Integrity,
            ["ProfileSid"] = context.ProfileSid, ["OperatorSid"] = context.OperatorSid, ["MachineId"] = context.MachineId,
            ["ConfigurationIdentitySha256"] = AutomationPlanRules.ConfigurationIdentity(context.ConfigurationDirectory, context.ProfileSid),
            ["ConfigurationSha256"] = plan.ConfigurationSha256, ["EntraLeaveConfirmed"] = entraLeaveConfirmed,
            ["ApprovalSha256"] = approvalJson is null ? null : AutomationPlanRules.Digest(approvalJson),
        });
    }

    public PestoCliResult? ReadPrevious(string payloadSha256, AutomationPlan plan, DateTimeOffset now)
    {
        if (!File.Exists(requestPath))
        {
            if (File.Exists(resultPath)) throw Refused("Un résultat idempotent n'a plus son intention durable ; aucun nouvel envoi.");
            return null;
        }
        byte[] bytes; AutomationJournalRequest request;
        try { bytes = ReadBytes(requestPath); request = ReadRequest(bytes); }
        catch (Exception) { return Interrupted(null, now, "L'intention idempotente est illisible. Une action peut avoir été engagée ; aucun nouvel envoi ni rejeu."); }
        ValidateOwner(request, payloadSha256);
        if (request.PlanIntegrity != plan.Integrity || request.ConfigurationSha256 != plan.ConfigurationSha256)
            throw Refused("Le plan ne correspond plus à l'intention idempotente durable.");
        if (!File.Exists(resultPath)) return Interrupted(request.ReceiptId, now,
            "Une intention durable a été interrompue avant son résultat final. Aucun rejeu automatique ; inspectez le reçu lié.");
        try
        {
        using var doc = AutomationPlanRules.ParseObject(ReadBytes(resultPath));
        AutomationPlanRules.RequireFields(doc.RootElement, ["Schema", "RequestSha256", "PayloadSha256", "ReceiptSha256", "Utc", "Result"]);
        var saved = JsonSerializer.Deserialize<AutomationJournalResult>(doc.RootElement.GetRawText(), AutomationPlanRules.JsonOptions)
            ?? throw Refused("Résultat durable illisible.");
        if (saved.Schema != 1 || saved.RequestSha256 != AutomationPlanRules.Digest(bytes) || saved.PayloadSha256 != payloadSha256
            || saved.Utc == default || saved.Utc.Offset != TimeSpan.Zero || saved.Result is null
            || saved.Result.Schema != 1 || saved.Result.Mode != "CLI" || saved.Result.OperationId != request.ReceiptId
            || saved.Result.ExitCode is not (0 or 3010 or 96 or 97) || saved.Result.Observation is not null || saved.Result.Plan is not null
            || saved.Result.Replayed || saved.Result.Utc == default || saved.Result.Utc.Offset != TimeSpan.Zero
            || saved.Result.State is not ("Verified" or "PendingRestart" or "Refused" or "Uncertain" or "Partial")
            || saved.Result.ExitCode == 0 && (saved.Result.State != "Verified" || saved.Result.EngineCode is not (30 or 33) || saved.Result.RestartRequired)
            || saved.Result.ExitCode == 3010 && (saved.Result.State != "PendingRestart" || saved.Result.EngineCode is not (10 or 20 or 77) || !saved.Result.RestartRequired)
            || saved.Result.ExitCode == 96 && saved.Result.State != "Refused"
            || saved.Result.ExitCode == 97 && saved.Result.State is not ("Uncertain" or "Partial")
            || saved.Result.Message is not { Length: <= 1024 } || saved.Result.Message.Any(char.IsControl))
            throw Refused("Résultat idempotent incohérent ; aucune réussite ni nouvel envoi supposés.");
        if (saved.Result.Metadata is not null) _ = AutomationPlanRules.ValidateMetadata(saved.Result.Metadata);
        if (saved.Result.ExitCode is 0 or 3010)
        {
            if (!RemoteWindowsEvidenceProtocol.IsHash(saved.ReceiptSha256)) throw Refused("Empreinte du reçu métier absente.");
            using var proof = AutomationReceiptProof.Pin(context.GpRoot, request.ReceiptId, plan, now);
            if (proof.Sha256 != saved.ReceiptSha256) throw Refused("Le reçu métier a changé depuis le résultat idempotent.");
            proof.RequireResult(saved.Result);
        }
        else if (saved.ReceiptSha256 is not null) throw Refused("Empreinte inattendue pour un résultat sans succès confirmé.");
        return saved.Result with { Replayed = true };
        }
        catch (Exception) { return Interrupted(request.ReceiptId, now, "Le résultat final est illisible ou incohérent. L'intention reste bloquante ; aucune réussite ni nouvel envoi supposés."); }
    }

    private static PestoCliResult Interrupted(string? receiptId, DateTimeOffset now, string message) =>
        new(1, "CLI", "Uncertain", 97, null, false, true, receiptId, now, message, Replayed: true);

    public AutomationExecutionAuthorization Begin(AutomationPlan plan, string payloadSha256, bool entraLeaveConfirmed,
        string? approvalJson, DateTimeOffset now)
    {
        MutationSessionGuard.RequireWritableSession();
        var folder = Path.GetDirectoryName(requestPath)!;
        SharedCoordinationProtocol.RequireNoLinks(folder);
        if (OperatingSystem.IsWindows() && context.SecureDirectory is null) throw Refused("Protection ACL du registre d'idempotence indisponible.");
        Directory.CreateDirectory(folder);
        context.SecureDirectory?.Invoke(folder);
        MutationSessionGuard.RequireWritableSession();
        var request = new AutomationJournalRequest(1, keyHash, payloadSha256, "receipt-" + Guid.NewGuid().ToString("N"), plan.Integrity,
            context.ProfileSid, context.OperatorSid, context.MachineId, plan.ConfigurationSha256, now, "Started");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(request, AutomationPlanRules.JsonOptions);
        WriteExclusive(requestPath, bytes);
        return new(keyHash, payloadSha256, AutomationPlanRules.Digest(bytes), request.ReceiptId, plan,
            context.ProfileSid, context.OperatorSid, context.MachineId, entraLeaveConfirmed, approvalJson);
    }

    public void Complete(AutomationExecutionAuthorization authority, PestoCliResult result, DateTimeOffset now)
    {
        if (result.OperationId != authority.ReceiptId || result.Observation is not null || result.Replayed) throw Refused("Résultat étranger à cette intention.");
        RequireAuthority(context.GpRoot, authority);
        using var proof = result.ExitCode is 0 or 3010 ? AutomationReceiptProof.Pin(context.GpRoot, authority.ReceiptId, authority.Plan, now) : null;
        proof?.RequireResult(result);
        var saved = new AutomationJournalResult(1, authority.RequestSha256, authority.PayloadSha256, proof?.Sha256, now, result);
        WriteExclusive(resultPath, JsonSerializer.SerializeToUtf8Bytes(saved, AutomationPlanRules.JsonOptions));
    }

    /// <summary>Native final guard: verifies the same immutable requested bytes under the GP mutation mutex.</summary>
    public static void RequireAuthority(string gpRoot, AutomationExecutionAuthorization authority)
    {
        using var handle = PinAuthority(gpRoot, authority);
    }

    /// <summary>The native caller holds this read-only, no-delete-sharing handle until its final send has returned.</summary>
    public static FileStream PinAuthority(string gpRoot, AutomationExecutionAuthorization authority)
    {
        if (!RemoteWindowsEvidenceProtocol.IsHash(authority.KeyHash) || !RemoteWindowsEvidenceProtocol.IsHash(authority.PayloadSha256)
            || !RemoteWindowsEvidenceProtocol.IsHash(authority.RequestSha256)) throw Refused("Empreinte d'autorisation automatique absente.");
        var folder = Path.Combine(gpRoot, "V2", "automation");
        var path = Path.Combine(folder, authority.KeyHash + ".request.json");
        SharedCoordinationProtocol.RequireNoLinks(path);
        var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
        if (input.Length is < 1 or > MaximumBytes) throw Refused("Intention automatique hors limites.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
        if (AutomationPlanRules.Digest(bytes) != authority.RequestSha256 || File.Exists(Path.Combine(folder, authority.KeyHash + ".result.json")))
            throw Refused("L'intention a changé ou possède déjà un résultat final : aucun rejeu.");
        var request = ReadRequest(bytes);
        if (request.KeyHash != authority.KeyHash || request.PayloadSha256 != authority.PayloadSha256 || request.ReceiptId != authority.ReceiptId
            || request.PlanIntegrity != authority.Plan.Integrity || request.ProfileSid != authority.ProfileSid || request.OperatorSid != authority.OperatorSid
            || request.MachineId != authority.MachineId || request.ConfigurationSha256 != authority.Plan.ConfigurationSha256)
            throw Refused("L'autorisation ne correspond plus aux octets de l'intention durable.");
        return input;
        }
        catch { input.Dispose(); throw; }
    }

    private void ValidateOwner(AutomationJournalRequest request, string payload)
    {
        if (request.KeyHash != keyHash || request.PayloadSha256 != payload || request.ProfileSid != context.ProfileSid
            || request.OperatorSid != context.OperatorSid || !AutomationPlanRules.Same(request.MachineId, context.MachineId))
            throw Refused("Clé déjà utilisée pour une autre intention, configuration, machine ou identité ; aucun rejeu.");
    }

    private static AutomationJournalRequest ReadRequest(byte[] bytes)
    {
        using var doc = AutomationPlanRules.ParseObject(bytes);
        AutomationPlanRules.RequireFields(doc.RootElement, ["Schema", "KeyHash", "PayloadSha256", "ReceiptId", "PlanIntegrity", "ProfileSid", "OperatorSid", "MachineId", "ConfigurationSha256", "Utc", "State"]);
        var request = JsonSerializer.Deserialize<AutomationJournalRequest>(doc.RootElement.GetRawText(), AutomationPlanRules.JsonOptions)
            ?? throw Refused("Intention automatique illisible.");
        if (request.Schema != 1 || request.State != "Started" || request.Utc == default || request.Utc.Offset != TimeSpan.Zero
            || !RemoteWindowsEvidenceProtocol.IsHash(request.KeyHash) || !RemoteWindowsEvidenceProtocol.IsHash(request.PayloadSha256)
            || !RemoteWindowsEvidenceProtocol.IsHash(request.PlanIntegrity) || !RemoteWindowsEvidenceProtocol.IsHash(request.ConfigurationSha256)
            || !AutomationPlanRules.Sid(request.ProfileSid) || !AutomationPlanRules.Sid(request.OperatorSid)
            || !RemoteWindowsEvidenceProtocol.IsGuid(request.MachineId) || request.ReceiptId is not { Length: 40 }
            || !request.ReceiptId.StartsWith("receipt-", StringComparison.Ordinal) || !Guid.TryParseExact(request.ReceiptId[8..], "N", out _))
            throw Refused("Intention automatique incomplète ; aucun nouvel envoi.");
        return request;
    }

    private static byte[] ReadBytes(string path)
    {
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > MaximumBytes) throw Refused("Registre automatique vide ou trop volumineux.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes); return bytes;
    }
    private static void WriteExclusive(string path, byte[] bytes)
    {
        if (bytes.Length is < 1 or > MaximumBytes) throw Refused("Registre automatique hors limites.");
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        output.Write(bytes); output.Flush(flushToDisk: true);
    }
    private static PestoException Refused(string message) => new("automation.idempotency", message);
    public void Dispose() { if (owned) { owned = false; mutex.ReleaseMutex(); } mutex.Dispose(); }
}
