using System.Security.Cryptography;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record RestartReceiptSnapshot(Receipt Receipt, string Sha256, string Domain, string? Dc,
    string? ComputerGuid, string MachineId, DateTimeOffset InitialBootUtc, bool LocalTarget,
    string? InitialWindowsDomain = null, bool? InitialPartOfDomain = null, int? InitialDomainRole = null, string? InitialOu = null,
    bool PartialRenameMove = false, bool? InitialProtected = null)
{
    public string ExpectedAdOu => PartialRenameMove ? InitialOu ?? "" : Receipt.TargetOU;
}

public sealed record RestartTargetEvidence(string ActiveName, string ConfiguredName, string Domain, bool PartOfDomain,
    int DomainRole, string MachineId, DateTimeOffset BootUtc, string? AdGuid, string? AdName, bool LocalTarget,
    DateTimeOffset ObservedUtc, string? Error = null, RemoteWindowsProof? RemoteProof = null, string? AdOu = null, bool? AdProtected = null);

/// <summary>Held only by the native engine plan; callers of the bridge never provide this authorization.</summary>
public sealed record RestartAuthorization(string Token, string PlanId, RestartReceiptSnapshot Source,
    RestartTargetEvidence Evidence, DateTimeOffset ExpiresAt, string ConfigurationSha256);
public sealed record RestartPreparation(RestartAuthorization Authorization, Receipt Receipt);
public sealed record RestartCommand(string Id, string ReceiptId, string ReceiptSha256, string PlanId,
    string Computer, string ConfiguredName, string Domain, string? ComputerGuid, string MachineId,
    DateTimeOffset BootUtc, bool LocalTarget, DateTimeOffset RequestedUtc, string OperationKind,
    bool AllowPendingJoin = false, string? InitialWindowsDomain = null, int? InitialDomainRole = null,
    string? AuthorizationConfigurationSha256 = null);
public sealed record RestartNativeResult(string Status, string Message);
public sealed record RestartResult(Receipt Receipt, string Id, string Status, string Computer, DateTimeOffset Utc, string Message);

public interface IMutationRestart
{
    RestartPreparation PrepareRestart(string receiptId, string planId, string configurationSha256);
    RestartResult Restart(RestartAuthorization authorization);
}

public interface IReceiptRestartEnvironment
{
    RestartReceiptSnapshot ReadSource(string receiptId);
    void RequireAdmission(RestartReceiptSnapshot source, string configurationSha256);
    RestartTargetEvidence ReadTarget(RestartReceiptSnapshot source);
    RestartNativeResult Send(RestartCommand command);
}

public static class ReceiptRestartRules
{
    public static RestartReceiptSnapshot ReadSource(string path, ReadOnlyMemory<byte> bytes, DateTimeOffset observedUtc)
    {
        var parsed = GpHistory.ParseAdapterSnapshot(path, bytes, observedUtc);
        if (parsed.Readable && parsed.Receipt.Kind == "offlineJoin")
            throw Refused("Ce reçu ODJ reste sous le contrôle de Pesto.exe --offline-join ; le redémarrage général ne dispose pas de sa preuve spécialisée.");
        using var document = JsonDocument.Parse(bytes);
        var root = document.RootElement;
        string? Text(string key) => root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        var partial = parsed.Receipt.Kind == "renameMove" && parsed.Receipt.Code == 89
            && Text("Phase") is ("PendingRestart" or "Uncertain" or "Partial");
        if (!parsed.Readable || parsed.Acknowledged || (!partial && Text("Phase") != "PendingRestart") || !parsed.Receipt.RestartRequired
            || parsed.Receipt.Kind is not ("join" or "rename" or "renameMove")
            || !RemoteWindowsEvidenceProtocol.IsGuid(Text("MachineId")) || !RemoteWindowsEvidenceProtocol.IsHash(Text("ConfigurationSha256"))
            || !SharedCoordinationProtocol.IsDomainName(Text("Domain")) || !JoinClockGuard.IsServer(Text("Dc"))
            || !DateTimeOffset.TryParse(Text("InitialBootUtc"), out var boot) || boot == default || boot.Offset != TimeSpan.Zero
            || !root.TryGetProperty("LocalTarget", out var local) || local.ValueKind is not (JsonValueKind.True or JsonValueKind.False)
            || !RemoteWindowsEvidenceProtocol.IsName(parsed.Receipt.NewName))
            throw Refused("Seul un reçu PendingRestart ou un parent 89 non acquitté avec identité AD, Windows et boot initial complets permet de préparer un redémarrage.");
        if (!RemoteWindowsEvidenceProtocol.IsGuid(Text("ComputerGuid")) && !(local.GetBoolean() && parsed.Receipt.Kind == "join" && Text("ComputerGuid") is null))
            throw Refused("GUID AD non confirmé pour ce reçu ; aucun redémarrage envoyé.");
        if (!partial && parsed.Receipt.Code != (parsed.Receipt.Kind == "join" ? 10 : parsed.Receipt.Kind == "rename" ? 20 : 77))
            throw Refused("Ce reçu ne consigne pas un code natif accepté avec redémarrage attendu.");
        var initialProtected = root.TryGetProperty("InitialProtected", out var protection) && protection.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? (bool?)protection.GetBoolean() : null;
        if (partial && (!RemoteWindowsEvidenceProtocol.IsGuid(Text("ComputerGuid")) || !V1Config.IsOuPath(Text("InitialOu") ?? "")
            || initialProtected is null || RemoteWindowsEvidenceProtocol.Same(parsed.Receipt.Computer, parsed.Receipt.NewName)
            || new[] { "ContinuationChildReceiptId", "ContinuationChildPlanId", "ResolutionChildReceiptId" }.Any(key => Text(key) is not null)))
            throw Refused("Le parent 89 doit conserver l’OU source et sa protection, sans reprise de déplacement déjà engagée : aucun redémarrage autorisé sinon.");
        if (!local.GetBoolean() && (!ReceiptWindowsEvidence.RemoteBaselineMatches(root) || parsed.Receipt.Kind == "join"))
            throw Refused("La baseline Windows distante est absente ou invalide ; aucun redémarrage distant préparé pour cet ancien reçu.");
        return new(parsed.Receipt, Convert.ToHexString(SHA256.HashData(bytes.Span)), Text("Domain")!, Text("Dc"),
            Text("ComputerGuid"), Text("MachineId")!, boot, local.GetBoolean(), Text("InitialWindowsDomain"),
            root.TryGetProperty("InitialPartOfDomain", out var membership) && membership.ValueKind is JsonValueKind.True or JsonValueKind.False ? membership.GetBoolean() : null,
            root.TryGetProperty("InitialDomainRole", out var role) && role.ValueKind == JsonValueKind.Number && role.TryGetInt32(out var roleValue) ? roleValue : null,
            Text("InitialOu"), partial, initialProtected);
    }

    public static void RequireTarget(RestartReceiptSnapshot source, RestartTargetEvidence target, DateTimeOffset now)
    {
        if (target.Error is not null || target.LocalTarget != source.LocalTarget
            || !RemoteWindowsEvidenceProtocol.Same(target.MachineId, source.MachineId)
            || (source.ComputerGuid is not null && (!RemoteWindowsEvidenceProtocol.Same(target.AdGuid, source.ComputerGuid)
                || !RemoteWindowsEvidenceProtocol.Same(target.AdName, source.Receipt.NewName)
                || !RemoteWindowsEvidenceProtocol.Same(target.AdOu, source.ExpectedAdOu)))
            || source.PartialRenameMove && (source.InitialProtected is null || target.AdProtected != source.InitialProtected)
            || !RemoteWindowsEvidenceProtocol.Same(target.ConfiguredName, source.Receipt.NewName)
            || !(RemoteWindowsEvidenceProtocol.Same(target.ActiveName, source.Receipt.Computer)
                || RemoteWindowsEvidenceProtocol.Same(target.ActiveName, source.Receipt.NewName))
            || !(target.PartOfDomain && target.DomainRole is 1 or 3 && RemoteWindowsEvidenceProtocol.Same(target.Domain, source.Domain)
                || IsPendingLocalJoin(source, target))
            || target.BootUtc == default || target.BootUtc.Offset != TimeSpan.Zero
            || target.ObservedUtc < now.AddMinutes(-2) || target.ObservedUtc > now.AddSeconds(5))
            throw Refused("L’identité Windows/AD, le domaine, les noms et le rôle du poste à redémarrer ne sont pas prouvés ensemble.");
        if (target.BootUtc != source.InitialBootUtc)
            throw Refused("Le boot a changé depuis l’opération : vérifiez d’abord le reçu après redémarrage ; aucune nouvelle demande de redémarrage.");
        if (target.LocalTarget)
        {
            if (target.RemoteProof is not null) throw Refused("Une preuve distante ne remplace pas l’identité locale.");
        }
        else
        {
            if (target.RemoteProof is not { } proof) throw Refused("Preuve SYSTEM distante requise avant redémarrage.");
            var windows = RemoteWindowsEvidenceProtocol.ValidateProof(proof);
            if (proof.Request.Purpose != "restart" || proof.Request.ReceiptId != source.Receipt.Id
                || !RemoteWindowsEvidenceProtocol.Same(proof.Request.ReceiptSha256, source.Sha256)
                || !RemoteWindowsEvidenceProtocol.Same(windows.MachineId, target.MachineId) || windows.BootUtc != target.BootUtc
                || !RemoteWindowsEvidenceProtocol.Same(windows.ActiveName, target.ActiveName)
                || !RemoteWindowsEvidenceProtocol.Same(windows.ConfiguredName, target.ConfiguredName)
                || !RemoteWindowsEvidenceProtocol.Same(windows.Domain, target.Domain))
                throw Refused("La preuve SYSTEM distante ne correspond pas à ce reçu et à ce boot.");
        }
    }

    public static bool IsPendingLocalJoin(RestartReceiptSnapshot source, RestartTargetEvidence target) =>
        source.LocalTarget && source.Receipt.Kind == "join" && source.InitialPartOfDomain == false
        && source.InitialDomainRole is 0 or 2 && target.DomainRole == source.InitialDomainRole && !target.PartOfDomain
        && RemoteWindowsEvidenceProtocol.Same(target.Domain, source.InitialWindowsDomain)
        && RemoteWindowsEvidenceProtocol.Same(target.ActiveName, source.Receipt.Computer);

    public static void ValidateCommand(RestartCommand command)
    {
        if (!RemoteWindowsEvidenceProtocol.IsId(command.Id) || command.Id.Length != 40 || !command.Id.StartsWith("restart-", StringComparison.Ordinal)
            || !Guid.TryParseExact(command.Id[8..], "N", out var requestId) || requestId == Guid.Empty
            || !RemoteWindowsEvidenceProtocol.IsId(command.ReceiptId) || !RemoteWindowsEvidenceProtocol.IsId(command.PlanId)
            || !RemoteWindowsEvidenceProtocol.IsHash(command.ReceiptSha256) || !RemoteWindowsEvidenceProtocol.IsHash(command.AuthorizationConfigurationSha256)
            || !RemoteWindowsEvidenceProtocol.IsName(command.Computer)
            || !RemoteWindowsEvidenceProtocol.IsName(command.ConfiguredName) || !SharedCoordinationProtocol.IsDomainName(command.Domain)
            || (!RemoteWindowsEvidenceProtocol.IsGuid(command.ComputerGuid) && !(command.ComputerGuid is null && command.LocalTarget && command.OperationKind == "join"))
            || !RemoteWindowsEvidenceProtocol.IsGuid(command.MachineId) || command.OperationKind is not ("join" or "rename" or "renameMove")
            || command.AllowPendingJoin && (!command.LocalTarget || command.OperationKind != "join" || command.InitialDomainRole is not (0 or 2)
                || string.IsNullOrWhiteSpace(command.InitialWindowsDomain) || command.InitialWindowsDomain.Length > 253 || command.InitialWindowsDomain.Any(char.IsControl))
            || command.BootUtc == default || command.BootUtc.Offset != TimeSpan.Zero
            || command.RequestedUtc == default || command.RequestedUtc.Offset != TimeSpan.Zero)
            throw Refused("Demande de redémarrage invalide.");
    }

    public static PestoException Refused(string message) => new("restart.refused", message);
}
