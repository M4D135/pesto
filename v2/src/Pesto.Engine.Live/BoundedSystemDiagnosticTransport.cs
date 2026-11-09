using System.Diagnostics;

namespace Pesto.Engine.Live;

/// <summary>
/// COM/RPC can block independently of the task's deadline. A timed-out read-side call abandons the whole
/// diagnostic, issues no later RPC, and cannot authorize an AD mutation. Its task/evidence remain for inspection.
/// </summary>
public sealed class BoundedSystemDiagnosticTransport(ISystemDiagnosticTaskTransport inner, bool ownsTransport = false,
    TimeSpan? budget = null, TimeSpan? callTimeout = null) : ISystemDiagnosticTaskTransport, IDisposable
{
    private readonly Stopwatch elapsed = Stopwatch.StartNew();
    private readonly TimeSpan budget = budget ?? TimeSpan.FromSeconds(110);
    private readonly TimeSpan callTimeout = callTimeout ?? TimeSpan.FromSeconds(15);
    private Task? active;
    private bool faulted;
    private bool disposed;

    private T Call<T>(Func<T> operation)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (faulted || elapsed.Elapsed >= budget) throw new TimeoutException("Délai global du diagnostic dépassé.");
        var remaining = budget - elapsed.Elapsed;
        var wait = remaining < callTimeout ? remaining : callTimeout;
        var task = Task.Run(operation);
        active = task;
        try
        {
            if (!task.Wait(wait))
            {
                faulted = true;
                throw new TimeoutException("Réponse COM du diagnostic non confirmée dans le délai.");
            }
            return task.GetAwaiter().GetResult();
        }
        catch (AggregateException error) { throw error.InnerException ?? error; }
        finally { if (task.IsCompleted) active = null; }
    }

    public void RegisterSystem(string computer, string taskName, string xml, string connectionPrincipal, string connectionPassword) =>
        Call(() => { inner.RegisterSystem(computer, taskName, xml, connectionPrincipal, connectionPassword); return true; });
    public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal) =>
        throw new InvalidOperationException("Ce transport borné est réservé au diagnostic SYSTEM.");
    public void Run(string computer, string taskName) => Call(() => { inner.Run(computer, taskName); return true; });
    public TaskProbeResult Probe(string computer, string taskName) => Call(() => inner.Probe(computer, taskName));
    public void Delete(string computer, string taskName) => Call(() => { inner.Delete(computer, taskName); return true; });
    public string? ReadTaskLogTail(string computer, string localLogPath) => throw new InvalidOperationException("Le diagnostic ne lit aucun journal SMB.");

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (!ownsTransport || inner is not IDisposable disposable) return;
        // Never release a COM session while a timed-out call still owns it. No continuation runs another command.
        if (active is { IsCompleted: false } pending)
            _ = pending.ContinueWith(t => { _ = t.Exception; disposable.Dispose(); }, TaskScheduler.Default);
        else disposable.Dispose();
    }
}
