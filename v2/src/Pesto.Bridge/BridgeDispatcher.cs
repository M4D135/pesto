using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Bridge;

/// <summary>Closed local message channel. No arbitrary script, command or host object is callable; paths are accepted only by the explicit update-source schema.</summary>
public sealed partial class BridgeDispatcher(IPestoBackend backend)
{
    public const int MaxMessageLength = 1_048_576;
    private readonly ConcurrentDictionary<string, byte> pending = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim admission = new(8, 8);
    private readonly SemaphoreSlim mutations = new(1, 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        MaxDepth = 24
    };

    public async Task<string> DispatchAsync(string message, CancellationToken cancellationToken = default)
    {
        string? id = null;
        string? operation = null;
        bool registered = false;
        bool admitted = false;
        bool mutating = false;
        try
        {
            if (string.IsNullOrEmpty(message) || message.Length > MaxMessageLength)
                return Failure(null, null, "message.size", "Message trop volumineux ou vide.");
            using var document = JsonDocument.Parse(message, new JsonDocumentOptions { MaxDepth = 24 });
            var envelope = Fields(document.RootElement, ["id", "op", "args"]);
            id = Text(envelope, "id", 64);
            if (!RequestId().IsMatch(id)) return Failure(null, null, "message.id", "Identifiant de requête invalide.");
            operation = Text(envelope, "op", 64);
            if (!Schemas.TryGetValue(operation, out var schema))
                return Failure(id, null, "operation.unknown", "Cette opération n’est pas disponible.");
            if (!envelope.TryGetValue("args", out var args)) args = JsonSerializer.SerializeToElement(new { });
            Validate(args, schema);
            if (!pending.TryAdd(id, 0))
                return Failure(id, operation, "request.duplicate", "Cette requête est déjà en cours.");
            registered = true;
            if (pending.Count > 32)
                return Failure(id, operation, "operation.busy", "Trop de demandes en cours. Attendez leur résultat.");
            await admission.WaitAsync(cancellationToken).ConfigureAwait(false);
            admitted = true;
            if (schema.Mutation)
            {
                // Reject a second mutation instead of queuing an unintended later action.
                mutating = await mutations.WaitAsync(0, cancellationToken).ConfigureAwait(false);
                if (!mutating) return Failure(id, operation, "operation.busy", "Une modification est déjà en cours.");
            }
            using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            if (!schema.Mutation) lifetime.CancelAfter(TimeSpan.FromSeconds(60));
            var data = await Task.Run(() => backend.InvokeAsync(operation, args.Clone(), lifetime.Token), lifetime.Token).ConfigureAwait(false);
            return JsonSerializer.Serialize(new { id, kind = "result", op = operation, data }, JsonOptions);
        }
        catch (JsonException) { return Failure(id, operation, "message.json", "Message JSON illisible."); }
        catch (ArgumentException) { return Failure(id, operation, "arguments.invalid", "Les informations de cette demande sont invalides."); }
        catch (PestoException error) { return Failure(id, operation, error.Code, error.Message); }
        catch (OperationCanceledException)
        {
            return Failure(id, operation, "operation.cancelled", "La demande a été interrompue. Consultez son reçu avant de relancer une modification.");
        }
        catch (Exception)
        {
            // Never echo an exception which might contain credentials, LDAP input or private file content.
            return Failure(id, operation, "operation.failed", "L’opération a échoué. Aucun succès n’est confirmé.");
        }
        finally
        {
            if (mutating) mutations.Release();
            if (admitted) admission.Release();
            if (registered && id is not null) pending.TryRemove(id, out _);
        }
    }

    private static string Failure(string? id, string? operation, string code, string message) =>
        JsonSerializer.Serialize(new { id, kind = "error", op = operation, error = new { code, message } }, JsonOptions);

    private static Dictionary<string, JsonElement> Fields(JsonElement value, IEnumerable<string> allowed)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new ArgumentException("Object required.");
        var accepted = new HashSet<string>(allowed, StringComparer.Ordinal);
        var result = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
        foreach (var property in value.EnumerateObject())
            if (!accepted.Contains(property.Name) || !result.TryAdd(property.Name, property.Value))
                throw new ArgumentException("Unknown or duplicate property.");
        return result;
    }

    private static string Text(Dictionary<string, JsonElement> fields, string name, int max)
    {
        if (!fields.TryGetValue(name, out var value) || value.ValueKind != JsonValueKind.String)
            throw new ArgumentException("Text required.");
        var text = value.GetString()!;
        if (text.Length > max || text.Any(char.IsControl)) throw new ArgumentException("Invalid text.");
        return text;
    }

    private static void Validate(JsonElement args, Schema schema)
    {
        var fields = Fields(args, schema.Fields.Keys);
        foreach (var name in schema.Required)
            if (!fields.ContainsKey(name)) throw new ArgumentException("Required field missing.");
        foreach (var (name, value) in fields)
        {
            switch (schema.Fields[name])
            {
                case 's': _ = Text(fields, name, 2048); break;
                case 'm':
                    if (Text(fields, name, 500).Trim().Length < 3) throw new ArgumentException("Reason required.");
                    break;
                case 'b':
                    if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException("Boolean required.");
                    break;
                case 'i':
                    if (!value.TryGetInt32(out var limit) || limit is < 1 or > 200) throw new ArgumentException("Bounded integer required.");
                    break;
                case 'a':
                    if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > 200) throw new ArgumentException("Bounded site array required.");
                    foreach (var site in value.EnumerateArray())
                    {
                        var item = Fields(site, ["id", "name", "code", "ou"]);
                        foreach (var key in new[] { "id", "name", "code", "ou" }) _ = Text(item, key, 2048);
                    }
                    break;
                case 'r':
                    if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > 2500) throw new ArgumentException("Bounded resolutions required.");
                    foreach (var resolution in value.EnumerateArray())
                    {
                        var item = Fields(resolution, ["key", "choice"]);
                        _ = Text(item, "key", 256);
                        if (Text(item, "choice", 20) is not ("current" or "incoming")) throw new ArgumentException("Invalid conflict choice.");
                    }
                    break;
                case 'g':
                    if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > 200) throw new ArgumentException("Bounded GUID array required.");
                    var guids = new HashSet<Guid>();
                    foreach (var item in value.EnumerateArray())
                        if (item.ValueKind != JsonValueKind.String || !Guid.TryParseExact(item.GetString(), "D", out var guid)
                            || guid == Guid.Empty || !guids.Add(guid)) throw new ArgumentException("Distinct nonempty GUIDs required.");
                    break;
                case 'v':
                    var attributes = Fields(value, ["description", "location", "managedBy"]);
                    if (attributes.Count is < 1 or > 3) throw new ArgumentException("One to three attributes required.");
                    foreach (var key in attributes.Keys) _ = Text(attributes, key, 1024);
                    break;
            }
        }
    }

    private sealed record Schema(Dictionary<string, char> Fields, string[] Required, bool Mutation = false);
    private static Schema S(string texts = "", string required = "", bool mutation = false, string bools = "", string ints = "", string arrays = "", string resolutions = "", string guidArrays = "", string reasons = "", string attributeValues = "")
    {
        var fields = new Dictionary<string, char>(StringComparer.Ordinal);
        foreach (var (list, type) in new[] { (texts, 's'), (bools, 'b'), (ints, 'i'), (arrays, 'a'), (resolutions, 'r'), (guidArrays, 'g'), (reasons, 'm'), (attributeValues, 'v') })
            foreach (var name in list.Split(' ', StringSplitOptions.RemoveEmptyEntries)) fields.Add(name, type);
        return new(fields, required.Split(' ', StringSplitOptions.RemoveEmptyEntries), mutation);
    }

    private static readonly IReadOnlyDictionary<string, Schema> Schemas = new Dictionary<string, Schema>(StringComparer.Ordinal)
    {
        ["session.info"] = S(), ["dashboard.read"] = S(bools: "inventory"), ["directory.sites"] = S(),
        ["directory.services"] = S("site", "site"), ["directory.search"] = S("query", "query", ints: "limit"),
        ["computer.inspect"] = S("computer", "computer"),
        ["attributes.inspect"] = S("computer", "computer"),
        ["attributes.prepare"] = S("inspectionId", "inspectionId values", true, attributeValues: "values"),
        ["attributes.apply"] = S("planId confirmationName", "planId confirmationName", true),
        ["attributes.observe"] = S("id", "id", true),
        ["offlineJoin.open"] = S(mutation: true),
        ["offlineJoin.list"] = S(),
        ["offlineJoin.import"] = S("objectGuid targetOU", "objectGuid targetOU confirmed", true, "confirmed"),
        ["offlineJoin.prepare"] = S("id", "id", true),
        ["offlineJoin.apply"] = S("planId confirmationName", "planId confirmationName confirmed", true, "confirmed"),
        ["offlineJoin.observe"] = S("id", "id", true),
        ["names.preview"] = S("type site service computer", "type site service", bools: "alternative"),
        ["join.precreated.preview"] = S("name targetOU", "name"),
        ["operation.prepare"] = S("kind computer previewId newName targetOU", "kind", true),
        ["operation.execute"] = S("planId confirmationName", "planId confirmationName", true, "entraLeaveConfirmed"),
        ["queue.add"] = S("kind computer newName targetOU previewId", "kind computer", true),
        ["queue.list"] = S(), ["queue.remove"] = S("id", "id", true), ["queue.prepare"] = S(mutation: true, bools: "pilot"),
        ["queue.execute"] = S("batchId", "batchId confirmed", true, "confirmed entraLeaveConfirmed"),
        ["receipts.list"] = S("query"), ["receipts.get"] = S("id", "id"), ["receipts.reconcile"] = S("id", "id", true), ["receipts.prepareMove"] = S("id", "id", true), ["logs.list"] = S("query level"),
        ["receipts.prepareAcknowledgement"] = S("id", "id", true),
        ["receipts.acknowledge"] = S("planId confirmationName", "planId confirmationName reason", true, reasons: "reason"),
        ["receipts.prepareRestart"] = S("id", "id", true),
        ["receipts.restart"] = S("planId confirmationName", "planId confirmationName", true),
        ["reservations.list"] = S(), ["reservations.inspect"] = S("id", "id", true),
        ["reservations.prepare"] = S("id action", "id action", true),
        ["reservations.execute"] = S("planId confirmationName", "planId confirmationName", true),
        ["coordination.status"] = S(), ["coordination.inspect"] = S(mutation: true),
        ["coordination.prepare"] = S(mutation: true), ["coordination.apply"] = S("planId", "planId confirmed", true, "confirmed"),
        ["settings.get"] = S(),
        ["settings.save"] = S("domain dc prefix namingPattern", "domain dc prefix namingPattern production randomNames sites", true,
            "production randomNames simulation liveExecutionEnabled", arrays: "sites"),
        ["diagnostics.read"] = S(),
        ["demo.open"] = S(mutation: true), ["demo.status"] = S(),
        ["demo.reset"] = S(required: "confirmed", mutation: true, bools: "confirmed"),
        ["demo.scenario"] = S("id", "id confirmed", true, "confirmed"),
        ["demo.restart"] = S(required: "confirmed", mutation: true, bools: "confirmed"),
        ["demo.prepareMove"] = S("id", "id", true),
        ["configuration.status"] = S(), ["configuration.settings"] = S(),
        ["configuration.export"] = S("version", mutation: true),
        ["configuration.previewImport"] = S(mutation: true),
        ["configuration.previewSettings"] = S("domain dc prefix rootOu preprodOu preprodSite namingPattern fingerprint coordinationRoot entraPolicy",
            "domain prefix rootOu namingPattern production randomNames sites", true,
            "production randomNames coordinationRequired reserveNamesInAd auditEventLogEnabled blockJoinOnClockSkew allowPrecreatedJoin allowOfflineJoin unattendedJoinEnabled unattendedOperationsEnabled", arrays: "sites", guidArrays: "excludedGroupGuids"),
        ["configuration.applyImport"] = S("planId", "planId confirmed", true, "confirmed"),
        ["configuration.decideDistribution"] = S("planId", "planId replace confirmed", true, "replace confirmed"),
        ["configuration.setDefault"] = S("version", "confirmed", true, "confirmed"),
        ["references.preview"] = S(mutation: true),
        ["references.apply"] = S("planId", "planId confirmed resolutions", true, "confirmed", resolutions: "resolutions"),
        ["updates.status"] = S(), ["updates.windows"] = S(),
        ["updates.inspect"] = S("source kind", mutation: true),
        ["updates.prepare"] = S("candidateId", "candidateId", true),
        ["updates.install"] = S("preparedId closeWindows", "preparedId confirmed", true, "confirmed"),
        ["updates.rollback"] = S("closeWindows", "confirmed", mutation: true, bools: "confirmed"),
        ["updates.recover"] = S("closeWindows", "confirmed", mutation: true, bools: "confirmed"),
        ["host.reconnect"] = S(required: "confirmed", mutation: true, bools: "confirmed")
    };

    [GeneratedRegex("^[A-Za-z0-9_-]{1,64}$", RegexOptions.CultureInvariant)]
    private static partial Regex RequestId();
}
