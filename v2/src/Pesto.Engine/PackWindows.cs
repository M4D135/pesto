using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Another Pesto.exe started from this pack. Blocker is null when Pesto may ask its window to close.</summary>
public sealed record PackProcess(int Id, long StartTicks, string Label, string? Blocker);

/// <summary>Process access stays in the Windows host; the engine decides what is listed, closed or refused.</summary>
public interface IPackProcessSource
{
    IReadOnlyList<PackProcess> List();            // other Pesto.exe of this pack, calling process excluded
    bool RequestClose(PackProcess process);       // the window's own close request, never a kill; false when not delivered
    bool HasExited(PackProcess process);          // also true when the identifier now belongs to another process
}

/// <summary>Optional host capability, like IPestoOfflineJoinHost.</summary>
public interface IPestoPackWindowsHost { IPackProcessSource PackProcesses { get; } }

public static class PackWindows
{
    public static string Id(PackProcess p) =>
        p.Id.ToString(System.Globalization.CultureInfo.InvariantCulture) + "-" +
        p.StartTicks.ToString(System.Globalization.CultureInfo.InvariantCulture);

    public static string Token(IReadOnlyList<PackProcess> processes)
    {
        if (processes.Count == 0) return "";
        var ids = processes.Select(Id).OrderBy(id => id, StringComparer.Ordinal).ToList();
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join("\n", ids)));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static JsonObject Describe(IReadOnlyList<PackProcess> processes)
    {
        var windows = new JsonArray();
        foreach (var process in processes)
        {
            var item = new JsonObject
            {
                ["id"] = Id(process),
                ["label"] = process.Label,
                ["closable"] = process.Blocker is null,
            };
            if (process.Blocker is not null) item["reason"] = process.Blocker;
            windows.Add(item);
        }
        return new JsonObject { ["windows"] = windows, ["token"] = Token(processes) };
    }

    public static async Task ReleaseAsync(IPackProcessSource source, string token, CancellationToken cancellationToken,
        int attempts = 120, TimeSpan? interval = null)
    {
        var others = source.List();
        if (others.Count == 0) return;

        if (string.IsNullOrEmpty(token))
            throw new PestoException("update.windows",
                $"D’autres fenêtres Pesto de ce pack sont ouvertes : {Names(others)}. Rien n’a été modifié ; recommencez pour les voir et confirmer leur fermeture.");

        if (!string.Equals(token, Token(others), StringComparison.Ordinal))
            throw new PestoException("update.windows",
                $"Les fenêtres Pesto ouvertes ont changé depuis votre confirmation : {Names(others)}. Aucune fenêtre n’a été fermée et rien n’a été modifié ; recommencez.");

        var blocked = others.Where(p => p.Blocker is not null).ToList();
        if (blocked.Count > 0)
            throw new PestoException("update.windows",
                $"Pesto ne peut pas fermer lui-même : {string.Join(" ; ", blocked.Select(p => $"« {p.Label} » ({p.Blocker})"))}. Fermez-les puis recommencez ; rien n’a été modifié.");

        // A window kept disabled by a Windows dialog does not take the request: it is asked again until the dialog closes.
        var unreached = others.Where(process => !source.RequestClose(process)).ToList();

        var wait = interval ?? TimeSpan.FromMilliseconds(250);
        for (var attempt = 0; attempt < attempts; attempt++)
        {
            unreached.RemoveAll(process => source.HasExited(process) || source.RequestClose(process));
            if (others.All(source.HasExited)) return;
            await Task.Delay(wait, cancellationToken).ConfigureAwait(false);
        }

        var remaining = others.Where(process => !source.HasExited(process)).ToList();
        if (remaining.Count == 0) return;
        var closing = remaining.Where(process => !unreached.Contains(process)).ToList();
        var held = remaining.Where(unreached.Contains).ToList();
        var message = new StringBuilder();
        if (closing.Count > 0)
            message.Append($"Ces fenêtres Pesto ne se sont pas fermées à temps : {Names(closing)}. Une opération y est peut-être en cours ; leur fermeture reste demandée. ");
        if (held.Count > 0)
            message.Append($"Ces fenêtres Pesto n’ont pas pu recevoir la demande de fermeture : {Names(held)}. Une boîte de dialogue Windows y est probablement ouverte ; fermez-la. ");
        message.Append("Aucun fichier n’a été remplacé ; recommencez une fois ces fenêtres fermées.");
        throw new PestoException("update.running", message.ToString());
    }

    private static string Names(IReadOnlyList<PackProcess> processes) =>
        string.Join(", ", processes.Select(process => $"« {process.Label} »"));
}
