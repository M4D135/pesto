using System.Diagnostics;

namespace Pesto.App;

/// <summary>A monotonic deadline shared by nested waits in one qualification run.</summary>
internal readonly record struct CoexistenceDeadline(CancellationToken Token, long Expires, string Code)
{
    internal static CoexistenceDeadline Start(CancellationToken token, TimeSpan limit, string code)
        => new(token, Stopwatch.GetTimestamp() + (long)(limit.TotalSeconds * Stopwatch.Frequency), code);

    private static readonly TimeSpan MinimumDelay = TimeSpan.FromMilliseconds(1);

    internal TimeSpan Remaining()
    {
        Token.ThrowIfCancellationRequested();
        var remaining = Left();
        return remaining > TimeSpan.Zero ? remaining : throw new CoexistenceTimeout(Code);
    }

    private TimeSpan Left() => Stopwatch.GetElapsedTime(Stopwatch.GetTimestamp(), Expires);

    internal CoexistenceDeadline Within(TimeSpan limit)
    {
        var step = Start(Token, limit, "qualification.coexistence.step-timeout");
        return step.Expires < Expires ? step : this;
    }

    // Decide without waiting for the WinForms message pump. A task already sent to COM cannot be
    // cancelled by this driver; it may settle later, but neither success nor another click is inferred.
    internal async Task<T> WaitAsync<T>(Func<Task<T>> issue)
    {
        _ = Remaining();
        var task = issue();
        try
        {
            var result = await task.WaitAsync(Remaining(), Token).ConfigureAwait(false);
            _ = Remaining(); // A delayed timer or worker must not turn an expired call into success.
            return result;
        }
        catch (TimeoutException error) when (error is not CoexistenceTimeout && !ReferenceEquals(task.Exception?.InnerException, error))
        {
            // The runtime timer can fire one clock tick before the monotonic deadline. Report the timeout only
            // once Remaining() agrees, so a later wait on this expired step can never issue another command.
            for (var left = Left(); left > TimeSpan.Zero; left = Left())
                await Task.Delay(left < MinimumDelay ? MinimumDelay : left, Token).ConfigureAwait(false);
            Token.ThrowIfCancellationRequested();
            throw new CoexistenceTimeout(Code, error);
        }
        finally
        {
            // WaitAsync cannot cancel an already dispatched WebView2 COM call. Observe any late
            // fault without touching a disposed form, writing proof, clicking again or starting a new step.
            if (!task.IsCompletedSuccessfully)
                _ = task.ContinueWith(t => { _ = t.Exception; }, CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
        }
    }

    // Start the command on the owning thread, keep diagnostic writes there and test the budget
    // again on resumption. A permanently blocked UI still needs the launcher's process timeout
    // to terminate it; it cannot run form cleanup or write its final proof while the pump is blocked.
    internal async Task<T> OnUiAsync<T>(Func<Task<T>> issue, Action<bool> pending)
    {
        Task<T>? native = null;
        try
        {
            var result = await WaitAsync(() =>
            {
                native = issue();
                pending(!native.IsCompleted);
                return native;
            });
            _ = Remaining();
            return result;
        }
        finally { if (native is not null) pending(!native.IsCompleted); }
    }
}

internal sealed class CoexistenceTimeout(string code, Exception? inner = null)
    : TimeoutException("Le délai de qualification est écoulé.", inner)
{
    internal string Code { get; } = code;
}
