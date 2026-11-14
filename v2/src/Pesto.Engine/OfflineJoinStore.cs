using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Immutable ODJ events and a protected secret. Callers serialize writes with the historical GP mutex.</summary>
public sealed class OfflineJoinStore(string gpRoot, ConfigurationAccessMode mode,
    Action<string>? secureDirectory = null, TimeProvider? clock = null)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private static readonly JsonSerializerOptions JsonOptions = new()
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, RespectRequiredConstructorParameters = true };
    public string RootPath => Path.Combine(LocalRoot(), "V2", "offline-join");

    private string LocalRoot()
    {
        OfflineJoinRules.Guard(mode);
        RequireLocalPath(gpRoot);
        return Path.GetFullPath(gpRoot);
    }

    public string DirectoryFor(string id)
    {
        OfflineJoinRules.Guard(mode);
        if (!OfflineJoinRules.IsHash(id)) throw Invalid();
        return Path.Combine(RootPath, id);
    }
    public string ProtectedPath(string id) => Path.Combine(DirectoryFor(id), "blob.protected");
    public string PlainPath(string id) => Path.Combine(DirectoryFor(id), "blob.odj.tmp");
    public string ReceiptPath(string receiptId)
    {
        OfflineJoinRules.Guard(mode);
        if (!OfflineJoinRules.IsId(receiptId)) throw Invalid();
        return Path.Combine(LocalRoot(), "V2", "receipts", receiptId + ".json");
    }

    public IReadOnlyList<string> Ids()
    {
        var root = RootPath; RequirePlain(root);
        if (File.Exists(root)) throw Invalid();
        if (!Directory.Exists(root)) return [];
        var directories = Directory.EnumerateDirectories(root).Take(501).ToArray();
        if (directories.Length > 500 || directories.Any(path => !OfflineJoinRules.IsHash(Path.GetFileName(path)))) throw Invalid();
        return directories.Select(Path.GetFileName).Select(id => id!).Order(StringComparer.Ordinal).ToArray();
    }

    public OfflineJoinSnapshot Begin(OfflineJoinBinding binding)
    {
        OfflineJoinRules.Guard(mode); OfflineJoinRules.ValidateBinding(binding);
        var directory = DirectoryFor(binding.Id); RequirePlain(directory);
        var legacy = Path.Combine(LocalRoot(), "OfflineJoin", binding.Id);
        RequirePlain(legacy + ".json"); RequirePlain(legacy + ".protected");
        if (Directory.Exists(directory) || File.Exists(directory) || File.Exists(legacy + ".json") || File.Exists(legacy + ".protected"))
            throw OfflineJoinRules.Refused("offlineJoin.duplicate", "Ce blob possède déjà une intention ou un import local, y compris dans V1. Observez son reçu ; aucune réimportation ni répétition.");
        if (Ids().Count >= 500) throw OfflineJoinRules.Refused("offlineJoin.limit", "Le registre conserve déjà 500 imports ODJ ; aucun nouvel import ne rendra cet historique illisible.");
        EnsureDirectory(RootPath); EnsureDirectory(directory);
        return Write(new(1, 1, "", binding, "Importing", clock.GetUtcNow(), null, null, null, false, null, null, null));
    }

    public void WriteProtected(OfflineJoinSnapshot importing, byte[] ciphertext)
    {
        OfflineJoinRules.Guard(mode); RequireCurrent(importing);
        if (importing.Event.State != "Importing" || ciphertext.Length is < 1 or > OfflineJoinRules.MaximumSecretBytes
            || OfflineJoinRules.Hash(ciphertext) != importing.Event.Binding.ProtectedSha256) throw Invalid();
        WriteNew(ProtectedPath(importing.Event.Binding.Id), ciphertext);
    }

    public byte[] ReadProtected(OfflineJoinBinding binding)
    {
        OfflineJoinRules.Guard(mode); OfflineJoinRules.ValidateBinding(binding);
        var bytes = ReadBounded(ProtectedPath(binding.Id), OfflineJoinRules.MaximumSecretBytes);
        if (OfflineJoinRules.Hash(bytes) != binding.ProtectedSha256) throw Invalid();
        return bytes;
    }

    public void WritePlain(OfflineJoinBinding binding, byte[] plaintext)
    {
        OfflineJoinRules.Guard(mode); OfflineJoinRules.ValidateBinding(binding);
        if (plaintext.Length is < 1 or > OfflineJoinRules.MaximumBlobBytes || OfflineJoinRules.Hash(plaintext) != binding.Id) throw Invalid();
        WriteNew(PlainPath(binding.Id), plaintext);
    }

    public OfflineJoinSnapshot Append(OfflineJoinSnapshot expected, string state, string? receiptId = null,
        string? planId = null, int? nativeCode = null, bool workerMayRun = false,
        OfflineJoinObservation? observation = null, string? sourceReceiptSha256 = null, OfflineJoinLocalState? baseline = null)
    {
        OfflineJoinRules.Guard(mode); RequireCurrent(expected);
        return Write(new(1, expected.Event.Sequence + 1, expected.Sha256, expected.Event.Binding, state,
            clock.GetUtcNow(), receiptId ?? expected.Event.ReceiptId, planId ?? expected.Event.PlanId,
            nativeCode ?? expected.Event.NativeCode, workerMayRun, observation ?? expected.Event.Observation,
            sourceReceiptSha256 ?? expected.Event.SourceReceiptSha256, baseline ?? expected.Event.Baseline));
    }

    public OfflineJoinSnapshot? Read(string id)
    {
        OfflineJoinRules.Guard(mode);
        var directory = DirectoryFor(id); RequirePlain(directory);
        if (!Directory.Exists(directory)) return null;
        var events = Path.Combine(directory, "events"); RequirePlain(events);
        if (!Directory.Exists(events)) throw Invalid();
        var files = Directory.EnumerateFiles(events).OrderBy(Path.GetFileName, StringComparer.Ordinal).Take(257).ToArray();
        if (files.Length is 0 or > 256) throw Invalid();
        OfflineJoinSnapshot? previous = null;
        foreach (var path in files)
        {
            if (Path.GetFileName(path) != ((previous?.Event.Sequence ?? 0) + 1).ToString("D4", CultureInfo.InvariantCulture) + ".json") throw Invalid();
            var bytes = ReadBounded(path, 65536); OfflineJoinEvent value;
            try
            {
                using var closed = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 }); RequireUnique(closed.RootElement);
                value = JsonSerializer.Deserialize<OfflineJoinEvent>(bytes, JsonOptions) ?? throw Invalid();
            }
            catch (JsonException) { throw Invalid(); }
            ValidateEvent(value, previous);
            if (value.Binding.Id != id) throw Invalid();
            previous = new(value, OfflineJoinRules.Hash(bytes));
        }
        return previous;
    }

    public bool ContainsEvent(string id, string sha256)
    {
        _ = Read(id) ?? throw Invalid();
        return Directory.EnumerateFiles(Path.Combine(DirectoryFor(id), "events"), "*.json")
            .Any(path => OfflineJoinRules.Hash(ReadBounded(path, 65536)) == sha256);
    }

    public OfflineJoinSnapshot? ReadEvent(string id, string sha256)
    {
        if (!OfflineJoinRules.IsHash(sha256)) throw Invalid();
        _ = Read(id) ?? throw Invalid();
        foreach (var path in Directory.EnumerateFiles(Path.Combine(DirectoryFor(id), "events"), "*.json"))
        {
            var bytes = ReadBounded(path, 65536);
            if (OfflineJoinRules.Hash(bytes) == sha256)
                return new(JsonSerializer.Deserialize<OfflineJoinEvent>(bytes, JsonOptions) ?? throw Invalid(), sha256);
        }
        return null;
    }

    private void RequireCurrent(OfflineJoinSnapshot expected)
    {
        var actual = Read(expected.Event.Binding.Id);
        if (actual is null || actual.Sha256 != expected.Sha256 || actual.Event != expected.Event)
            throw OfflineJoinRules.Refused("offlineJoin.changed", "Le journal ODJ a changé ; aucun remplacement ni nouvel envoi.");
    }

    private OfflineJoinSnapshot Write(OfflineJoinEvent value)
    {
        var previous = value.Sequence == 1 ? null : Read(value.Binding.Id);
        ValidateEvent(value, previous);
        var directory = Path.Combine(DirectoryFor(value.Binding.Id), "events"); EnsureDirectory(directory);
        var path = Path.Combine(directory, value.Sequence.ToString("D4", CultureInfo.InvariantCulture) + ".json");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);
        if (bytes.Length > 65536) throw Invalid();
        WriteNew(path, bytes);
        return new(value, OfflineJoinRules.Hash(bytes));
    }

    private static void ValidateEvent(OfflineJoinEvent value, OfflineJoinSnapshot? previous)
    {
        OfflineJoinRules.ValidateBinding(value.Binding);
        if (value.Schema != 1 || value.Sequence is < 1 or > 256 || value.Utc.Offset != TimeSpan.Zero || value.Utc < value.Binding.ImportedUtc
            || value.Sequence != (previous?.Event.Sequence ?? 0) + 1 || value.PreviousSha256 != (previous?.Sha256 ?? "")
            || value.State is not ("Importing" or "Imported" or "Requested" or "PendingRestart" or "Uncertain" or "Verified")) throw Invalid();
        if (previous is null)
        {
            if (value.State != "Importing") throw Invalid();
        }
        else
        {
            if (value.Binding != previous.Event.Binding || value.Utc < previous.Event.Utc) throw Invalid();
            var allowed = previous.Event.State switch
            {
                "Importing" => value.State == "Imported",
                "Imported" => value.State == "Requested",
                "Requested" => value.State is "Requested" or "PendingRestart" or "Uncertain" or "Verified",
                "PendingRestart" or "Uncertain" => value.State is "Uncertain" or "Verified",
                "Verified" => value.State == "Verified",
                _ => false
            };
            if (!allowed || previous.Event.ReceiptId is not null && value.ReceiptId != previous.Event.ReceiptId
                || previous.Event.PlanId is not null && value.PlanId != previous.Event.PlanId
                || previous.Event.Baseline is not null && value.Baseline != previous.Event.Baseline) throw Invalid();
        }
        if (value.State is "Importing" or "Imported")
        {
            if (value.ReceiptId is not null || value.PlanId is not null || value.NativeCode is not null || value.WorkerMayRun
                || value.Observation is not null || value.SourceReceiptSha256 is not null || value.Baseline is not null) throw Invalid();
        }
        else if (!OfflineJoinRules.IsId(value.ReceiptId) || !OfflineJoinRules.IsId(value.PlanId)
            || value.SourceReceiptSha256 is not null && !OfflineJoinRules.IsHash(value.SourceReceiptSha256) || value.Baseline is null) throw Invalid();
        if (value.Baseline is not null) OfflineJoinRules.RequireLocal(value.Baseline, value.Utc, value.Binding);
        if (value.State == "PendingRestart" && (value.NativeCode != 0 || value.WorkerMayRun)) throw Invalid();
        if (value.State == "Verified" && (value.WorkerMayRun || value.Observation is null
            || OfflineJoinRules.ObservationRefusal(value.Binding, value.Observation, value.Utc, value.Baseline?.BootUtc) is not null)) throw Invalid();
    }

    private void EnsureDirectory(string path)
    {
        RequirePlain(path); Directory.CreateDirectory(path); RequirePlain(path); secureDirectory?.Invoke(path);
    }

    public static void WriteNew(string path, byte[] bytes)
    {
        RequirePlain(path);
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        stream.Write(bytes); stream.Flush(true);
    }

    public static byte[] ReadBounded(string path, int maximum)
    {
        RequirePlain(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is < 1 || stream.Length > maximum) throw Invalid();
        var bytes = new byte[checked((int)stream.Length)]; stream.ReadExactly(bytes); return bytes;
    }

    public static void RequireLocalPath(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) || path.StartsWith("//", StringComparison.Ordinal)
            || path.Any(char.IsControl)) throw OfflineJoinRules.Refused("offlineJoin.path", "ODJ exige un fichier ou stockage local absolu, sans partage ni chemin spécial.");
        if (OperatingSystem.IsWindows() && (path.StartsWith(@"\\?\", StringComparison.Ordinal) || path.StartsWith(@"\\.\", StringComparison.Ordinal)
            || new DriveInfo(Path.GetPathRoot(path)!).DriveType == DriveType.Network))
            throw OfflineJoinRules.Refused("offlineJoin.path", "Un lecteur réseau n’est pas un stockage hors connexion.");
    }

    public static void RequirePlain(string path)
    {
        RequireLocalPath(path);
        var full = Path.GetFullPath(path); var root = Path.GetPathRoot(full)!; var current = root;
        // Check each ancestor before probing its descendants: a junction to a share must not cause even a
        // preliminary File.Exists on the remote target during this local-only workflow.
        foreach (var part in full[root.Length..].Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { break; }
            catch (DirectoryNotFoundException) { break; }
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw OfflineJoinRules.Refused("offlineJoin.path", "Un lien ou une jonction ne peut pas être traversé par le parcours ODJ local.");
        }
    }

    internal static void RequireUnique(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var item in value.EnumerateObject()) { if (!names.Add(item.Name)) throw Invalid(); RequireUnique(item.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) RequireUnique(item);
    }

    /// <summary>Native mutation admission also consults intents whose mirror receipt was interrupted.</summary>
    public static string? RefusalForMutation(string gpRoot, string computer, bool localTarget = false)
    {
        try
        {
            var store = new OfflineJoinStore(gpRoot, ConfigurationAccessMode.Live);
            foreach (var id in store.Ids())
            {
                var item = store.Read(id) ?? throw Invalid();
                if ((localTarget || OfflineJoinRules.Same(item.Event.Binding.Computer, computer))
                    && item.Event.State is "Requested" or "PendingRestart" or "Uncertain")
                    return "Une jonction hors connexion de ce poste reste demandée ou non vérifiée. Ouvrez Pesto --offline-join et observez son reçu ; aucune autre jonction ni répétition.";
            }
            var legacy = Path.Combine(store.LocalRoot(), "OfflineJoin"); RequirePlain(legacy);
            if (File.Exists(legacy)) throw Invalid();
            if (!Directory.Exists(legacy)) return null;
            var paths = Directory.EnumerateFiles(legacy, "*.json").Take(501).ToArray();
            if (paths.Length > 500) throw Invalid();
            foreach (var path in paths)
            {
                using var document = JsonDocument.Parse(ReadBounded(path, 131072)); var value = document.RootElement; RequireUnique(value);
                var (name, state) = ReadLegacyBarrier(path, value);
                if ((localTarget || OfflineJoinRules.Same(name, computer)) && state is not ("Imported" or "Verified"))
                    return "Un reçu ODJ V1 de ce poste reste demandé ou incertain. Son journal historique est conservé ; la fenêtre V2 ne le migre pas et ne rejoue jamais son blob.";
            }
            return null;
        }
        catch (Exception) { return "Le registre ODJ local est illisible ou incomplet ; aucune nouvelle mutation ne traverse cette incertitude."; }
    }

    private static (string Computer, string State) ReadLegacyBarrier(string path, JsonElement value)
    {
        static string? Text(JsonElement item, string key) => item.TryGetProperty(key, out var field) && field.ValueKind == JsonValueKind.String ? field.GetString() : null;
        static bool Closed(JsonElement item, string[] fields, string[] required) => item.ValueKind == JsonValueKind.Object
            && item.EnumerateObject().All(p => fields.Contains(p.Name, StringComparer.Ordinal)) && required.All(name => item.TryGetProperty(name, out _));
        string[] fields = ["Schema", "Mode", "Id", "State", "Plan", "BootUtc", "OperationId", "NativeCode", "Utc"];
        if (!Closed(value, fields, fields) || !value.GetProperty("Schema").TryGetInt32(out var schema) || schema != 1
            || Text(value, "Mode") != "OfflineJoin" || !OfflineJoinRules.IsHash(Text(value, "Id"))
            || Path.GetFileName(path) != Text(value, "Id") + ".json" || Text(value, "State") is not ("Imported" or "Requested" or "PendingRestart" or "Uncertain" or "Verified")) throw Invalid();
        var plan = value.GetProperty("Plan");
        string[] planFields = ["Schema", "Purpose", "Action", "CreatedUtc", "ExpiresUtc", "MachineId", "ConfigStamp", "Domain", "Computer", "NewName", "SourceOU", "TargetOU", "ObjectGuid", "TargetOUGuid", "Type", "SiteCode", "ServiceCode", "Metadata", "BlobSHA256", "Integrity"];
        string[] required = ["Schema", "Purpose", "Action", "CreatedUtc", "ExpiresUtc", "MachineId", "ConfigStamp", "Domain", "Computer", "NewName", "TargetOU", "ObjectGuid", "BlobSHA256", "Integrity"];
        var computer = Text(plan, "Computer"); var state = Text(value, "State")!;
        if (!Closed(plan, planFields, required) || !plan.GetProperty("Schema").TryGetInt32(out var planSchema) || planSchema != 1
            || Text(plan, "Purpose") != "PestoPreparedPlan" || Text(plan, "Action") != "OfflineJoin"
            || !EntraPreparationRules.Name(computer) || Text(plan, "NewName") != computer
            || !OfflineJoinRules.IsGuid(Text(plan, "MachineId")) || !OfflineJoinRules.IsGuid(Text(plan, "ObjectGuid"))
            || !OfflineJoinRules.IsHash(Text(plan, "ConfigStamp")) || !OfflineJoinRules.IsHash(Text(plan, "Integrity"))
            || !SharedCoordinationProtocol.IsDomainName(Text(plan, "Domain")) || Text(plan, "TargetOU") is not { Length: > 0 and <= 2048 } ou
            || !V1Config.IsOuPath(ou) || Text(plan, "BlobSHA256") != Text(value, "Id")
            || !DateTimeOffset.TryParse(Text(plan, "CreatedUtc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var created)
            || !DateTimeOffset.TryParse(Text(plan, "ExpiresUtc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var expires) || expires <= created
            || !DateTimeOffset.TryParse(Text(value, "BootUtc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var boot)
            || !DateTimeOffset.TryParse(Text(value, "Utc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var utc) || utc < boot
            || value.GetProperty("NativeCode").ValueKind is not (JsonValueKind.Null or JsonValueKind.Number)) throw Invalid();
        if (state == "Imported" ? Text(value, "OperationId") != "" : !Guid.TryParse(Text(value, "OperationId"), out var operation) || operation == Guid.Empty) throw Invalid();
        return (computer!, state);
    }

    private static PestoException Invalid() => OfflineJoinRules.Refused("offlineJoin.evidence", "Journal ODJ illisible, lié, concurrent ou incomplet ; aucune preuve remplacée et aucun rejeu.");
}
