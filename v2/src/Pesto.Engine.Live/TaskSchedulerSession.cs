namespace Pesto.Engine.Live;

/// <summary>One authenticated COM connection for one exact target/task lifecycle. No password is retained.</summary>
public sealed class TaskSchedulerSession : IDisposable
{
    private readonly Func<string, string?, string?, object> connect;
    private readonly Action<object?> release;
    private object? service;
    private string? computer;
    private string? task;
    private bool disposed;

    public TaskSchedulerSession(Func<string, string?, string?, object> connect, Action<object?> release)
    {
        this.connect = connect;
        this.release = release;
    }

    public object Bind(string target, string taskName, string? principal, string? password)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (service is not null) throw new InvalidOperationException("Ce transport est déjà lié à une tâche.");
        service = connect(target, principal, password);
        computer = target;
        task = taskName;
        return service;
    }

    public object ForTask(string target, string taskName)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (service is null || !string.Equals(computer, target, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(task, taskName, StringComparison.Ordinal))
            throw new InvalidOperationException("Le transport authentifié ne correspond pas à cette cible et à cette tâche.");
        return service;
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        var previous = service;
        service = null;
        computer = null;
        task = null;
        release(previous);
    }
}

public static class TaskSchedulerComValues
{
    /// <summary>COM DATE is marshalled as DateTime. Never guess a locale-dependent date from a string.</summary>
    public static DateTimeOffset? LastRunTime(object? value)
    {
        try
        {
            return value switch
            {
                DateTimeOffset offset => offset,
                DateTime date => new DateTimeOffset(date),
                _ => null
            };
        }
        catch (ArgumentException) { return null; }
    }
}
