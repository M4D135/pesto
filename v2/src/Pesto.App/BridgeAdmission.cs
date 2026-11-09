using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pesto.App;

/// <summary>
/// Decides whether a message from the page may reach the dispatcher, and builds the correlated
/// refusal the page needs. A message the host never accepted must still settle its promise: an
/// unanswered call keeps the screen busy and the router never marks the screen ready.
/// </summary>
internal static class BridgeAdmission
{
    internal enum Decision
    {
        Accepted,
        RejectedSize,
        RejectedBackpressure,
    }

    // The id is only read to answer it. Anything longer than the bridge's own identifiers is not ours.
    internal const int MaximumCorrelationIdLength = 64;

    internal static Decision Classify(string json, int pendingRequests) =>
        json.Length > HostPolicy.MaximumMessageLength ? Decision.RejectedSize
        : pendingRequests >= HostPolicy.MaximumPendingMessages ? Decision.RejectedBackpressure
        : Decision.Accepted;

    /// <summary>Returns the JSON to post back, or null when the message cannot be safely correlated.</summary>
    internal static string? CorrelatedRefusal(string json, Decision decision)
    {
        if (decision == Decision.Accepted) return null;

        string? id = null;
        string? op = null;
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            if (document.RootElement.TryGetProperty("id", out var idElement))
            {
                if (idElement.ValueKind != JsonValueKind.String) return null;
                id = idElement.GetString();
            }
            if (document.RootElement.TryGetProperty("op", out var opElement) && opElement.ValueKind == JsonValueKind.String)
                op = opElement.GetString();
        }
        catch (JsonException)
        {
            // An unreadable payload cannot be correlated; it stays unanswered rather than echoing unknown bytes.
            return null;
        }

        if (string.IsNullOrEmpty(id) || id.Length > MaximumCorrelationIdLength) return null;

        var (code, message, retryable) = decision == Decision.RejectedSize
            ? ("bridge.rejected.size", "Cette demande dépasse la taille autorisée. Aucune opération n’a été lancée.", false)
            : ("bridge.rejected.backpressure", "Trop d’opérations sont déjà en attente. Aucune opération n’a été lancée.", true);

        var refusal = new JsonObject
        {
            ["id"] = id,
            ["kind"] = "error",
            ["error"] = new JsonObject { ["code"] = code, ["message"] = message, ["retryable"] = retryable },
        };
        if (!string.IsNullOrEmpty(op)) refusal["op"] = op;
        return refusal.ToJsonString();
    }
}
