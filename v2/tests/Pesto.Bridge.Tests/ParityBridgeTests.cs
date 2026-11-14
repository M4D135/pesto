using System.Text.Json;
using Pesto.Core;

namespace Pesto.Bridge.Tests;

internal sealed class ParityBridgeTests
{
    private sealed class RecordingBackend : IPestoBackend
    {
        public int Calls;
        public JsonElement Last;
        public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken token = default)
        { Calls++; Last = args.Clone(); return Task.FromResult<object?>(new { accepted = true }); }
    }
    private static string Message(string op, object args) => JsonSerializer.Serialize(new { id = "parity", op, args });
    private static string Code(string response) => JsonDocument.Parse(response).RootElement.GetProperty("error").GetProperty("code").GetString()!;
    private static string Kind(string response) => JsonDocument.Parse(response).RootElement.GetProperty("kind").GetString()!;

    [Test]
    public async Task AttributeValuesPreserveExactWhitespaceAndExplicitEmptyValues()
    {
        var native = new RecordingBackend(); var dispatcher = new BridgeDispatcher(native);
        var result = await dispatcher.DispatchAsync(Message("attributes.prepare", new { inspectionId = "inspection", values = new { description = "  exact  ", location = "" } }));
        Check.Equal("result", Kind(result), "Closed attribute preparation accepted");
        Check.Equal("  exact  ", native.Last.GetProperty("values").GetProperty("description").GetString(), "No trim or normalization");
        Check.Equal("", native.Last.GetProperty("values").GetProperty("location").GetString(), "Explicit clear remains empty");
        Check.True(!native.Last.GetProperty("values").TryGetProperty("managedBy", out _), "Omitted attribute remains absent");
    }

    [Test]
    public async Task AttributesRejectUnknownDuplicateNullControlAndOversizedValuesBeforeBackend()
    {
        var native = new RecordingBackend(); var dispatcher = new BridgeDispatcher(native);
        foreach (var values in new[] { "{}", "{\"password\":\"x\"}", "{\"description\":null}", "{\"location\":1}",
            "{\"description\":\"a\",\"description\":\"b\"}", "{\"description\":\"line\\nnext\"}",
            JsonSerializer.Serialize(new { description = new string('x', 1025) }) })
        {
            var result = await dispatcher.DispatchAsync("{\"id\":\"invalid\",\"op\":\"attributes.prepare\",\"args\":{\"inspectionId\":\"held\",\"values\":" + values + "}}");
            Check.Equal("arguments.invalid", Code(result), "Malformed attribute shape never reaches native code");
        }
        Check.Equal(0, native.Calls, "No backend call for an invalid diff");
    }

    [Test]
    public async Task OfflineAndAttributesRejectForgedAuthoritiesPathsAndSecrets()
    {
        var native = new RecordingBackend(); var dispatcher = new BridgeDispatcher(native);
        foreach (var (operation, args) in new (string, object)[]
        {
            ("attributes.inspect", new { computer = "PC", computerGuid = Guid.NewGuid().ToString() }),
            ("attributes.prepare", new { inspectionId = "held", values = new { description = "x" }, before = "old" }),
            ("attributes.apply", new { planId = "held", confirmationName = "PC", force = true }),
            ("attributes.observe", new { id = "receipt", replay = true }),
            ("offlineJoin.import", new { objectGuid = Guid.NewGuid().ToString(), targetOU = "OU=PC,DC=x,DC=local", confirmed = true, path = @"\\server\secret" }),
            ("offlineJoin.import", new { objectGuid = Guid.NewGuid().ToString(), targetOU = "OU=PC,DC=x,DC=local", confirmed = true, blob = "secret" }),
            ("offlineJoin.apply", new { planId = "held", confirmationName = "PC", confirmed = true, command = "djoin" }),
            ("offlineJoin.observe", new { id = "held", repair = true }),
            ("offlineJoin.open", new { configuration = @"C:\other\cfg.json" }),
            ("queue.execute", new { batchId = "held", confirmed = true, pilot = false })
        })
            Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Message(operation, args))), "Only native authority and the prepared batch determine effects");
        Check.Equal(0, native.Calls, "No path, secret or effect-authority input admitted");
        Check.Equal("operation.unknown", Code(await dispatcher.DispatchAsync(Message("automation.execute", new { }))), "CLI is never exposed to the web bridge");
    }

    [Test]
    public async Task PilotChoiceIsAStrictBooleanBoundOnlyAtPreparation()
    {
        var native = new RecordingBackend(); var dispatcher = new BridgeDispatcher(native);
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Message("queue.prepare", new { pilot = "true" }))), "No string truthiness");
        Check.Equal("result", Kind(await dispatcher.DispatchAsync(Message("queue.prepare", new { pilot = true }))), "Pilot accepted only in preparation");
        Check.True(native.Last.GetProperty("pilot").GetBoolean(), "Exact explicit pilot choice reaches engine");
    }
}
