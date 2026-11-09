using System.Diagnostics;
using Pesto.App;

namespace Pesto.Engine.Tests;

internal sealed class CoexistenceDeadlineTests
{
    private const string GlobalTimeout = "qualification.coexistence.timeout";
    private const string StepTimeout = "qualification.coexistence.step-timeout";
    private static readonly TimeSpan Budget = TimeSpan.FromMilliseconds(200);
    private static readonly TimeSpan Safety = TimeSpan.FromSeconds(5);

    private static CoexistenceDeadline Campaign(CancellationToken token = default)
        => CoexistenceDeadline.Start(token, TimeSpan.FromSeconds(60), GlobalTimeout);

    private static async Task ExpectTimeout(Task task, string code)
    {
        try { await task.WaitAsync(Safety); }
        catch (CoexistenceTimeout error)
        {
            Check.Equal(code, error.Code, "The earliest applicable deadline must be identified");
            return;
        }
        throw new TestFailureException("An expired qualification wait succeeded.");
    }

    // The WinForms message pump is deliberately not serviced. Only the explicit call to
    // ResumeOneAsync runs a queued UI continuation. No actual WebView or Windows is required.
    private sealed class HeldUi : SynchronizationContext
    {
        private readonly TaskCompletionSource<(SendOrPostCallback Callback, object? State)> posted =
            new(TaskCreationOptions.RunContinuationsAsynchronously);

        public override void Post(SendOrPostCallback callback, object? state) => posted.SetResult((callback, state));
        internal bool HasPost => posted.Task.IsCompleted;
        internal Task Posted => posted.Task;

        internal Task<T> Start<T>(Func<Task<T>> callback)
        {
            var previous = Current;
            SetSynchronizationContext(this);
            try { return callback(); }
            finally { SetSynchronizationContext(previous); }
        }

        internal async Task ResumeOneAsync()
        {
            var (callback, state) = await posted.Task.WaitAsync(Safety);
            callback(state);
        }
    }

    [Test]
    public async Task NonPumpingUiCannotHoldTheDeadlineDecisionOrTriggerAnotherCall()
    {
        var ui = new HeldUi();
        var issued = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        int calls = 0;
        var step = Campaign().Within(Budget);
        var waiting = ui.Start(() => step.WaitAsync(() => { calls++; return issued.Task; }));
        await ExpectTimeout(waiting, StepTimeout);
        Check.False(ui.HasPost, "The failure decision does not depend on an available UI pump");
        Check.False(issued.Task.IsCompleted, "The underlying native task is still pending at timeout");
        issued.SetException(new IOException("synthetic late COM failure"));
        await ExpectTimeout(step.WaitAsync(() => { calls++; return Task.FromResult(42); }), StepTimeout);
        Check.Equal(1, calls, "An expired step must not issue or retry a command");
    }

    [Test]
    public async Task LateUiResumeRejectsEvenAnOnTimeNativeReply()
    {
        var ui = new HeldUi();
        var issued = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
        bool pending = false;
        var step = Campaign().Within(Budget);
        var waiting = ui.Start(() => step.OnUiAsync(() => issued.Task, value => pending = value));
        Check.True(pending, "The UI recorded dispatch of the pending native read");
        issued.SetResult(13);
        await ui.Posted.WaitAsync(Safety); // The native wait returned, but the UI cannot process the result yet.
        var remaining = Stopwatch.GetElapsedTime(Stopwatch.GetTimestamp(), step.Expires);
        if (remaining > TimeSpan.Zero) await Task.Delay(remaining + TimeSpan.FromMilliseconds(5));
        Check.False(waiting.IsCompleted, "The UI continuation still needs its pump");
        await ui.ResumeOneAsync();
        await ExpectTimeout(waiting, StepTimeout);
        Check.False(pending, "The returned native call no longer counts as pending");
    }

    [Test]
    public async Task OuterDeadlineAndParentCancellationTakePrecedence()
    {
        var campaign = CoexistenceDeadline.Start(default, Budget, GlobalTimeout);
        var nested = campaign.Within(TimeSpan.FromSeconds(35));
        await ExpectTimeout(nested.WaitAsync(() => new TaskCompletionSource<int>().Task), GlobalTimeout);

        using var stop = new CancellationTokenSource();
        var reader = Campaign(stop.Token);
        var waiting = reader.WaitAsync(() => new TaskCompletionSource<int>().Task);
        stop.Cancel();
        try { await waiting.WaitAsync(Safety); }
        catch (OperationCanceledException error) when (error.CancellationToken == stop.Token) { return; }
        throw new TestFailureException("Parent cancellation did not stop the pending observation.");
    }

    [Test]
    public async Task OriginalNativeFaultAndSuccessfulReplyArePreserved()
    {
        var campaign = Campaign();
        var expected = new TimeoutException("synthetic failure raised by the native operation");
        Exception? observed = null;
        try { await campaign.WaitAsync(() => Task.FromException<int>(expected)); }
        catch (Exception error) { observed = error; }
        Check.True(ReferenceEquals(expected, observed), "A native timeout must not become a driver timeout");
        var result = await campaign.OnUiAsync(() => Task.FromResult(42), pending =>
            Check.False(pending, "A synchronously completed native reply must not be marked pending"));
        Check.Equal(42, result, "A valid in-budget reply is returned unchanged");
    }
}
