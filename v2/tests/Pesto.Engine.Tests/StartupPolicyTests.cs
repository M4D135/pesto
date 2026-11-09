using System.ComponentModel;
using Pesto.Engine;
namespace Pesto.Engine.Tests;
public sealed class StartupPolicyTests
{
    [Test]
    public void OnlyOrdinaryUnelevatedStartupRequestsElevation()
    {
        Check.True(StartupPolicy.NeedsElevation(false, false, false), "Normal startup asks Windows for UAC at once");
        Check.False(StartupPolicy.NeedsElevation(false, false, true), "The elevated relay continues without another prompt");
        Check.False(StartupPolicy.NeedsElevation(true, false, false), "Demo stays isolated");
        Check.False(StartupPolicy.NeedsElevation(false, true, false), "Explicit settings remain available without elevation");
    }
    [Test]
    public void ElevationStartsOnceWithoutAnyPrompt()
    {
        var starts = 0; var prompts = 0;
        Check.Equal(0, StartupPolicy.Elevate(() => starts++, _ => { prompts++; return true; }), "Started relay");
        Check.Equal(1, starts, "One UAC request"); Check.Equal(0, prompts, "No dialog before or after consent");
    }
    [Test]
    public void CancelledElevationAsksBeforeEachRetry()
    {
        var starts = 0; var messages = new List<string>();
        var code = StartupPolicy.Elevate(() => { if (++starts < 3) throw new Win32Exception(1223); },
            message => { messages.Add(message); return true; });
        Check.Equal(0, code, "Third request started the relay");
        Check.Equal(3, starts, "Each retry is one explicit request");
        Check.Equal(2, messages.Count, "One choice per cancellation");
        Check.True(messages.All(m => m == StartupPolicy.CancelledMessage), "Cancellation is named as such");
    }
    [Test]
    public void ClosingAfterCancellationOrFailureStopsWithoutAnotherRequest()
    {
        var starts = 0;
        Check.Equal(0, StartupPolicy.Elevate(() => { starts++; throw new Win32Exception(1223); }, _ => false), "Closing a cancelled request is not a failure");
        Check.Equal(1, starts, "No request after Close");
        starts = 0; string? shown = null;
        Check.Equal(2, StartupPolicy.Elevate(() => { starts++; throw new IOException("synthetic"); }, m => { shown = m; return false; }), "Closing a failed request fails");
        Check.Equal(1, starts, "No request after Close");
        Check.Equal(StartupPolicy.FailedMessage, shown, "Failure is named without internal details");
    }
    [Test]
    public void UnexpectedErrorsAreNotTurnedIntoRetries()
    {
        var thrown = false;
        try { StartupPolicy.Elevate(() => throw new ArgumentException("synthetic"), _ => true); }
        catch (ArgumentException) { thrown = true; }
        Check.True(thrown, "Only Windows elevation failures offer Retry");
    }
}
