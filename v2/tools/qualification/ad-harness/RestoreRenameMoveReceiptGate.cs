using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

// ReadReconciliation may inspect Entra. Never call it until BOTH raw receipts prove this local, Entra-free campaign.
internal sealed class RestoreRenameMoveReceiptGate : IDisposable
{
    internal const string MachineId = "81387449-2dd8-4bd9-8059-f868a5b8ec68";
    private const int MaximumBytes = 65536;
    private readonly FileStream source;
    private readonly FileStream returned;
    private readonly string sourceId;
    private readonly string returnId;
    private bool disposed;
    public string SourceHash { get; }
    public string ReturnHash { get; }

    private RestoreRenameMoveReceiptGate(FileStream source, FileStream returned, string sourceId, string returnId,
        byte[] sourceBytes, byte[] returnBytes)
    {
        this.source = source; this.returned = returned; this.sourceId = sourceId; this.returnId = returnId;
        SourceHash = Hash(sourceBytes); ReturnHash = Hash(returnBytes);
    }

    public static RestoreRenameMoveReceiptGate Open(string gpRoot, string sourceId, string returnId)
    {
        if (sourceId != RestoreRenameMovePolicy.SourceReceiptId
            || !Regex.IsMatch(returnId, "\\Areceipt-[a-fA-F0-9]{32}\\z", RegexOptions.CultureInvariant)
            || string.Equals(sourceId, returnId, StringComparison.OrdinalIgnoreCase)) throw Refused();
        FileStream? source = null, returned = null;
        try
        {
            source = OpenPinned(Path.Combine(gpRoot, "V2", "receipts", sourceId + ".json"));
            returned = OpenPinned(Path.Combine(gpRoot, "V2", "receipts", returnId + ".json"));
            var sourceBytes = ReadBounded(source);
            var returnBytes = ReadBounded(returned);
            ValidatePair(sourceBytes, returnBytes, sourceId, returnId);
            return new(source, returned, sourceId, returnId, sourceBytes, returnBytes);
        }
        catch { returned?.Dispose(); source?.Dispose(); throw; }
    }

    // This is the ONLY entry point for the two adapter calls. A bad second receipt means zero adapter calls.
    public (T Source, T Returned) Observe<T>(Func<string, T> observe)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        var sourceBytes = ReadBounded(source);
        var returnBytes = ReadBounded(returned);
        if (Hash(sourceBytes) != SourceHash || Hash(returnBytes) != ReturnHash) throw Refused();
        ValidatePair(sourceBytes, returnBytes, sourceId, returnId);
        return (observe(sourceId), observe(returnId));
    }

    private static FileStream OpenPinned(string path)
    {
        NoLinks(path);
        // On Windows these handles deny write/delete/replacement until Dispose, including during adapter reads.
        var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try { NoLinks(path); return stream; }
        catch { stream.Dispose(); throw; }
    }

    private static byte[] ReadBounded(FileStream stream)
    {
        NoLinks(stream.Name);
        if (stream.Length is < 1 or > MaximumBytes) throw Refused();
        var bytes = new byte[checked((int)stream.Length)];
        stream.Position = 0;
        stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1) throw Refused();
        return bytes;
    }

    private static void NoLinks(string path)
    {
        for (string? current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw Refused();
    }

    private static void ValidatePair(byte[] sourceBytes, byte[] returnBytes, string sourceId, string returnId)
    {
        using var sourceDoc = JsonDocument.Parse(sourceBytes, new JsonDocumentOptions { MaxDepth = 32 });
        using var returnDoc = JsonDocument.Parse(returnBytes, new JsonDocumentOptions { MaxDepth = 32 });
        var s = sourceDoc.RootElement; var r = returnDoc.RootElement;
        ValidateCommon(s, sourceId); ValidateCommon(r, returnId);
        if (String(s, "Kind") != "renameMove" || Number(s, "Code") != 77
            || !Same(String(s, "Computer"), RestoreNamePolicy.OriginalName)
            || !Same(String(s, "NewName"), RestoreRenameMovePolicy.CurrentName)
            || !Same(String(s, "InitialOu"), RestoreNamePolicy.Paris)
            || !Same(String(s, "TargetOu"), RestoreRenameMovePolicy.Lyon)
            || String(r, "Kind") != "move" || Number(r, "Code") != 30
            || !Same(String(r, "Computer"), RestoreRenameMovePolicy.CurrentName)
            || String(r, "NewName") is { Length: > 0 } newName && !Same(newName, RestoreRenameMovePolicy.CurrentName)
            || !Same(String(r, "InitialOu"), RestoreRenameMovePolicy.Lyon)
            || !Same(String(r, "TargetOu"), RestoreNamePolicy.Paris)) throw Refused();
        var sourceCreated = Date(s, "CreatedUtc"); var sourceVerified = Date(s, "Utc");
        var returnBoot = Date(r, "InitialBootUtc"); var returnCreated = Date(r, "CreatedUtc");
        if (Date(s, "InitialBootUtc") >= sourceCreated || sourceCreated >= sourceVerified
            || sourceVerified >= returnCreated || returnCreated > Date(r, "Utc")
            || sourceCreated >= returnBoot || returnBoot > returnCreated)
            throw Refused();
    }

    private static void ValidateCommon(JsonElement receipt, string id)
    {
        if (receipt.ValueKind != JsonValueKind.Object) throw Refused();
        var fields = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var field in receipt.EnumerateObject()) if (!fields.Add(field.Name)) throw Refused();
        if (Number(receipt, "Schema") != 1 || String(receipt, "Version") != "2.0"
            || String(receipt, "Phase") != "Verified" || String(receipt, "ReceiptId") != id
            || Flag(receipt, "RestartRequired") != false || Flag(receipt, "LocalTarget") != true
            || !Same(String(receipt, "ComputerGuid"), RestoreNamePolicy.Guid)
            || !Same(String(receipt, "MachineId"), MachineId)
            || !Same(String(receipt, "Domain"), RestoreNamePolicy.Domain)
            || !Same(String(receipt, "Dc"), LabDomain.Dc)
            || !Same(String(receipt, "InitialWindowsDomain"), RestoreNamePolicy.Domain)
            || Flag(receipt, "InitialPartOfDomain") != true || Number(receipt, "InitialDomainRole") != 1
            || Flag(receipt, "InitialProtected") != false
            || String(receipt, "Entra") is not (null or "NotRequested" or "Skipped")
            || String(receipt, "EntraEvidenceId") is not null || String(receipt, "EntraEvidenceSha256") is not null
            || Flag(receipt, "EntraMayStillRun") == true || Flag(receipt, "EntraReenrollmentPending") == true)
            throw Refused();
    }

    private static string? String(JsonElement value, string key) => !value.TryGetProperty(key, out var field)
        || field.ValueKind == JsonValueKind.Null ? null : field.ValueKind == JsonValueKind.String ? field.GetString() : throw Refused();
    private static bool? Flag(JsonElement value, string key) => !value.TryGetProperty(key, out var field)
        || field.ValueKind == JsonValueKind.Null ? null : field.ValueKind switch
        { JsonValueKind.True => true, JsonValueKind.False => false, _ => throw Refused() };
    private static int Number(JsonElement value, string key) => value.TryGetProperty(key, out var field)
        && field.TryGetInt32(out var number) ? number : throw Refused();
    private static DateTimeOffset Date(JsonElement value, string key) => DateTimeOffset.TryParse(String(value, key),
        CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var result) && result.Offset == TimeSpan.Zero ? result : throw Refused();
    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static InvalidOperationException Refused() => new("Both raw receipts must identify only the recorded local renameMove and its verified Paris return, without Entra activity.");
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; returned.Dispose(); source.Dispose();
    }
}
