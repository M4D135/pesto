using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record EntraLeaveCommand(string ReceiptId, string PlanId, string Nonce,
    EntraPreparationRequest Request, string MachineId, DateTimeOffset CreatedUtc);

public sealed record EntraLeaveEvent(int Schema, int Sequence, string PreviousSha256, EntraLeaveCommand Command,
    string Phase, string Effect, bool MayStillRun, DateTimeOffset Utc, string? TaskName = null,
    string? TaskDefinitionSha256 = null, long? NativeCode = null);

public sealed record EntraLeaveSnapshot(EntraLeaveEvent Event, string Sha256);
public sealed record EntraLeaveNativeResult(string Effect, bool MayStillRun, string Message, long? NativeCode = null);

/// <summary>A transport receives a fixed, bound request. It must durably record dispatch before any native send.</summary>
public interface IEntraLeaveTransport
{
    EntraLeaveNativeResult Leave(EntraLeaveCommand command, Action<string, string?, string?, long?> record);
}

/// <summary>Append-only hash-linked evidence. Existing bytes, including a concurrent event, are never replaced.</summary>
public sealed class EntraLeaveEvidence(string gpRoot, ConfigurationAccessMode mode, TimeProvider? clock = null)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private static readonly JsonSerializerOptions JsonOptions = new()
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, RespectRequiredConstructorParameters = true };
    private static readonly HashSet<string> Phases = ["Requested", "DispatchRequested", "TaskRegistering", "TaskRegistered", "TaskStartRequested", "TaskStarted", "TaskFinished", "TaskDeleted", "TaskDeleteFailed", "Completed", "Inspected"];
    private static readonly HashSet<string> Effects = ["Requested", "NotRequested", "Skipped", "Confirmed", "Uncertain"];

    public EntraLeaveSnapshot Begin(EntraLeaveCommand command)
    {
        Guard(); Validate(command);
        if (Read(command.ReceiptId) is not null) throw new PestoException("entra.replay", "Préparation Entra déjà engagée sous ce reçu ; aucun second retrait.");
        return Write(new(1, 1, "", command, "Requested", "Requested", false, clock.GetUtcNow()));
    }

    public EntraLeaveSnapshot Append(EntraLeaveSnapshot expected, string phase, string effect, bool mayStillRun,
        string? taskName = null, string? definitionSha256 = null, long? nativeCode = null)
    {
        Guard();
        var current = Read(expected.Event.Command.ReceiptId);
        if (current is null || current.Sha256 != expected.Sha256 || current.Event.Sequence != expected.Event.Sequence)
            throw new PestoException("entra.changed", "La preuve Entra a changé ; aucun remplacement ni nouvel envoi.");
        if (current.Event.Effect == "Confirmed" && effect != "Confirmed")
            throw new PestoException("entra.effect", "Un retrait confirmé reste consigné comme un effet réel.");
        return Write(new(1, current.Event.Sequence + 1, current.Sha256, current.Event.Command,
            phase, effect, mayStillRun, clock.GetUtcNow(), taskName ?? current.Event.TaskName,
            definitionSha256 ?? current.Event.TaskDefinitionSha256, nativeCode ?? current.Event.NativeCode));
    }

    public EntraLeaveSnapshot? Read(string receiptId)
    {
        Guard();
        var directory = DirectoryFor(receiptId); RequireNoLinks(directory);
        if (!Directory.Exists(directory)) return null;
        var files = Directory.EnumerateFiles(directory).OrderBy(Path.GetFileName, StringComparer.Ordinal).Take(65).ToArray();
        if (files.Length > 64) throw Invalid();
        EntraLeaveSnapshot? previous = null;
        foreach (var path in files)
        {
            RequireNoLinks(path);
            if (Path.GetFileName(path) != ((previous?.Event.Sequence ?? 0) + 1).ToString("D4", System.Globalization.CultureInfo.InvariantCulture) + ".json") throw Invalid();
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096);
            if (input.Length is 0 or > 65536) throw Invalid();
            var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
            EntraLeaveEvent value;
            try
            {
                using var closed = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 });
                RequireUniqueProperties(closed.RootElement);
                value = JsonSerializer.Deserialize<EntraLeaveEvent>(bytes, JsonOptions) ?? throw Invalid();
            }
            catch (JsonException) { throw Invalid(); }
            ValidateEvent(value);
            if (value.Command.ReceiptId != receiptId || value.Sequence != (previous?.Event.Sequence ?? 0) + 1
                || value.PreviousSha256 != (previous?.Sha256 ?? "")
                || previous is not null && (value.Command != previous.Event.Command || value.Utc < previous.Event.Utc
                    || previous.Event.Effect == "Confirmed" && value.Effect != "Confirmed")) throw Invalid();
            previous = new(value, Digest(bytes));
        }
        return previous;
    }

    public EntraBarrierEvidence ReadBarrier(string receiptId)
    {
        try
        {
            var snapshot = Read(receiptId);
            if (snapshot is null) return new(true, null, Digest(Encoding.UTF8.GetBytes("absent:" + receiptId)));
            return new(!snapshot.Event.MayStillRun && snapshot.Event.Phase is "Completed" or "Inspected",
                snapshot.Event.MayStillRun || snapshot.Event.Phase is not ("Completed" or "Inspected")
                    ? "Un retrait Entra peut encore agir ou sa fin n’est pas prouvée ; inspectez sa preuve avant d’acquitter." : null,
                snapshot.Sha256);
        }
        catch (Exception) { return new(false, "Preuve Entra absente, concurrente ou illisible : aucun acquittement.", "invalid"); }
    }

    public bool ContainsPhase(string receiptId, string phase)
    {
        var snapshot = Read(receiptId); // Validate the whole chain before consulting any event.
        if (snapshot is null) return false;
        return Directory.EnumerateFiles(DirectoryFor(receiptId), "*.json").Any(path =>
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(path));
            return document.RootElement.GetProperty("Phase").GetString() == phase;
        });
    }

    private EntraLeaveSnapshot Write(EntraLeaveEvent value)
    {
        ValidateEvent(value);
        var directory = DirectoryFor(value.Command.ReceiptId); RequireNoLinks(directory);
        Directory.CreateDirectory(directory); RequireNoLinks(directory);
        var path = Path.Combine(directory, value.Sequence.ToString("D4", System.Globalization.CultureInfo.InvariantCulture) + ".json");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions);
        // No temporary replacing pointer: a torn final event is itself a blocking, inspectable proof.
        using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { output.Write(bytes); output.Flush(true); }
        return new(value, Digest(bytes));
    }

    private string DirectoryFor(string receiptId)
    {
        if (!Regex.IsMatch(receiptId, "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")) throw Invalid();
        return Path.Combine(Path.GetFullPath(gpRoot), "V2", "entra", receiptId, "events");
    }

    private void Guard()
    {
        if (mode != ConfigurationAccessMode.Live) throw new PestoException("entra.isolated", "Démo, santé et reprise binaire n’accèdent à aucune preuve Entra réelle.");
    }

    public static void Validate(EntraLeaveCommand command)
    {
        EntraPreparationRules.ValidateRequest(command.Request);
        if (!Regex.IsMatch(command.ReceiptId, "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
            || !Regex.IsMatch(command.PlanId, "^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$")
            || !Regex.IsMatch(command.Nonce, "^[a-f0-9]{64}$")
            || !Guid.TryParse(command.MachineId, out var machine) || machine == Guid.Empty) throw Invalid();
    }

    private static void ValidateEvent(EntraLeaveEvent value)
    {
        Validate(value.Command);
        if (value.Schema != 1 || value.Sequence is < 1 or > 64 || !Phases.Contains(value.Phase) || !Effects.Contains(value.Effect)
            || value.Sequence > 1 && !Regex.IsMatch(value.PreviousSha256, "^[a-f0-9]{64}$")
            || value.Sequence == 1 && (value.PreviousSha256 != "" || value.Phase != "Requested" || value.Effect != "Requested")
            || value.TaskName is not null && !Regex.IsMatch(value.TaskName, @"^\\Pesto_EntraLeave_[a-f0-9]{24}$")
            || value.TaskDefinitionSha256 is not null && !Regex.IsMatch(value.TaskDefinitionSha256, "^[a-fA-F0-9]{64}$")) throw Invalid();
    }

    public static string Digest(byte[] value) => Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();
    private static void RequireUniqueProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            {
                if (!seen.Add(property.Name)) throw Invalid();
                RequireUniqueProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RequireUniqueProperties(item);
    }
    public static void RequireNoLinks(string path)
    {
        for (string? current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw Invalid();
    }
    private static PestoException Invalid() => new("entra.evidence", "Preuve Entra fermée, cohérente et sans lien requise.");
}

/// <summary>Durable intent precedes dispatch. A lost response is never retried and cannot authorize a rename.</summary>
public sealed class EntraLeaveTransaction(EntraLeaveEvidence evidence)
{
    public EntraLeaveNativeResult Execute(EntraLeaveCommand command, IEntraLeaveTransport transport)
    {
        var snapshot = evidence.Begin(command); // Must succeed before the transport is even called.
        try
        {
            var result = transport.Leave(command, (phase, task, hash, code) =>
                snapshot = evidence.Append(snapshot, phase, "Requested", true, task, hash, code));
            if (result.Effect is not ("NotRequested" or "Confirmed" or "Uncertain")
                || result.Effect == "Confirmed" && result.NativeCode != 42)
                result = new("Uncertain", true, "Résultat Entra non probant : aucun renommage.", result.NativeCode);
            snapshot = evidence.Append(snapshot, "Completed", result.Effect, result.MayStillRun, nativeCode: result.NativeCode);
            return result;
        }
        catch (Exception)
        {
            try { _ = evidence.Append(snapshot, "Completed", "Uncertain", true); } catch (Exception) { }
            return new("Uncertain", true, "Retrait Entra engagé ou preuve interrompue : résultat incertain, aucun renommage ni second retrait automatique.", 97);
        }
    }
}
