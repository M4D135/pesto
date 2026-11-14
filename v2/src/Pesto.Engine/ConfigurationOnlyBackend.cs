using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Closed local session. ApplicationServicesBackend owns explicit configuration/import/update actions.</summary>
internal sealed class ConfigurationOnlyBackend(string? configurationRoot, string? gpRoot) : IPestoBackend
{
    private const string Reason = "Configuration locale : reconnectez Pesto pour ouvrir une session Active Directory.";
    private readonly IPestoBackend local = new LiveBackend(configurationRoot, null, null, TimeProvider.System, gpRoot);

    public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        // Refuse before inspecting any business arguments, including direct API calls outside the UI.
        if (operation is not ("session.info" or "settings.get" or "diagnostics.read" or "logs.list"))
            throw new PestoException("session.configurationOnly", Reason);
        var result = await local.InvokeAsync(operation, args, cancellationToken).ConfigureAwait(false);
        if (operation == "session.info" && result is JsonObject session)
        {
            session["configurationOnly"] = true;
            session["readOnly"] = true;
            session["dc"] = null;
            if (session["capabilities"] is JsonArray capabilities)
                foreach (var capability in capabilities.OfType<JsonObject>())
                {
                    capability["enabled"] = false;
                    capability["reason"] = Reason;
                }
        }
        return result;
    }
}
