using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.Engine.Tests;

internal sealed class PackWindowsTests
{
    [Test]
    public async Task NoWindowsReturnsEvenWhenTokenWasProvided()
    {
        var source = new FakeSource();
        await PackWindows.ReleaseAsync(source, "any-token", CancellationToken.None);
        Check.Equal(0, source.CloseRequests, "no close requested");
    }

    [Test]
    public async Task RefusesWithoutToken()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Fenêtre", null));
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, "", CancellationToken.None), "update.windows", "missing token refuses");
        Check.Contains("Fenêtre", error.Message, "names the window");
        Check.Equal(0, source.CloseRequests, "no close before confirmation");
    }

    [Test]
    public async Task RefusesIfListChanged()
    {
        var original = new PackProcess(1, 10, "Fenêtre", null);
        var token = PackWindows.Token([original]);
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 11, "Fenêtre", null));
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, token, CancellationToken.None), "update.windows", "changed list refuses");
        Check.Contains("Fenêtre", error.Message, "names the current window");
        Check.Equal(0, source.CloseRequests, "no close when token is stale");
    }

    [Test]
    public async Task BlockedWindowRefusesEverythingWithoutClosing()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Bloquée", "bloque"));
        var token = PackWindows.Token(source.Processes);
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, token, CancellationToken.None), "update.windows", "blocked window refuses");
        Check.Contains("Bloquée", error.Message, "names blocked window");
        Check.Contains("bloque", error.Message, "names blocker");
        Check.Equal(0, source.CloseRequests, "no close when any window is blocked");
    }

    [Test]
    public async Task ClosesConsentedWindowsThenReturns()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Un", null));
        source.Processes.Add(new PackProcess(2, 20, "Deux", null));
        var token = PackWindows.Token(source.Processes);
        await PackWindows.ReleaseAsync(source, token, CancellationToken.None, attempts: 3, interval: TimeSpan.Zero);
        Check.Equal(2, source.CloseRequests, "one request per window");
        Check.True(source.ClosedIds.Count == 2, "both windows closed");
    }

    [Test]
    public async Task RemainingWindowProducesUpdateRunningAfterOneCloseRequest()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Restante", null));
        source.CloseNever = true;
        var token = PackWindows.Token(source.Processes);
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, token, CancellationToken.None, attempts: 3, interval: TimeSpan.Zero), "update.running", "window remains open");
        Check.Contains("Restante", error.Message, "names remaining window");
        Check.Equal(1, source.CloseRequests, "close requested once");
    }

    [Test]
    public async Task WindowHeldByADialogGetsTheRequestOnceTheDialogCloses()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Dialogue", null));
        source.RefusedRequests[1] = 2;
        await PackWindows.ReleaseAsync(source, PackWindows.Token(source.Processes), CancellationToken.None, attempts: 5, interval: TimeSpan.Zero);
        Check.Equal(3, source.CloseRequests, "request repeated until delivered, then not again");
        Check.True(source.ClosedIds.Contains(1), "window closed once its dialog was gone");
    }

    [Test]
    public async Task UndeliveredRequestIsNotReportedAsPending()
    {
        var source = new FakeSource();
        source.Processes.Add(new PackProcess(1, 10, "Dialogue", null));
        source.RefusedRequests[1] = int.MaxValue;
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, PackWindows.Token(source.Processes), CancellationToken.None, attempts: 3, interval: TimeSpan.Zero),
            "update.running", "a dialog keeps the window open");
        Check.Contains("n’ont pas pu recevoir la demande de fermeture : « Dialogue »", error.Message, "undelivered request named");
        Check.Contains("Aucun fichier n’a été remplacé", error.Message, "nothing replaced");
        Check.False(error.Message.Contains("reste demandée", StringComparison.Ordinal), "no pending closure claimed");
    }

    [Test]
    public async Task ClosingAndUnreachedWindowsAreReportedApart()
    {
        var source = new FakeSource { CloseNever = true };
        source.Processes.Add(new PackProcess(1, 10, "Occupée", null));
        source.Processes.Add(new PackProcess(2, 20, "Dialogue", null));
        source.RefusedRequests[2] = int.MaxValue;
        var error = await ExpectPesto(() => PackWindows.ReleaseAsync(source, PackWindows.Token(source.Processes), CancellationToken.None, attempts: 3, interval: TimeSpan.Zero),
            "update.running", "both windows remain open");
        Check.Contains("ne se sont pas fermées à temps : « Occupée ». Une opération y est peut-être en cours ; leur fermeture reste demandée.", error.Message, "delivered request still pending");
        Check.Contains("n’ont pas pu recevoir la demande de fermeture : « Dialogue ».", error.Message, "undelivered request named apart");
    }

    [Test]
    public void DescribeAndTokenAreStableAndOrdered()
    {
        var a = new PackProcess(1, 10, "Un", null);
        var b = new PackProcess(2, 20, "Deux", "bloque");
        var token = PackWindows.Token([a, b]);
        Check.True(token.Length == 64, "token is SHA-256 hex");
        Check.Equal(token, PackWindows.Token([b, a]), "token independent of order");

        var described = PackWindows.Describe([a, b]);
        var windows = (JsonArray)described["windows"]!;
        Check.Equal(2, windows.Count, "two windows described");

        var first = (JsonObject)windows[0]!;
        Check.Equal(PackWindows.Id(a), first["id"]!.GetValue<string>(), "first id");
        Check.True(first["closable"]!.GetValue<bool>(), "first closable");
        Check.Null(first["reason"], "reason absent when closable");

        var second = (JsonObject)windows[1]!;
        Check.False(second["closable"]!.GetValue<bool>(), "second not closable");
        Check.Equal("bloque", second["reason"]!.GetValue<string>(), "second reason");

        Check.Equal(token, described["token"]!.GetValue<string>(), "describe token");
        Check.Equal("", PackWindows.Token([]), "empty token");
        Check.Equal(0, ((JsonArray)PackWindows.Describe([])["windows"]!).Count, "empty windows");
    }

    private static async Task<PestoException> ExpectPesto(Func<Task> action, string code, string message)
    {
        try
        {
            await action();
        }
        catch (PestoException error) when (error.Code == code)
        {
            return error;
        }
        catch (PestoException error)
        {
            throw new TestFailureException($"{message} (attendu {code}, obtenu {error.Code})");
        }
        throw new TestFailureException($"{message} (aucune exception {code})");
    }

    private sealed class FakeSource : IPackProcessSource
    {
        public List<PackProcess> Processes { get; } = new();
        public HashSet<int> ClosedIds { get; } = new();
        public int CloseRequests { get; private set; }
        public bool CloseNever { get; set; }

        public IReadOnlyList<PackProcess> List() => Processes;

        // Windows kept disabled by a dialog: requests refused before one is delivered.
        public Dictionary<int, int> RefusedRequests { get; } = new();

        public bool RequestClose(PackProcess process)
        {
            CloseRequests++;
            if (RefusedRequests.TryGetValue(process.Id, out var left) && left > 0) { RefusedRequests[process.Id] = left - 1; return false; }
            if (!CloseNever && process.Blocker is null) ClosedIds.Add(process.Id);
            return true;
        }

        public bool HasExited(PackProcess process) => ClosedIds.Contains(process.Id);
    }
}
