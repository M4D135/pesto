using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>
/// Bounded, best-effort diagnostics for an already validated, elevated helper.
/// A missing or incomplete trace is never a success receipt. Diagnostic I/O must
/// neither change the transaction result nor replace its original exception.
/// </summary>
internal sealed class UpdateHelperDiagnostics : IDisposable
{
    private const int MaximumEvents = 16;
    private const int MaximumLineBytes = 2048;
    private const int MaximumFileBytes = 32 * 1024;
    private static readonly HashSet<string> Phases =
    [
        "helperValidated", "waitingForParent", "parentReleased", "waitingForPackProcesses",
        "readyForExecuteCore", "result", "resultDialogClosed", "exception"
    ];
    private readonly object gate = new();
    private readonly FileStream? stream;
    private readonly string transactionId = "";
    private readonly int processId;
    private readonly string startUtcTicks = "";
    private readonly string launchId = "";
    private int sequence;
    private long writtenBytes;
    private string? previousPhase;
    private bool disabled;

    private UpdateHelperDiagnostics() { }

    private UpdateHelperDiagnostics(FileStream stream, string transactionId, int processId, string startUtcTicks, string launchId)
    {
        this.stream = stream; this.transactionId = transactionId; this.processId = processId;
        this.startUtcTicks = startUtcTicks; this.launchId = launchId;
    }

    internal static UpdateHelperDiagnostics Start(string transactionDirectory)
    {
        // The caller has already verified the helper image and elevation. The
        // trace is exclusively created in that transaction, never in a profile.
        try
        {
            var directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(transactionDirectory));
            UpdatePackage.RequireNoLinks(directory);
            using var process = Process.GetCurrentProcess();
            var ticks = process.StartTime.ToUniversalTime().Ticks.ToString(CultureInfo.InvariantCulture);
            var nonce = Guid.NewGuid().ToString("N");
            var name = "helper-diagnostic-" + process.Id.ToString(CultureInfo.InvariantCulture) + "-" + ticks + "-" + nonce + ".jsonl";
            var output = new FileStream(Path.Combine(directory, name), FileMode.CreateNew, FileAccess.Write,
                FileShare.ReadWrite | FileShare.Delete, 4096, FileOptions.WriteThrough);
            return new(output, Path.GetFileName(directory), process.Id, ticks, nonce);
        }
        catch (Exception error) when (IsDiagnosticFailure(error)) { return new(); }
    }

    internal void Record(string phase, string? status = null, Exception? error = null)
    {
        lock (gate)
        {
            if (stream is null || disabled || sequence >= MaximumEvents || !Phases.Contains(phase)) return;
            try
            {
                var record = new
                {
                    schemaVersion = 1, kind = "pesto.update-helper-diagnostic", transactionId, processId, startUtcTicks, launchId,
                    sequence = sequence + 1, utc = DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture),
                    phase, previousPhase, status = Identifier(status, 64),
                    exceptionType = Identifier(error?.GetType().FullName, 256),
                    pestoCode = Identifier((error as PestoException)?.Code, 128),
                    win32Error = NativeError(error), hresult = error?.HResult
                };
                // No messages, stacks, arguments, credentials or configuration
                // content are recorded. Every field has a fixed bound.
                var bytes = JsonSerializer.SerializeToUtf8Bytes(record);
                if (bytes.Length + 1 > MaximumLineBytes || writtenBytes + bytes.Length + 1 > MaximumFileBytes)
                { disabled = true; return; }
                stream.Write(bytes); stream.WriteByte((byte)'\n'); stream.Flush(true);
                sequence++; writtenBytes += bytes.Length + 1; previousPhase = phase;
            }
            catch (Exception failure) when (IsDiagnosticFailure(failure)) { disabled = true; }
        }
    }

    private static string? Identifier(string? value, int maximum) => value is not null && value.Length <= maximum
        && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '+' or '`' or '-') ? value : null;

    private static int? NativeError(Exception? error)
    {
        for (var depth = 0; error is not null && depth < 4; depth++, error = error.InnerException)
            if (error is Win32Exception native) return native.NativeErrorCode;
        return null;
    }

    private static bool IsDiagnosticFailure(Exception error) => error is IOException or UnauthorizedAccessException
        or ArgumentException or NotSupportedException or InvalidOperationException or System.Security.SecurityException
        or Win32Exception or PestoException;

    public void Dispose()
    {
        lock (gate)
        {
            if (disabled && stream is null) return;
            disabled = true;
            try { stream?.Dispose(); }
            catch (Exception error) when (IsDiagnosticFailure(error)) { }
        }
    }
}
