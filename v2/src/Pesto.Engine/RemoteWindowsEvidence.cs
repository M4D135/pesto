using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Native-only binding. Computer is the connection target; expected active/configured names may differ only for an explicit pending restart.</summary>
public sealed record RemoteWindowsEvidenceRequest(string ReceiptId, string Computer, string Domain, string Dc,
    string ExpectedAdGuid, string? ExpectedMachineId, string? ReceiptSha256, string Purpose,
    string ExpectedActiveName, string ExpectedConfiguredName);

public sealed record RemoteWindowsSnapshot(int Schema, string Nonce, string RequestSha256, string ReceiptId,
    string ExpectedAdGuid, string SystemSid, string ActiveName, string ConfiguredName, string Domain,
    bool PartOfDomain, int DomainRole, string MachineId, DateTimeOffset BootUtc, DateTimeOffset ObservedUtc, bool? SecureChannel);

/// <summary>Exact returned bytes are kept so the persisted result hash can be verified without probing the remote host.</summary>
public sealed record RemoteWindowsProof(int Schema, RemoteWindowsEvidenceRequest Request, string Nonce, string TaskName,
    string DefinitionSha256, string ResultSha256, string ResultJson, DateTimeOffset CollectedUtc, bool CleanupConfirmed);

public sealed record RemoteWindowsEvidenceResult(RemoteWindowsProof? Proof, string Message, bool Uncertain, string? TaskName = null);

public interface IRemoteWindowsEvidenceFiles
{
    byte[] Read(string computer, string nonce);
    void DeleteExact(string computer, string nonce, string expectedSha256);
}

public static class RemoteWindowsEvidenceProtocol
{
    public const int MaximumResultBytes = 16384;
    public static bool IsName(string? value) => value is { Length: > 0 and <= 15 }
        && Regex.IsMatch(value, @"\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?\z", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    public static bool IsHash(string? value) => value is { Length: 64 } && value.All(char.IsAsciiHexDigit);
    public static bool IsNonce(string? value) => value is { Length: 32 } && value.All(c => char.IsAsciiDigit(c) || c is >= 'a' and <= 'f');
    public static bool IsId(string? value) => value is { Length: > 0 and <= 128 } && value.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');
    public static bool IsGuid(string? value) => Guid.TryParse(value, out var id) && id != Guid.Empty;
    public static bool Same(string? a, string? b) => !string.IsNullOrEmpty(a) && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public static string Hash(ReadOnlySpan<byte> bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    public static string RequestHash(RemoteWindowsEvidenceRequest request, string nonce) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { Request = request, Nonce = nonce }));
    public static string TaskName(string nonce) => IsNonce(nonce) ? "\\Pesto_WindowsProof_" + nonce[..12] : throw Invalid("Nonce invalide.");

    public static void ValidateRequest(RemoteWindowsEvidenceRequest request)
    {
        if (request is null || !IsId(request.ReceiptId) || !IsName(request.Computer) || !IsName(request.ExpectedActiveName)
            || !IsName(request.ExpectedConfiguredName) || !SharedCoordinationProtocol.IsDomainName(request.Domain)
            || !JoinClockGuard.IsServer(request.Dc) || !IsGuid(request.ExpectedAdGuid)
            || request.ExpectedMachineId is not null && !IsGuid(request.ExpectedMachineId)
            || request.ReceiptSha256 is not null && !IsHash(request.ReceiptSha256)
            || request.Purpose is not ("baseline" or "reconciliation" or "continuation" or "restart")) throw Invalid("Identité de diagnostic Windows invalide.");
        if (request.Purpose != "baseline" && (request.ExpectedMachineId is null || request.ReceiptSha256 is null))
            throw Invalid("Une preuve initiale et le SHA du reçu sont nécessaires ; les anciens reçus incomplets ne sont pas complétés par supposition.");
        if (request.Purpose != "restart" && (!Same(request.ExpectedActiveName, request.ExpectedConfiguredName) || !Same(request.Computer, request.ExpectedActiveName)))
            throw Invalid("Cible et noms Windows du diagnostic incohérents.");
        if (request.Purpose == "restart" && !Same(request.Computer, request.ExpectedActiveName)) throw Invalid("Le redémarrage doit cibler le nom actif prouvé.");
    }

    public static RemoteWindowsSnapshot ReadResult(RemoteWindowsEvidenceRequest request, string nonce, ReadOnlyMemory<byte> bytes)
    {
        ValidateRequest(request);
        if (!IsNonce(nonce) || bytes.Length is < 1 or > MaximumResultBytes) throw Invalid("Réponse Windows absente ou hors limites.");
        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            RequireClosed(root, ["Schema", "Nonce", "RequestSha256", "ReceiptId", "ExpectedAdGuid", "SystemSid", "ActiveName", "ConfiguredName", "Domain", "PartOfDomain", "DomainRole", "MachineId", "BootUtc", "ObservedUtc", "SecureChannel"]);
            var value = root.Deserialize<RemoteWindowsSnapshot>() ?? throw Invalid("Réponse Windows absente.");
            if (value.Schema != 1 || value.Nonce != nonce || value.RequestSha256 != RequestHash(request, nonce)
                || value.ReceiptId != request.ReceiptId || !Same(value.ExpectedAdGuid, request.ExpectedAdGuid) || value.SystemSid != "S-1-5-18"
                || !Same(value.ActiveName, request.ExpectedActiveName) || !Same(value.ConfiguredName, request.ExpectedConfiguredName)
                || !Same(value.Domain, request.Domain) || !value.PartOfDomain || value.DomainRole is not (1 or 3)
                || !IsGuid(value.MachineId) || request.ExpectedMachineId is not null && !Same(value.MachineId, request.ExpectedMachineId)
                || value.BootUtc == default || value.ObservedUtc == default || value.BootUtc.Offset != TimeSpan.Zero
                || value.ObservedUtc.Offset != TimeSpan.Zero || value.BootUtc > value.ObservedUtc) throw Invalid("La réponse ne prouve pas les identités Windows attendues.");
            return value;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException)
        { throw Invalid("Réponse Windows illisible ou incomplète ; aucune identité supposée."); }
    }

    public static RemoteWindowsSnapshot ValidateProof(RemoteWindowsProof proof, bool requireCleanup = true)
    {
        if (proof is null || proof.Schema != 1 || proof.Request is null || !IsNonce(proof.Nonce)
            || proof.TaskName != TaskName(proof.Nonce) || !IsHash(proof.DefinitionSha256) || !IsHash(proof.ResultSha256)
            || proof.ResultJson is null || Encoding.UTF8.GetByteCount(proof.ResultJson) > MaximumResultBytes
            || proof.CollectedUtc == default || proof.CollectedUtc.Offset != TimeSpan.Zero || requireCleanup && !proof.CleanupConfirmed)
            throw Invalid("Preuve Windows distante incomplète ou nettoyage non confirmé.");
        var bytes = Encoding.UTF8.GetBytes(proof.ResultJson);
        if (Hash(bytes) != proof.ResultSha256) throw Invalid("Les octets de la preuve Windows distante ont changé.");
        return ReadResult(proof.Request, proof.Nonce, bytes);
    }

    public static RemoteWindowsProof ReadProof(JsonElement root)
    {
        try
        {
            RequireClosed(root, ["Schema", "Request", "Nonce", "TaskName", "DefinitionSha256", "ResultSha256", "ResultJson", "CollectedUtc", "CleanupConfirmed"]);
            RequireClosed(root.GetProperty("Request"), ["ReceiptId", "Computer", "Domain", "Dc", "ExpectedAdGuid", "ExpectedMachineId", "ReceiptSha256", "Purpose", "ExpectedActiveName", "ExpectedConfiguredName"]);
            var proof = root.Deserialize<RemoteWindowsProof>() ?? throw Invalid("Preuve absente.");
            _ = ValidateProof(proof); return proof;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException)
        { throw Invalid("Preuve Windows distante mal formée."); }
    }

    internal static void RequireClosed(JsonElement root, string[] fields)
    {
        if (root.ValueKind != JsonValueKind.Object) throw Invalid("Objet attendu.");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in root.EnumerateObject())
            if (!fields.Contains(property.Name, StringComparer.Ordinal) || !seen.Add(property.Name)) throw Invalid("Champ inconnu ou dupliqué.");
        if (seen.Count != fields.Length) throw Invalid("Preuve incomplète.");
    }
    internal static PestoException Invalid(string message) => new("receipt.remote_evidence", message);
}
