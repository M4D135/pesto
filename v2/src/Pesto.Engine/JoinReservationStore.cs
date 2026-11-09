using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Atomic, bounded and closed-schema storage. Callers serialize mutations under the GP mutex.
/// IDs are file names derived by this store, never paths supplied by a browser.</summary>
public sealed class JoinReservationStore
{
    private const long MaximumBytes = 65536;
    private static readonly JsonSerializerOptions Options = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public string DirectoryPath { get; }
    public JoinReservationStore(string gpRoot)
    {
        if (!Path.IsPathFullyQualified(gpRoot) || gpRoot.StartsWith("\\\\", StringComparison.Ordinal))
            throw new IOException("Le registre de réservation doit être un dossier local absolu.");
        DirectoryPath = Path.Combine(Path.GetFullPath(gpRoot), "V2", "reservations");
        RequirePlain(DirectoryPath);
    }

    public static string MarkerFor(string operationId) => "Réservé par Pesto [" + operationId + "]";
    public static bool IsId(string? id) => id is not null && Regex.IsMatch(id, "^reservation-[a-f0-9]{32}$", RegexOptions.CultureInvariant);
    public static bool IsOpaqueId(string? id) => id is { Length: > 0 and <= 128 }
        && id.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.');
    public static bool IsHash(string? value) => value is not null && Regex.IsMatch(value, "^[a-f0-9]{64}$", RegexOptions.CultureInvariant);
    public static bool IsGuid(string? value) => Guid.TryParse(value, out var guid) && guid != Guid.Empty;
    public static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public static bool IsTerminal(string state) => state is "consumed" or "released" or "gone" or "taken" or "refused";
    private string PathFor(string id) => IsId(id) ? Path.Combine(DirectoryPath, id + ".json")
        : throw new PestoException("reservation.id", "Identifiant de réservation invalide.");

    public IReadOnlyList<JoinReservationReceipt> List()
    {
        RequirePlain(DirectoryPath);
        if (!Directory.Exists(DirectoryPath)) return [];
        var paths = Directory.EnumerateFiles(DirectoryPath, "*.json", SearchOption.TopDirectoryOnly).Take(5001).ToArray();
        if (paths.Length > 5000) throw new IOException("Trop de reçus de réservation : vérification manuelle nécessaire.");
        return paths.Select(p => Read(Path.GetFileNameWithoutExtension(p))).OrderByDescending(r => r.CreatedUtc).ToArray();
    }

    public JoinReservationReceipt Read(string id) => Decode(ReadBytes(id), id);
    public (JoinReservationReceipt Receipt, string Stamp) ReadStamped(string id)
    {
        var bytes = ReadBytes(id);
        return (Decode(bytes, id), Digest(bytes));
    }
    public string Stamp(string id) => Digest(ReadBytes(id));
    public static string Digest(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private byte[] ReadBytes(string id)
    {
        var path = PathFor(id);
        RequirePlain(path);
        var info = new FileInfo(path);
        if (!info.Exists || info.Length is < 1 or > MaximumBytes) throw new IOException("Reçu de réservation absent ou illisible.");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is < 1 or > MaximumBytes) throw new IOException("Reçu de réservation trop volumineux.");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        _ = Decode(bytes, id);
        return bytes;
    }

    private static JoinReservationReceipt Decode(byte[] bytes, string id)
    {
        try
        {
            using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 8 });
            RequireUnique(document.RootElement);
            var receipt = JsonSerializer.Deserialize<JoinReservationReceipt>(bytes, Options)
                ?? throw new JsonException();
            Validate(receipt);
            if (receipt.Id != id) throw new JsonException("Identité de fichier différente du reçu.");
            return receipt;
        }
        catch (Exception error) when (error is JsonException or ArgumentException or InvalidOperationException or NullReferenceException)
        { throw new IOException("Le reçu de réservation ne respecte pas le schéma fermé.", error); }
    }

    private static void RequireUnique(JsonElement node)
    {
        if (node.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in node.EnumerateObject())
            { if (!names.Add(property.Name)) throw new JsonException("Champ dupliqué."); RequireUnique(property.Value); }
        }
        else if (node.ValueKind == JsonValueKind.Array) foreach (var item in node.EnumerateArray()) RequireUnique(item);
    }

    public static void Validate(JoinReservationReceipt r)
    {
        static bool Name(string? s) => s is not null && Regex.IsMatch(s, "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$", RegexOptions.CultureInvariant);
        static bool Dns(string? s) => s is { Length: > 2 and <= 253 } && Regex.IsMatch(s, "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$", RegexOptions.CultureInvariant);
        if (r.Schema != 1 || !IsId(r.Id) || !IsGuid(r.OperationId) || !IsGuid(r.MachineId)
            || !IsOpaqueId(r.ParentReceiptId) || r.JoinReceiptIds is null || r.JoinReceiptIds.Length is < 1 or > 32
            || r.JoinReceiptIds.Any(id => !IsOpaqueId(id)) || r.JoinReceiptIds.Distinct(StringComparer.Ordinal).Count() != r.JoinReceiptIds.Length
            || r.JoinReceiptIds[0] != r.ParentReceiptId || !Name(r.Computer) || !Name(r.Name)
            || !Dns(r.Domain) || !Dns(r.Dc) || Same(r.Domain, r.Dc) || !r.Dc.EndsWith("." + r.Domain, StringComparison.OrdinalIgnoreCase)
            || r.TargetOu is null || r.TargetOu.Length > 2048 || !V1Config.IsOuPath(r.TargetOu) || !IsGuid(r.TargetOuGuid)
            || !r.TargetOu.EndsWith("," + string.Join(",", r.Domain.Split('.').Select(p => "DC=" + p)), StringComparison.OrdinalIgnoreCase)
            || r.Marker != MarkerFor(r.OperationId) || (r.ComputerGuid is not null && !IsGuid(r.ComputerGuid))
            || r.State is not ("pending" or "reserved" or "joining" or "releasing" or "uncertain" or "kept" or "consumed" or "released" or "gone" or "taken" or "refused")
            || r.Message is null || r.Message.Length > 2048 || r.Message.Any(c => char.IsControl(c) && c is not ('\r' or '\n' or '\t'))
            || r.Revision < 1 || r.CreatedUtc == default || r.UpdatedUtc < r.CreatedUtc
            || (r.CurrentComputer is not null && !Name(r.CurrentComputer))
            || (r.State is "reserved" or "joining" or "consumed" or "released" && r.ComputerGuid is null)
            || (r.ResolvedParents is not null && (r.ResolvedParents.Length > 32 || r.ResolvedParents.Any(p => !IsOpaqueId(p.ReceiptId)
                || !IsHash(p.Sha256) || !r.JoinReceiptIds.Contains(p.ReceiptId, StringComparer.Ordinal))
                || r.ResolvedParents.Select(p => p.ReceiptId).Distinct(StringComparer.Ordinal).Count() != r.ResolvedParents.Length)))
            throw new JsonException("Identité, portée ou état de réservation invalide.");
    }

    /// <summary>expectedStamp=null creates exclusively; every subsequent replacement compares the exact old bytes.</summary>
    public string Save(JoinReservationReceipt receipt, string? expectedStamp = null)
    {
        Validate(receipt);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(receipt, Options);
        if (bytes.Length > MaximumBytes) throw new IOException("Reçu de réservation trop volumineux.");
        RequirePlain(DirectoryPath);
        Directory.CreateDirectory(DirectoryPath);
        RequirePlain(DirectoryPath);
        var path = PathFor(receipt.Id);
        RequirePlain(path);
        var temporary = Path.Combine(DirectoryPath, ".pending-" + Guid.NewGuid().ToString("N"));
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(flushToDisk: true); }
            RequirePlain(path);
            if (expectedStamp is not null && (!IsHash(expectedStamp) || Stamp(receipt.Id) != expectedStamp))
                throw new IOException("Le reçu de réservation a changé : remplacement refusé.");
            File.Move(temporary, path, overwrite: expectedStamp is not null);
            return Digest(bytes);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    public static void RequirePlain(string path)
    {
        var cursor = Path.GetFullPath(path);
        while (!string.IsNullOrEmpty(cursor))
        {
            FileSystemInfo info = Directory.Exists(cursor) ? new DirectoryInfo(cursor) : new FileInfo(cursor);
            if (info.LinkTarget is not null) throw new IOException("Un lien est interdit dans le registre de réservation.");
            if ((File.Exists(cursor) || Directory.Exists(cursor)) && (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Un lien ou point de réanalyse est interdit dans le registre de réservation.");
            var parent = Path.GetDirectoryName(cursor);
            if (parent == cursor) break;
            cursor = parent;
        }
    }
}
