using System.Text.Json;
using Pesto.App;

namespace Pesto.Engine.Tests;

internal sealed class BridgeAdmissionTests
{
    private const string Canary = "CANARY-parc-prive";

    private static string Request(string id, string op = "directory.search") =>
        JsonSerializer.Serialize(new Dictionary<string, object>
        {
            ["id"] = id,
            ["op"] = op,
            ["args"] = new Dictionary<string, object> { ["query"] = Canary, ["padding"] = new string('x', 4096) },
        });

    [Test]
    public void WithinTheDeclaredLimitsTheMessageReachesTheDispatcher()
    {
        Check.Equal(BridgeAdmission.Decision.Accepted, BridgeAdmission.Classify("{}", 0), "An ordinary request must be dispatched");
        Check.Equal(BridgeAdmission.Decision.Accepted, BridgeAdmission.Classify("{}", HostPolicy.MaximumPendingMessages - 1),
            "The last admissible pending slot must still be dispatched");
        Check.Equal(BridgeAdmission.Decision.RejectedSize,
            BridgeAdmission.Classify(new string('x', HostPolicy.MaximumMessageLength + 1), 0), "An oversized message must be rejected");
        Check.Equal(BridgeAdmission.Decision.RejectedBackpressure,
            BridgeAdmission.Classify("{}", HostPolicy.MaximumPendingMessages), "A flooded bridge must be rejected");
    }

    [Test]
    public void AnAcceptedMessageIsNeverAnsweredTwice()
    {
        Check.Null(BridgeAdmission.CorrelatedRefusal(Request("p1"), BridgeAdmission.Decision.Accepted),
            "An accepted request must not receive a refusal");
    }

    [Test]
    public void ARejectedRequestSettlesWithItsOwnCorrelatedError()
    {
        foreach (var (decision, code, retryable) in new[]
        {
            (BridgeAdmission.Decision.RejectedSize, "bridge.rejected.size", false),
            (BridgeAdmission.Decision.RejectedBackpressure, "bridge.rejected.backpressure", true),
        })
        {
            var refusal = BridgeAdmission.CorrelatedRefusal(Request("p7"), decision);
            Check.NotNull(refusal, $"A rejected request must still settle its promise ({code})");
            using var document = JsonDocument.Parse(refusal!);
            var root = document.RootElement;
            Check.Equal("p7", root.GetProperty("id").GetString(), "The refusal must carry the page identifier");
            Check.Equal("error", root.GetProperty("kind").GetString(), "The page only settles an error kind");
            Check.Equal(code, root.GetProperty("error").GetProperty("code").GetString(), "The refusal must be named");
            Check.Equal(retryable, root.GetProperty("error").GetProperty("retryable").GetBoolean(), "Retryability must be stated");
            Check.Equal("directory.search", root.GetProperty("op").GetString(), "The refused operation must be named");
            Check.False(refusal!.Contains(Canary), "A refusal must never echo the request arguments");
        }
    }

    [Test]
    public void AnUncorrelatedPayloadIsRefusedSilentlyRatherThanEchoed()
    {
        Check.Null(BridgeAdmission.CorrelatedRefusal("not json", BridgeAdmission.Decision.RejectedSize),
            "Unreadable bytes must not be reflected to the page");
        Check.Null(BridgeAdmission.CorrelatedRefusal("[1,2,3]", BridgeAdmission.Decision.RejectedSize),
            "A non-object payload cannot be correlated");
        Check.Null(BridgeAdmission.CorrelatedRefusal("{\"op\":\"directory.search\"}", BridgeAdmission.Decision.RejectedBackpressure),
            "A request without an identifier cannot be answered");
        Check.Null(BridgeAdmission.CorrelatedRefusal("{\"id\":42}", BridgeAdmission.Decision.RejectedSize),
            "A non-string identifier is not ours to answer");
        Check.Null(BridgeAdmission.CorrelatedRefusal($"{{\"id\":\"{new string('p', BridgeAdmission.MaximumCorrelationIdLength + 1)}\"}}",
            BridgeAdmission.Decision.RejectedSize), "An oversized identifier is refused without an answer");
    }
}
