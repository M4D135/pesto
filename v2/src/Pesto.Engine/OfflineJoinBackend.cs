using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Native windows only. A selected blob path never enters the WebView contract.</summary>
public interface IPestoOfflineJoinHost
{
    Task<object?> OpenOfflineJoinAsync(CancellationToken cancellationToken);
    Task<string?> SelectOfflineJoinBlobAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Closed local entry point: it cannot delegate to the ordinary directory, maintenance or mutation backend.
/// Only explicit postboot observation may ask the ODJ provider to contact Active Directory.
/// </summary>
public sealed class OfflineJoinBackend(OfflineJoinService service, IPestoOfflineJoinHost host, string account)
    : IPestoBackend, IDisposable
{
    private readonly SemaphoreSlim admission = new(1, 1);
    private bool disposed;

    public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        if (operation is not ("session.info" or "offlineJoin.list" or "offlineJoin.import" or "offlineJoin.prepare" or "offlineJoin.apply" or "offlineJoin.observe"))
            throw new PestoException("offlineJoin.local_only", "Cette fenêtre est réservée à la jonction hors ligne locale. Ouvrez Pesto normalement pour les autres parcours.");
        await admission.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (disposed) throw new PestoException("offlineJoin.closed", "La fenêtre locale est fermée.");
            switch (operation)
            {
                case "session.info":
                {
                    Arguments.Only(args);
                    var status = service.List();
                    var available = status["available"]?.GetValue<bool>() == true;
                    return new JsonObject
                    {
                        ["mode"] = "offline", ["localOnly"] = true, ["readOnly"] = !available,
                        ["computer"] = status["local"]?["computer"]?.DeepClone(),
                        ["domain"] = status["local"]?["domain"]?.DeepClone(), ["dc"] = null,
                        ["account"] = account, ["version"] = EngineVersion.Current,
                        ["capabilities"] = new JsonArray(new JsonObject { ["id"] = "offlineJoin", ["enabled"] = available,
                            ["reason"] = status["reason"]?.DeepClone() })
                    };
                }
                case "offlineJoin.list": Arguments.Only(args); return service.List();
                case "offlineJoin.import":
                {
                    Arguments.Only(args, "objectGuid", "targetOU", "confirmed");
                    var guid = Arguments.Text(args, "objectGuid", true, 36);
                    if (!Guid.TryParseExact(guid, "D", out var parsed) || parsed == Guid.Empty)
                        throw new PestoException("invalid_arguments", "Le GUID AD déclaré doit être complet et non vide.");
                    var ou = Arguments.Text(args, "targetOU", true, 2048);
                    if (!V1Config.IsOuPath(ou)) throw new PestoException("invalid_arguments", "L’OU AD déclarée doit être complète.");
                    if (!Arguments.Flag(args, "confirmed")) throw new PestoException("confirmation.required", "Confirmez l’import local du blob et ses références AD déclarées.");
                    var availability = service.List();
                    if (availability["available"]?.GetValue<bool>() != true)
                        throw new PestoException("offlineJoin.unavailable", availability["reason"]?.GetValue<string>() ?? "L’import local n’est pas disponible dans ce contexte.");
                    var path = await host.SelectOfflineJoinBlobAsync(cancellationToken).ConfigureAwait(false);
                    return path is null ? new JsonObject { ["status"] = "cancelled" } : service.Import(path, guid, ou, true);
                }
                case "offlineJoin.prepare":
                    Arguments.Only(args, "id"); return service.Prepare(Arguments.Text(args, "id", true, 128));
                case "offlineJoin.apply":
                    Arguments.Only(args, "planId", "confirmationName", "confirmed");
                    return service.Apply(Arguments.Text(args, "planId", true, 128), Arguments.Text(args, "confirmationName", true, 15), Arguments.Flag(args, "confirmed"));
                default:
                    Arguments.Only(args, "id"); return service.Observe(Arguments.Text(args, "id", true, 128));
            }
        }
        finally { admission.Release(); }
    }

    public void Dispose()
    {
        admission.Wait();
        try { if (!disposed) { disposed = true; service.Dispose(); } }
        finally { admission.Release(); }
    }
}
