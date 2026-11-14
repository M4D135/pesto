using System.Text.Json.Nodes;
using Pesto.Bridge;

namespace Pesto.Engine.Tests;

internal sealed class BridgeIntegrationTests
{
    [Test]
    public async Task SessionInfoTravelsThroughTheClosedBridge()
    {
        var envelope = await Harness.DispatchAsync(Harness.Simulation(), "r1", "session.info");
        Check.Equal("result", Harness.Str(envelope, "kind"), "Réponse de succès");
        Check.Equal("simulation", envelope["data"]!["mode"]!.GetValue<string>(), "Données du moteur transmises");
    }

    [Test]
    public async Task UnknownOperationIsRejected()
    {
        var envelope = await Harness.DispatchAsync(Harness.Simulation(), "r2", "host.run", new { command = "calc" });
        Check.Equal("error", Harness.Str(envelope, "kind"), "Réponse d’erreur");
        Check.Equal("operation.unknown", Harness.ErrorCode(envelope), "Aucune opération hors contrat");
    }

    [Test]
    public async Task MissingRequiredFieldIsRejectedBeforeTheEngine()
    {
        var envelope = await Harness.DispatchAsync(Harness.Simulation(), "r3", "directory.services");
        Check.Equal("arguments.invalid", Harness.ErrorCode(envelope), "Champ requis exigé par le pont");
    }

    [Test]
    public async Task UnexpectedFieldIsRejected()
    {
        var envelope = await Harness.DispatchAsync(Harness.Simulation(), "r4", "operation.prepare", new { kind = "rename", evil = "x" });
        Check.Equal("arguments.invalid", Harness.ErrorCode(envelope), "Aucun champ non déclaré accepté");
    }

    [Test]
    public async Task InvalidRequestIdIsRejected()
    {
        var envelope = await Harness.DispatchAsync(Harness.Simulation(), "bad id", "session.info");
        Check.Equal("message.id", Harness.ErrorCode(envelope), "Identifiant de requête validé");
    }

    [Test]
    public async Task OversizedMessageIsRejected()
    {
        var dispatcher = new BridgeDispatcher(Harness.Simulation());
        var response = await dispatcher.DispatchAsync(new string('x', BridgeDispatcher.MaxMessageLength + 1), CancellationToken.None);
        var envelope = (JsonObject)JsonNode.Parse(response)!;
        Check.Equal("message.size", envelope["error"]!["code"]!.GetValue<string>(), "Message trop volumineux refusé");
    }
}
