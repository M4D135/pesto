using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Native ODJ only. Construction does not discover a domain, open configuration, create folders or authenticate.</summary>
public sealed partial class WindowsOfflineJoinPlatform(string configurationPath, string gpRoot,
    ConfigurationAccessMode mode = ConfigurationAccessMode.Live) : IOfflineJoinPlatform, IReceiptAuditDisclosure
{
    private bool disposed;
    private readonly ReceiptAuditTrail audit = new(new WindowsReceiptAuditSink());
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        RespectRequiredConstructorParameters = true
    };
    public ReceiptAuditStatus AuditStatus => audit.Status;
    private OfflineJoinStore Store => new(gpRoot, mode);
    private void Guard() { OfflineJoinRules.Guard(mode); ObjectDisposedException.ThrowIf(disposed, this); }
    private void GuardWindows() { Guard(); if (!OperatingSystem.IsWindows()) throw OfflineJoinRules.Refused("offlineJoin.platform", "Le service ODJ natif exige Windows ; aucune opération simulée."); }
    public void Dispose() => disposed = true;

    public string? UnavailableReason
    {
        get
        {
            Guard();
            if (!OperatingSystem.IsWindows()) return "La jonction hors connexion exige Windows et Windows PowerShell 5.1.";
            if (WindowsPowerShellProbe.UnavailableReason is { } reason) return reason;
            var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "djoin.exe");
            try { OfflineJoinStore.RequirePlain(path); return File.Exists(path) ? null : "Le composant Windows djoin.exe est absent."; }
            catch (Exception) { return "Le composant Windows djoin.exe ne peut pas être vérifié localement."; }
        }
    }

    public MutationManagedPolicy ReadManagedPolicy() { GuardWindows(); return WindowsManagedPolicyReader.Read(); }

    public OfflineJoinLocalState ReadLocal()
    {
        GuardWindows();
        try
        {
            var output = Run(WindowsOfflineJoinScripts.ReadLocal, "", 30000);
            if (!output.Completed || output.ExitCode != 0) return OfflineJoinLocalState.Unknown("Lecture Windows locale interrompue.");
            using var document = Parse(output.Json);
            return JsonSerializer.Deserialize<OfflineJoinLocalState>(document.RootElement, JsonOptions)
                ?? OfflineJoinLocalState.Unknown("Preuve locale absente.");
        }
        catch (Exception) { return OfflineJoinLocalState.Unknown("Identité Windows locale incomplète ; aucun état hors domaine supposé."); }
    }

    public OfflineJoinNativeResult Apply(OfflineJoinCommand command)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        using var gp = new NativeGpLease();
        var mayRun = false;
        try
        {
            var now = DateTimeOffset.UtcNow; var b = command.Binding; OfflineJoinRules.ValidateBinding(b);
            if (!OfflineJoinRules.IsId(command.ReceiptId) || !command.ReceiptId.StartsWith("receipt-", StringComparison.Ordinal)
                || !OfflineJoinRules.IsId(command.PlanId) || !OfflineJoinRules.IsHash(command.IntentSha256)
                || command.RequestedUtc < now.AddMinutes(-5) || command.RequestedUtc > now.AddSeconds(5)
                || command.PlanExpiresUtc <= now || command.PlanExpiresUtc > command.RequestedUtc.AddMinutes(5)
                || command.PlanExpiresUtc > b.ExpiresUtc) throw Invalid();
            using var configPin = PinConfiguration(out var configuration);
            var policy = ReadManagedPolicy(); OfflineJoinRules.RequireConfiguration(configuration, policy, b);
            var head = Store.Read(b.Id) ?? throw Invalid();
            if (head.Sha256 != command.IntentSha256 || head.Event.Binding != b || head.Event.State != "Requested"
                || !head.Event.WorkerMayRun || head.Event.ReceiptId != command.ReceiptId || head.Event.PlanId != command.PlanId
                || head.Event.Baseline != command.Baseline || head.Event.Utc != command.RequestedUtc) throw Invalid();
            var receiptPath = Store.ReceiptPath(command.ReceiptId);
            var receiptBytes = OfflineJoinStore.ReadBounded(receiptPath, 65536);
            if (OfflineJoinRules.Hash(receiptBytes) != head.Event.SourceReceiptSha256) throw Invalid();
            using var receipt = Parse(Encoding.UTF8.GetString(receiptBytes));
            var eventHash = Text(receipt.RootElement, "OfflineJoinSha256") ?? throw Invalid();
            var linked = Store.ReadEvent(b.Id, eventHash) ?? throw Invalid();
            if (!OfflineJoinReceipt.Matches(linked, receipt.RootElement) || linked.Event.State != "Requested"
                || linked.Event.ReceiptId != command.ReceiptId || linked.Event.Baseline != command.Baseline) throw Invalid();
            var local = ReadLocal(); OfflineJoinRules.RequireLocal(local, now, b);
            if (local != command.Baseline) throw Invalid();
            var directory = Store.DirectoryFor(b.Id);
            var attemptPath = Path.Combine(directory, "native-requested.json"); var resultPath = Path.Combine(directory, "native-result.json");
            OfflineJoinStore.RequirePlain(attemptPath); OfflineJoinStore.RequirePlain(resultPath);
            if (File.Exists(attemptPath) || File.Exists(resultPath)) throw Invalid();
            var plainPath = Store.PlainPath(b.Id);
            using var plainPin = new FileStream(plainPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (plainPin.Length is < 1 or > OfflineJoinRules.MaximumBlobBytes
                || !OfflineJoinRules.Same(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(plainPin)), b.Id)) throw Invalid();
            OfflineJoinRules.RequireConfiguration(OfflineJoinStore.ReadBounded(configurationPath, ConfigurationDocument.MaximumBytes), ReadManagedPolicy(), b);
            MutationSessionGuard.RequireWritableSession();
            var payload = JsonSerializer.Serialize(new
            {
                Command = command, ConfigurationPath = configurationPath, ManagedPolicy = policy,
                IntentPath = Path.Combine(directory, "events", head.Event.Sequence.ToString("D4", CultureInfo.InvariantCulture) + ".json"),
                ReceiptPath = receiptPath, PlainPath = plainPath, AttemptPath = attemptPath, ResultPath = resultPath
            });
            mayRun = true;
            var output = Run(WindowsOfflineJoinScripts.Apply, payload, 150000);
            if (!output.Completed || output.ExitCode != 0) return new(true, null, true, "Worker ODJ interrompu ; aucune répétition.");
            if (!File.Exists(attemptPath)) return new(false, null, false, "Le worker a refusé avant son marqueur natif ; le blob reste consommé.");
            using var attempt = Parse(Encoding.UTF8.GetString(OfflineJoinStore.ReadBounded(attemptPath, 16384)));
            RequireNativeIdentity(attempt.RootElement, command, result: false);
            using var result = Parse(Encoding.UTF8.GetString(OfflineJoinStore.ReadBounded(resultPath, 16384)));
            RequireNativeIdentity(result.RootElement, command, result: true);
            var r = result.RootElement;
            var started = r.GetProperty("Started").GetBoolean(); var worker = r.GetProperty("WorkerMayRun").GetBoolean();
            var nativeCode = r.GetProperty("NativeCode").ValueKind == JsonValueKind.Null ? (int?)null : r.GetProperty("NativeCode").GetInt32();
            if (!started && nativeCode is not null || worker && nativeCode is not null) throw Invalid();
            return new(started, nativeCode, worker, started && nativeCode == 0 && !worker
                ? "Demande native acceptée ; nouveau démarrage et observation requis." : "Résultat natif non vérifié ; aucune répétition.");
        }
        catch (Exception) { return new(mayRun, null, mayRun, "Admission ou preuve native ODJ non confirmée ; aucune seconde application."); }
    }

    public OfflineJoinObservation Observe(OfflineJoinBinding binding)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession();
        var local = ReadLocal();
        try
        {
            var head = Store.Read(binding.Id) ?? throw Invalid();
            if (head.Event.Binding != binding || head.Event.State is "Importing" or "Imported" || head.Event.Baseline?.BootUtc is not { } appliedBoot) throw Invalid();
            if (OfflineJoinRules.LocalObservationRefusal(binding, local, DateTimeOffset.UtcNow, appliedBoot) is { } reason)
                return Unknown(local, reason);
            using var configurationPin = PinConfiguration(out var configuration);
            OfflineJoinRules.RequireObservationConfiguration(configuration, ReadManagedPolicy(), binding);
            var module = TrustedActiveDirectoryModule.Resolve(Path.GetDirectoryName(configurationPath));
            if (module is null) return Unknown(local, "Le module AD vérifié est indisponible ; aucune conclusion de réussite.");
            var output = Run(WindowsOfflineJoinScripts.Observe, JsonSerializer.Serialize(new
            { Binding = binding, AppliedBootUtc = appliedBoot, ModulePath = module }), 60000);
            if (!output.Completed || output.ExitCode != 0) return Unknown(local, "Observation Windows/AD interrompue ; aucune réparation ni répétition.");
            using var document = Parse(output.Json);
            return JsonSerializer.Deserialize<OfflineJoinObservation>(document.RootElement, JsonOptions) ?? Unknown(local, "Observation absente.");
        }
        catch (Exception) { return Unknown(local, "La preuve du domaine, du compte AD ou du canal sécurisé est incomplète ; aucune jonction rejouée."); }
    }

    public void Audit(bool enabled, string durableReceiptJson)
    {
        GuardWindows(); MutationSessionGuard.RequireWritableSession(); audit.AfterDurableReceipt(enabled, durableReceiptJson);
    }

    private FileStream PinConfiguration(out byte[] bytes)
    {
        OfflineJoinStore.RequirePlain(configurationPath);
        var stream = new FileStream(configurationPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        try { if (stream.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw Invalid();
            bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes); return stream; }
        catch { stream.Dispose(); throw; }
    }

    private static void RequireNativeIdentity(JsonElement value, OfflineJoinCommand command, bool result)
    {
        string[] fields = result ? ["Schema", "Id", "ReceiptId", "IntentSha256", "Started", "NativeCode", "WorkerMayRun", "Utc"]
            : ["Schema", "Id", "ReceiptId", "IntentSha256", "ConfigurationSha256", "MachineId", "Utc"];
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != fields.Length
            || fields.Any(name => !value.TryGetProperty(name, out _)) || value.GetProperty("Schema").GetInt32() != 1
            || Text(value, "Id") != command.Binding.Id || Text(value, "ReceiptId") != command.ReceiptId || Text(value, "IntentSha256") != command.IntentSha256
            || !DateTimeOffset.TryParse(Text(value, "Utc"), CultureInfo.InvariantCulture, DateTimeStyles.None, out var utc)
            || utc.Offset != TimeSpan.Zero || utc < command.RequestedUtc || utc > DateTimeOffset.UtcNow.AddSeconds(5)) throw Invalid();
        if (!result && (Text(value, "ConfigurationSha256") != command.Binding.ConfigurationSha256 || !OfflineJoinRules.Same(Text(value, "MachineId"), command.Binding.MachineId))) throw Invalid();
        if (result && (value.GetProperty("Started").ValueKind is not (JsonValueKind.True or JsonValueKind.False)
            || value.GetProperty("WorkerMayRun").ValueKind is not (JsonValueKind.True or JsonValueKind.False)
            || value.GetProperty("NativeCode").ValueKind is not (JsonValueKind.Null or JsonValueKind.Number))) throw Invalid();
    }
    private static string? Text(JsonElement value, string name) => value.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String ? field.GetString() : null;
    private static OfflineJoinObservation Unknown(OfflineJoinLocalState local, string reason) => new(local, null, null, null, null, null, null, DateTimeOffset.UtcNow, reason);
    private static PestoException Invalid() => OfflineJoinRules.Refused("offlineJoin.native_evidence", "Preuve ou secret natif ODJ non confirmé ; aucune répétition ni fichier étranger remplacé.");

    private static JsonDocument Parse(string text)
    {
        if (text.Length is < 1 or > 65536) throw Invalid();
        var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 16 });
        try { Unique(document.RootElement); return document; } catch { document.Dispose(); throw; }
    }
    private static void Unique(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var item in value.EnumerateObject()) { if (!names.Add(item.Name)) throw Invalid(); Unique(item.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) Unique(item);
    }
    private sealed record WorkerOutput(bool Completed, int? ExitCode, string Json);
    private static WorkerOutput Run(string script, string payload, int timeout)
    {
        using var process = Process.Start(PowerShellFixedWorker.StartInfo(script));
        if (process is null) return new(false, null, "");
        using var job = OwnedMutationJob.Attach(process); // Worker is blocked in the hash-bound bootstrap until the JobObject owns it.
        var output = ReadBounded(process.StandardOutput, 65536); var errors = Drain(process.StandardError);
        PowerShellFixedWorker.Send(process, script, payload);
        if (!process.WaitForExit(timeout)) return new(false, null, "");
        var json = output.GetAwaiter().GetResult(); errors.GetAwaiter().GetResult();
        return new(true, process.ExitCode, json);
    }
    private static async Task<string> ReadBounded(StreamReader reader, int maximum)
    {
        var output = new StringBuilder(); var buffer = new char[1024]; int count;
        while ((count = await reader.ReadAsync(buffer).ConfigureAwait(false)) != 0)
        {
            if (output.Length + count > maximum) throw Invalid();
            output.Append(buffer, 0, count);
        }
        return output.ToString();
    }
    private static async Task Drain(StreamReader reader)
    {
        var buffer = new char[1024];
        try { while (await reader.ReadAsync(buffer).ConfigureAwait(false) != 0) { } }
        finally { Array.Clear(buffer); }
    }
    private sealed class NativeGpLease : IDisposable
    {
        private readonly Mutex mutex = new(false, OfflineJoinRules.MutexName);
        public NativeGpLease()
        {
            bool acquired; try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) { mutex.Dispose(); throw OfflineJoinRules.Refused("offlineJoin.busy", "Une mutation GP est déjà active ; aucun envoi natif concurrent."); }
        }
        public void Dispose() { try { mutex.ReleaseMutex(); } finally { mutex.Dispose(); } }
    }
}
