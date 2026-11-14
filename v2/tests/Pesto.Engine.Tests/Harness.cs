using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Bridge;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>Controllable clock so plan and preview expiry can be exercised without waiting.</summary>
internal sealed class FixedClock : TimeProvider
{
    private DateTimeOffset now = new(2026, 10, 23, 8, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset GetUtcNow() => now;
    public void Advance(TimeSpan delta) => now += delta;
}

internal static class Harness
{
    private static readonly JsonSerializerOptions Write = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static IPestoBackend Simulation(FixedClock? clock = null) => PestoBackend.CreateSimulation(clock ?? new FixedClock());
    public static IPestoBackend Live(string? root = null) => PestoBackend.CreateLive(root);
    public static IPestoBackend Live(string? root, Pesto.Engine.IDirectoryGateway gateway) => PestoBackend.CreateLive(root, gateway);
    public static IPestoBackend Live(string? root, Pesto.Engine.IDirectoryGateway gateway, Pesto.Engine.IMutationGateway? mutation, FixedClock? clock = null)
    {
        FixtureEntraPreparation.SetClock(mutation, clock ?? TimeProvider.System);
        return PestoBackend.CreateLive(root, gateway, mutation, clock ?? TimeProvider.System, IsolatedGpRoot());
    }

    /// <summary>Qualification avec dossier GP explicite : l'historique durable (registre V1 + reçus de l'adaptateur) est lu là.</summary>
    public static IPestoBackend Live(string? root, Pesto.Engine.IDirectoryGateway gateway, Pesto.Engine.IMutationGateway? mutation, FixedClock? clock, string? gpRoot)
    {
        FixtureEntraPreparation.SetClock(mutation, clock ?? TimeProvider.System);
        return PestoBackend.CreateLive(root, gateway, mutation, clock ?? TimeProvider.System, gpRoot);
    }

    /// <summary>Dossier GP temporaire et vide : un test ne lit jamais un vrai %ProgramData%\GP et n'en dépend pas.</summary>
    public static string IsolatedGpRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "pesto-gp-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    public static JsonNode Call(IPestoBackend backend, string operation, object? args = null)
    {
        var element = JsonSerializer.SerializeToElement(args ?? new { }, Write);
        var result = backend.InvokeAsync(operation, element, CancellationToken.None).GetAwaiter().GetResult();
        return (JsonNode)result!;
    }

    public static string Str(JsonNode node, string key) => node[key]!.GetValue<string>();
    public static int Int(JsonNode node, string key) => node[key]!.GetValue<int>();
    public static bool Bool(JsonNode node, string key) => node[key]!.GetValue<bool>();
    public static bool IsNull(JsonNode node, string key) => node[key] is null;
    public static JsonArray Arr(JsonNode node, string key) => (JsonArray)node[key]!;

    /// <summary>Sends a message through the real bridge and returns the parsed response envelope.</summary>
    public static async Task<JsonObject> DispatchAsync(IPestoBackend backend, string id, string operation, object? args = null)
    {
        var dispatcher = new BridgeDispatcher(backend);
        var message = JsonSerializer.Serialize(new { id, op = operation, args = args ?? new { } }, Write);
        var response = await dispatcher.DispatchAsync(message, CancellationToken.None).ConfigureAwait(false);
        return (JsonObject)JsonNode.Parse(response)!;
    }

    public static string? ErrorCode(JsonObject envelope) => envelope["error"]?["code"]?.GetValue<string>();
}
