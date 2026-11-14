using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;
using Pesto.Engine;

namespace Pesto.UpdateQualification;

/// <summary>Windows-only observation/coordination of the exact helper launched by the PowerShell script.</summary>
[SupportedOSPlatform("windows")]
internal static class NativeMonitor
{
    private sealed record OwnedProcess(int Id, int ParentId, long StartUtcTicks, string Executable);
    private sealed class AttributionUnavailableException(JsonObject evidence, Exception? inner = null)
        : InvalidOperationException("A descendant cannot be attributed to this disposable pack; no process tree is stopped ("
            + Suite.Text(evidence, "reason") + ").", inner)
    {
        public JsonObject Evidence { get; } = evidence;
    }
    private static readonly HashSet<string> Terminal = ["completed", "rolledBack", "cancelled", "rollbackHealthFailed"];

    internal static JsonObject Observe(string root, string scenario, string stage, string launchFile)
    {
        using var identity = WindowsIdentity.GetCurrent();
        Suite.Require(new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator),
            "Native update qualification requires an already elevated token; UAC is never automated.");
        var suite = Suite.Load(root); var state = Suite.Case(root, scenario);
        Suite.Require(stage is "install" or "rollback" or "recovery", "Unknown native observation stage.");
        Suite.Require(Path.GetFullPath(launchFile) == Path.Combine(Suite.Evidence(root, scenario), "launch-" + stage + ".json"), "Unexpected launch receipt path.");
        var launch = Suite.Read<LaunchReceipt>(launchFile);
        Suite.Require(launch.TransactionId == state.TransactionId && launch.Executable == state.HelperExecutable
            && launch.ProcessId > 0 && long.TryParse(launch.StartUtcTicks, NumberStyles.None, CultureInfo.InvariantCulture, out _), "Launch receipt identity mismatch.");
        var startTicks = long.Parse(launch.StartUtcTicks, CultureInfo.InvariantCulture);
        using var process = Process.GetProcessById(launch.ProcessId);
        var observation = new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.native-update-observation", ["scenario"] = scenario,
            ["stage"] = stage, ["transactionId"] = state.TransactionId, ["helperProcessId"] = launch.ProcessId,
            ["helperStartUtcTicks"] = launch.StartUtcTicks, ["helperExecutableSha256"] = suite.Base.ExecutableSha256,
            ["candidateExecutableSha256"] = suite.Candidate.ExecutableSha256,
            ["journalReadPolicy"] = "owned-dialog-exit-or-attributed-checking-child",
            ["dialogDeadlinePolicy"] = "30s-from-owned-dialog-observation-through-helper-exit",
            ["success"] = false, ["interrupted"] = false, ["dialogClosed"] = false, ["checkingObserved"] = false,
            ["healthChildObserved"] = false, ["webViewChildObserved"] = false, ["events"] = new JsonArray()
        };
        var output = Path.Combine(Suite.Evidence(root, scenario), "observation-" + stage + ".json");
        var journalPath = Path.Combine(state.TransactionDirectory, "transaction.json");
        var installation = Path.Combine(Suite.CaseDirectory(root, scenario), "installation");
        var interrupt = scenario == "interruption" && stage == "install";
        var refusal = scenario == "format-refusal";
        Suite.Require(!refusal || stage == "install", "A format refusal is only observed at installation.");
        if (refusal) { observation["formatRefused"] = false; }
        var previous = ""; var dialogSent = false; var completed = false; var helperIdentityValidated = false;
        Stopwatch? terminalWait = null;
        var attributionFailures = new JsonArray();
        var attributionRefusals = 0;
        var attributionSaved = Stopwatch.StartNew();
        observation["descendantAttributionRefusals"] = attributionFailures;

        bool TryObserveDescendants(out List<OwnedProcess> owned)
        {
            try { owned = Descendants(process.Id, startTicks, Suite.CaseDirectory(root, scenario)); return true; }
            catch (AttributionUnavailableException error)
            {
                // An incomplete snapshot grants no authority to stop any process. Keep the first eight
                // and last eight refusals, then retry the entire inventory inside the existing deadline.
                owned = [];
                attributionRefusals++;
                if (attributionFailures.Count == 16) attributionFailures.RemoveAt(8);
                attributionFailures.Add(error.Evidence);
                observation["descendantAttributionRefusalCount"] = attributionRefusals;
                if (attributionRefusals == 1 || attributionSaved.Elapsed >= TimeSpan.FromSeconds(1))
                { Suite.Save(output, observation); attributionSaved.Restart(); }
                return false;
            }
        }

        void RequireHelperBeforeStop()
        {
            ValidateIdentity(process, launch, startTicks);
            UpdatePackage.RequireNoLinks(state.HelperExecutable);
            Suite.Require(UpdatePackage.Hash(state.HelperExecutable) == suite.Base.ExecutableSha256,
                "The owned helper no longer has the installed base executable hash; no process may be stopped.");
        }

        bool HasHealth(IEnumerable<OwnedProcess> owned) => owned.Any(p => p.ParentId == process.Id
            && string.Equals(p.Executable, Path.Combine(installation, "Pesto.exe"), StringComparison.OrdinalIgnoreCase));
        bool HasBrowser(IEnumerable<OwnedProcess> owned) => owned.Any(p => Path.GetFileName(p.Executable).Equals("msedgewebview2.exe", StringComparison.OrdinalIgnoreCase)
            && (Suite.Within(p.Executable, Path.Combine(installation, "wad", "runtime", "webview2")) || Suite.IsEvergreenBrowser(p.Executable)));
        try
        {
            ValidateIdentity(process, launch, startTicks);
            // GetProcessById alone does not retain a handle: .NET requires one to read ExitCode after
            // the observed process exits. Open it while the validated helper is alive and keep it until
            // this Process is disposed, including the deliberate interruption and normal-close paths.
            Suite.Require(!process.SafeHandle.IsInvalid, "Cannot retain the validated helper process handle.");
            observation["helperHandleRetained"] = true;
            Suite.Require(UpdatePackage.Hash(state.HelperExecutable) == suite.Base.ExecutableSha256, "Created helper differs from the installed base build.");
            helperIdentityValidated = true;
            var deadline = Stopwatch.StartNew();
            while (deadline.Elapsed < TimeSpan.FromSeconds(210))
            {
                var exited = process.HasExited;
                if (refusal && !dialogSent)
                {
                    Suite.Require(deadline.Elapsed < TimeSpan.FromSeconds(60),
                        "The base helper showed no identifiable refusal within 60 seconds.");
                    if (!exited)
                    {
                        ValidateIdentity(process, launch, startTicks);
                        if (TryObserveDescendants(out var owned) && (HasHealth(owned) || HasBrowser(owned)))
                        {
                            observation["healthChildObserved"] = HasHealth(owned);
                            observation["webViewChildObserved"] = HasBrowser(owned);
                            throw new InvalidOperationException("The base helper started a health check instead of refusing the pack.");
                        }
                    }
                }
                if (!exited)
                {
                    ValidateIdentity(process, launch, startTicks);
                    if (HasOwnedDialog(process))
                    {
                        if (terminalWait is null)
                        {
                            terminalWait = Stopwatch.StartNew();
                            observation["ownedDialogObservedUtc"] = DateTimeOffset.UtcNow.ToString("O");
                        }
                    }
                    else if (!interrupt)
                    {
                        if (dialogSent)
                            Suite.Require(terminalWait is not null && terminalWait.Elapsed < TimeSpan.FromSeconds(30),
                                "The helper did not exit within 30 seconds of its owned result dialog.");
                        Thread.Sleep(20);
                        continue;
                    }
                    else
                    {
                        if (!TryObserveDescendants(out var owned)) { Thread.Sleep(20); continue; }
                        if (!HasHealth(owned) || !HasBrowser(owned)) { Thread.Sleep(20); continue; }
                    }
                }
                // The legacy writer can reject an atomic replacement even when a reader grants
                // FileShare.Delete. Observe its modal result/exit, or its real health process for
                // interruption, before opening the journal. Intermediate phases are not invented.
                var journal = Suite.ReadSharedObject(journalPath);
                Suite.Require(Suite.Text(journal, "id") == state.TransactionId
                    && string.Equals(Path.GetFullPath(Suite.Text(journal, "installation")), installation, StringComparison.OrdinalIgnoreCase),
                    "Observed journal does not belong to this disposable installation.");
                var status = Suite.Text(journal, "status");
                if (status != previous)
                {
                    previous = status;
                    ((JsonArray)observation["events"]!).Add(new JsonObject { ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["journal"] = journal.DeepClone() });
                    Suite.Save(output, observation);
                }
                Suite.Require(!interrupt || !Suite.Boolean(observation, "checkingObserved") || status == "checking",
                    "Checking boundary was lost before an attributable process tree could be interrupted.");
                // The base build validates the prepared stage before its first transaction step: any other state
                // means it accepted or began replacing content, which a format refusal must never do.
                Suite.Require(!refusal || status == "prepared", "The base helper left the prepared state instead of refusing the pack.");
                if (process.HasExited)
                {
                    observation["helperExitCode"] = process.ExitCode;
                    Suite.Require(dialogSent && terminalWait is not null && terminalWait.Elapsed < TimeSpan.FromSeconds(30),
                        "The helper did not complete the owned dialog/exit handshake within 30 seconds.");
                    if (refusal)
                        Suite.Require(dialogSent && process.ExitCode != 0,
                            "Helper exited without its owned refusal dialog and a non-zero exit status.");
                    else
                        Suite.Require(!interrupt && Terminal.Contains(status) && dialogSent && process.ExitCode == 0,
                            "Helper exited without the required terminal journal, owned result dialog and zero exit status.");
                    WaitForOwnedProcessesToExit(Suite.CaseDirectory(root, scenario));
                    observation["finalJournalStatus"] = status;
                    observation["success"] = true; completed = true; break;
                }
                if (interrupt && status == "checking")
                {
                    observation["checkingObserved"] = true;
                    if (!TryObserveDescendants(out var owned)) { Thread.Sleep(20); continue; }
                    var health = HasHealth(owned); var browser = HasBrowser(owned);
                    observation["healthChildObserved"] = health;
                    observation["webViewChildObserved"] = browser;
                    if (health && browser)
                    {
                        // Re-read the complete tree, not a filtered subset of the previous snapshot.
                        if (!TryObserveDescendants(out owned)) { Thread.Sleep(20); continue; }
                        if (!HasHealth(owned) || !HasBrowser(owned)) { Thread.Sleep(20); continue; }
                        RequireHelperBeforeStop();
                        var healthExecutable = Path.Combine(installation, "Pesto.exe");
                        UpdatePackage.RequireNoLinks(healthExecutable);
                        var healthHash = UpdatePackage.Hash(healthExecutable);
                        Suite.Require(healthHash == suite.Candidate.ExecutableSha256,
                            "The observed candidate health process no longer matches build B; no process tree is stopped.");
                        Suite.Require(Suite.Text(Suite.ReadSharedObject(journalPath), "status") == "checking", "Checking boundary was lost before interruption.");
                        observation["healthExecutableSha256"] = healthHash;
                        observation["ownedTreeAtInterruption"] = System.Text.Json.JsonSerializer.SerializeToNode(owned, Suite.Json);
                        Suite.Save(output, observation); // Preserve exact identities before the deliberate failure.
                        process.Kill(entireProcessTree: true);
                        Suite.Require(process.WaitForExit(15000), "Created helper did not stop after the targeted interruption.");
                        WaitForOwnedProcessesToExit(Suite.CaseDirectory(root, scenario));
                        var after = Suite.ReadSharedObject(journalPath);
                        Suite.Require(Suite.Text(after, "status") == "checking", "Interruption did not leave the intended real checking boundary.");
                        observation["interrupted"] = true; observation["helperExitCode"] = process.ExitCode;
                        observation["finalJournalStatus"] = "checking"; observation["success"] = true;
                        Suite.Save(Path.Combine(Suite.Evidence(root, scenario), "journal-interrupted.json"), after);
                        completed = true; break;
                    }
                }
                if (refusal && !dialogSent)
                {
                    ValidateIdentity(process, launch, startTicks);
                    dialogSent = CloseOwnedRefusalDialog(process, observation);
                    observation["dialogClosed"] = dialogSent;
                }
                if (Terminal.Contains(status) && !interrupt && !dialogSent)
                {
                    ValidateIdentity(process, launch, startTicks);
                    terminalWait ??= Stopwatch.StartNew();
                    dialogSent = CloseOwnedResultDialog(process, observation);
                    observation["dialogClosed"] = dialogSent;
                    Suite.Require(dialogSent || terminalWait.Elapsed < TimeSpan.FromSeconds(30),
                        "The transaction reached its terminal state but its owned result dialog could not be identified; inspect resultWindows.");
                }
                if (dialogSent)
                    Suite.Require(terminalWait is not null && terminalWait.Elapsed < TimeSpan.FromSeconds(30),
                        "The helper did not exit within 30 seconds of its owned result dialog.");
                Thread.Sleep(20);
            }
            Suite.Require(completed, "Native helper timed out or the required interruption boundary was not observed.");
            return observation;
        }
        catch (Exception error)
        {
            observation["failure"] = error.GetType().Name + ": " + error.Message;
            // A fatal helper dialog can precede any terminal journal state. Record only this already
            // attributed process before stopping it; diagnostics never close a window or change the verdict.
            if (helperIdentityValidated)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        RequireHelperBeforeStop();
                        observation["failureDiagnostics"] = CaptureFailureDiagnostics(process, launch, startTicks,
                            Suite.CaseDirectory(root, scenario));
                        Suite.Save(output, observation);
                    }
                }
                catch (Exception diagnosticError)
                { observation["failureDiagnosticError"] = DiagnosticError(diagnosticError); }
            }
            // Failed qualification remains failed. Terminate only the process tree we created, with identity rechecked.
            try
            {
                if (!process.HasExited)
                {
                    RequireHelperBeforeStop();
                    _ = Descendants(process.Id, startTicks, Suite.CaseDirectory(root, scenario));
                    process.Kill(entireProcessTree: true);
                    Suite.Require(process.WaitForExit(15000), "The failed fixture helper did not stop after its owned interruption.");
                    WaitForOwnedProcessesToExit(Suite.CaseDirectory(root, scenario));
                    observation["failedFixtureProcessStopped"] = true;
                }
            }
            catch (AttributionUnavailableException cleanupError)
            {
                observation["stopFailure"] = cleanupError.GetType().Name;
                observation["cleanupDescendantAttributionRefusal"] = cleanupError.Evidence;
            }
            catch (Exception cleanupError) { observation["stopFailure"] = cleanupError.GetType().Name; }
            throw;
        }
        finally
        {
            if (terminalWait is not null) observation["ownedDialogElapsedMilliseconds"] = terminalWait.ElapsedMilliseconds;
            PreserveHelperDiagnostics(state.TransactionDirectory, Suite.Evidence(root, scenario), launch, observation);
            observation["finishedUtc"] = DateTimeOffset.UtcNow.ToString("O");
            Suite.Save(output, observation);
        }
    }

    private static void ValidateIdentity(Process process, LaunchReceipt launch, long ticks)
    {
        Suite.Require(!process.HasExited && process.Id == launch.ProcessId && process.StartTime.ToUniversalTime().Ticks == ticks,
            "Created helper PID/start time no longer matches; no process may be targeted.");
        var executable = process.MainModule?.FileName;
        Suite.Require(executable is not null && string.Equals(Path.GetFullPath(executable), Path.GetFullPath(launch.Executable), StringComparison.OrdinalIgnoreCase),
            "Created helper executable path cannot be verified.");
    }

    private static JsonObject DiagnosticError(Exception error) => new()
    {
        ["exceptionType"] = error.GetType().Name,
        ["nativeError"] = error is System.ComponentModel.Win32Exception native ? native.NativeErrorCode : null
    };

    private static void PreserveHelperDiagnostics(string transactionDirectory, string evidenceDirectory,
        LaunchReceipt launch, JsonObject observation)
    {
        const int maximumFiles = 8, maximumCandidates = 64, maximumBytes = 64 * 1024;
        var files = new JsonArray(); var refusals = new JsonArray();
        var collection = new JsonObject
        {
            ["helperProcessId"] = launch.ProcessId, ["helperStartUtcTicks"] = launch.StartUtcTicks,
            ["maximumFiles"] = maximumFiles, ["maximumBytesPerFile"] = maximumBytes,
            ["maximumCandidates"] = maximumCandidates, ["files"] = files, ["refusals"] = refusals,
            ["completed"] = false, ["informationalOnly"] = true
        };
        observation["helperDiagnosticCollection"] = collection;
        try
        {
            foreach (var directory in new[] { transactionDirectory, evidenceDirectory })
            {
                Suite.Require(Path.IsPathFullyQualified(directory) && !directory.StartsWith("\\\\", StringComparison.Ordinal)
                    && !directory.StartsWith("//", StringComparison.Ordinal) && !directory.Any(char.IsControl), "Nonlocal diagnostic directory.");
                Suite.Require(new DriveInfo(Path.GetPathRoot(directory)!).DriveType == DriveType.Fixed, "Diagnostic directory is not local.");
                UpdatePackage.RequireNoLinks(directory);
            }
            var pattern = new Regex("^helper-diagnostic-" + launch.ProcessId.ToString(CultureInfo.InvariantCulture)
                + "-" + Regex.Escape(launch.StartUtcTicks) + "-[0-9a-f]{32}\\.jsonl$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
            var candidates = 0; var matched = 0;
            foreach (var source in Directory.EnumerateFiles(transactionDirectory, "helper-diagnostic-*", SearchOption.TopDirectoryOnly))
            {
                if (++candidates > maximumCandidates) { collection["candidateLimitReached"] = true; break; }
                var name = Path.GetFileName(source);
                if (!pattern.IsMatch(name)) continue;
                if (++matched > maximumFiles) { collection["fileLimitReached"] = true; break; }
                try
                {
                    Suite.Require(string.Equals(Path.GetDirectoryName(Path.GetFullPath(source)), Path.GetFullPath(transactionDirectory),
                        StringComparison.OrdinalIgnoreCase), "Diagnostic file leaves the transaction directory.");
                    UpdatePackage.RequireNoLinks(source);
                    using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    var length = input.Length;
                    Suite.Require(length <= maximumBytes, "Diagnostic file exceeds the bounded copy size.");
                    var bytes = new byte[(int)length];
                    input.ReadExactly(bytes);
                    var sourceLengthAfterRead = input.Length;
                    var destination = Path.Combine(evidenceDirectory, name);
                    UpdatePackage.RequireNoLinks(destination);
                    using (var copy = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
                    { copy.Write(bytes); copy.Flush(flushToDisk: true); }
                    files.Add(new JsonObject
                    {
                        ["file"] = name, ["copiedBytes"] = bytes.Length, ["sourceBytesAfterRead"] = sourceLengthAfterRead,
                        ["snapshotMayBeIncomplete"] = sourceLengthAfterRead != length || bytes.Length > 0 && bytes[^1] != (byte)'\n',
                        ["sha256"] = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()
                    });
                }
                catch (Exception error)
                {
                    var refusal = DiagnosticError(error); refusal["file"] = name; refusals.Add(refusal);
                }
            }
            collection["scannedCandidates"] = Math.Min(candidates, maximumCandidates);
            collection["copiedFiles"] = files.Count;
            collection["completed"] = true;
        }
        catch (Exception error) { collection["collectionError"] = DiagnosticError(error); }
    }

    private static JsonObject CaptureFailureDiagnostics(Process process, LaunchReceipt launch, long startTicks, string caseDirectory)
    {
        const int maximumThreads = 64, maximumWindows = 16, maximumControls = 32, maximumText = 1024;
        ValidateIdentity(process, launch, startTicks);
        var threads = new JsonArray(); var windows = new JsonArray();
        var result = new JsonObject
        {
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["helperProcessId"] = process.Id,
            ["helperStartUtcTicks"] = launch.StartUtcTicks, ["identityRevalidated"] = true,
            ["informationalOnly"] = true, ["maximumThreads"] = maximumThreads, ["maximumWindows"] = maximumWindows,
            ["maximumControls"] = maximumControls, ["maximumControlTextCharacters"] = maximumText,
            ["threads"] = threads, ["windows"] = windows
        };
        try
        {
            var descendants = Descendants(process.Id, startTicks, caseDirectory);
            result["descendantCount"] = descendants.Count;
            result["descendants"] = System.Text.Json.JsonSerializer.SerializeToNode(descendants.Take(64).ToArray(), Suite.Json);
            result["descendantsTruncated"] = descendants.Count > 64;
        }
        catch (AttributionUnavailableException error) { result["descendantAttributionRefusal"] = error.Evidence; }
        catch (Exception error) { result["descendantError"] = DiagnosticError(error); }
        var threadIds = new List<uint>();
        try
        {
            var available = process.Threads;
            result["threadCount"] = available.Count; result["threadsTruncated"] = available.Count > maximumThreads;
            for (var index = 0; index < Math.Min(available.Count, maximumThreads); index++)
            {
                using var thread = available[index];
                var entry = new JsonObject(); threads.Add(entry);
                try
                {
                    entry["id"] = thread.Id; threadIds.Add((uint)thread.Id);
                    var state = thread.ThreadState; entry["state"] = state.ToString();
                    if (state == System.Diagnostics.ThreadState.Wait) entry["waitReason"] = thread.WaitReason.ToString();
                }
                catch (Exception error) { entry["inspectionError"] = DiagnosticError(error); }
            }
        }
        catch (Exception error) { result["threadError"] = DiagnosticError(error); }
        var seen = new HashSet<IntPtr>(); var controlsRead = 0;
        var windowBudget = Stopwatch.StartNew();
        bool WithinWindowBudget() => windowBudget.ElapsedMilliseconds < 2000;
        EnumWindowsCallback inspect = (window, parameter) =>
        {
            if (!WithinWindowBudget() || windows.Count >= maximumWindows) return false;
            if (!seen.Add(window)) return true;
            var threadId = GetWindowThreadProcessId(window, out var owner);
            if (owner != process.Id || process.HasExited) return true;
            var title = new StringBuilder(256); var type = new StringBuilder(80);
            _ = GetWindowText(window, title, title.Capacity); _ = GetClassName(window, type, type.Capacity);
            var controls = new JsonArray();
            windows.Add(new JsonObject
            {
                ["handle"] = window.ToInt64().ToString(CultureInfo.InvariantCulture), ["threadId"] = threadId,
                ["class"] = type.ToString(), ["title"] = title.ToString(), ["controls"] = controls
            });
            EnumWindowsCallback inspectChild = (child, childParameter) =>
            {
                if (!WithinWindowBudget() || controlsRead >= maximumControls) return false;
                _ = GetWindowThreadProcessId(child, out var childOwner);
                if (childOwner != process.Id || process.HasExited) return true;
                var childType = new StringBuilder(80); _ = GetClassName(child, childType, childType.Capacity);
                // Fatal/runtime dialogs expose their message in Static controls. Never inspect edit fields,
                // credentials, another process's text, stacks, memory, command lines or environment variables.
                if (childType.ToString() is not ("Static" or "Button")) return true;
                controlsRead++;
                var text = new StringBuilder(maximumText + 1);
                var timeout = (uint)Math.Clamp(2000 - windowBudget.ElapsedMilliseconds, 1, 100);
                var read = SendMessageTimeout(child, 0x000D, (IntPtr)text.Capacity, text, 0x0023, timeout, out var characters); // WM_GETTEXT, bounded/abort-if-hung.
                _ = GetWindowThreadProcessId(child, out childOwner);
                if (childOwner != process.Id || process.HasExited) return true;
                controls.Add(new JsonObject
                {
                    ["handle"] = child.ToInt64().ToString(CultureInfo.InvariantCulture), ["class"] = childType.ToString(),
                    ["textReadSucceeded"] = read != IntPtr.Zero, ["text"] = read != IntPtr.Zero ? text.ToString() : null,
                    ["textTruncated"] = read != IntPtr.Zero && characters.ToInt64() >= maximumText
                });
                return true;
            };
            _ = EnumChildWindows(window, inspectChild, IntPtr.Zero);
            return true;
        };
        try
        {
            _ = EnumWindows(inspect, IntPtr.Zero);
            foreach (var threadId in threadIds)
            {
                if (!WithinWindowBudget() || windows.Count >= maximumWindows) break;
                _ = EnumThreadWindows(threadId, inspect, IntPtr.Zero);
            }
        }
        catch (Exception error) { result["windowError"] = DiagnosticError(error); }
        result["windowBudgetExhausted"] = !WithinWindowBudget();
        result["windowLimitReached"] = windows.Count >= maximumWindows;
        result["controlLimitReached"] = controlsRead >= maximumControls;
        return result;
    }

    private static List<OwnedProcess> Descendants(int parentId, long parentStartTicks, string caseDirectory)
    {
        Dictionary<int, int> parents;
        try { parents = SnapshotParents(); }
        catch (Exception error) when (error is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            throw new AttributionUnavailableException(new JsonObject
            {
                ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["reason"] = "process-snapshot-incomplete",
                ["helperProcessId"] = parentId, ["helperStartUtcTicks"] = parentStartTicks.ToString(CultureInfo.InvariantCulture),
                ["exceptionType"] = error.GetType().Name,
                ["nativeError"] = error is System.ComponentModel.Win32Exception native ? native.NativeErrorCode : null
            }, error);
        }
        var descendants = new HashSet<int> { parentId };
        var changed = true;
        while (changed)
        {
            changed = false;
            foreach (var pair in parents)
                if (descendants.Contains(pair.Value) && descendants.Add(pair.Key)) changed = true;
        }
        var result = new List<OwnedProcess>();
        AttributionUnavailableException Refuse(string reason, int id, long? start, string? path, Exception? error = null)
        {
            // Only process metadata is recorded. Never read/hash an image outside the disposable pack,
            // and never admit a system process merely because its name resembles a known helper.
            var chain = new JsonArray(); var seen = new HashSet<int>(); var cursor = id;
            while (seen.Add(cursor) && parents.TryGetValue(cursor, out var ancestor) && chain.Count < 64)
            {
                chain.Add(new JsonObject { ["processId"] = cursor, ["parentId"] = ancestor });
                if (cursor == parentId) break;
                cursor = ancestor;
            }
            return new(new JsonObject
            {
                ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["reason"] = reason,
                ["helperProcessId"] = parentId, ["helperStartUtcTicks"] = parentStartTicks.ToString(CultureInfo.InvariantCulture),
                ["processId"] = id, ["snapshotParentId"] = parents.GetValueOrDefault(id),
                ["startUtcTicks"] = start?.ToString(CultureInfo.InvariantCulture), ["imagePath"] = path,
                ["exceptionType"] = error?.GetType().Name, ["snapshotAncestry"] = chain
            }, error);
        }
        foreach (var id in descendants.Where(id => id != parentId))
        {
            long? start = null; string? path = null;
            try
            {
                using var process = Process.GetProcessById(id);
                if (process.HasExited) throw Refuse("descendant-exited-during-snapshot", id, start, path);
                start = process.StartTime.ToUniversalTime().Ticks; path = process.MainModule?.FileName;
                if (start < parentStartTicks) throw Refuse("descendant-starts-before-helper", id, start, path);
                if (path is null) throw Refuse("descendant-image-unavailable", id, start, path);
                if (!Suite.Within(path, caseDirectory) && !Suite.IsEvergreenBrowser(path)) throw Refuse("descendant-image-outside-case", id, start, path);
                result.Add(new(id, parents[id], start.Value, path));
            }
            catch (AttributionUnavailableException) { throw; }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
            { throw Refuse("descendant-identity-unavailable", id, start, path, error); }
        }
        foreach (var child in result)
        {
            var parent = result.FirstOrDefault(p => p.Id == child.ParentId);
            if (parent is not null && parent.StartUtcTicks > child.StartUtcTicks)
                throw Refuse("parent-starts-after-child", child.Id, child.StartUtcTicks, child.Executable);
        }
        return result;
    }

    private static bool ProcessExists(int id)
    {
        try { using var process = Process.GetProcessById(id); return !process.HasExited; }
        catch (ArgumentException) { return false; }
    }

    private static void WaitForOwnedProcessesToExit(string caseDirectory)
    {
        for (var attempt = 0; attempt < 300; attempt++)
        {
            var busy = false;
            foreach (var name in new[] { "Pesto", "msedgewebview2" })
            foreach (var process in Process.GetProcessesByName(name))
            using (process)
            {
                if (process.HasExited) continue;
                try
                {
                    var path = process.MainModule?.FileName;
                    Suite.Require(path is not null, "An active Pesto/WebView2 process identity cannot be inspected.");
                    if (Suite.Within(path!, caseDirectory)) busy = true;
                }
                catch (InvalidOperationException) when (!ProcessExists(process.Id)) { }
            }
            if (!busy) return;
            Thread.Sleep(100);
        }
        throw new InvalidOperationException("Processes still use the disposable pack; recovery/cleanup is not qualified.");
    }

    private static bool HasOwnedDialog(Process process)
    {
        var found = false;
        var seen = new HashSet<IntPtr>();
        EnumWindowsCallback inspect = (window, parameter) =>
        {
            if (!seen.Add(window)) return true;
            _ = GetWindowThreadProcessId(window, out var owner);
            if (owner != process.Id) return true;
            var type = new StringBuilder(80);
            _ = GetClassName(window, type, type.Capacity);
            if (type.ToString() != "#32770") return true;
            found = true;
            return false;
        };
        try
        {
            if (process.HasExited) return false;
            _ = EnumWindows(inspect, IntPtr.Zero);
            if (!found)
                foreach (ProcessThread thread in process.Threads)
                using (thread)
                {
                    _ = EnumThreadWindows((uint)thread.Id, inspect, IntPtr.Zero);
                    if (found) break;
                }
        }
        catch (InvalidOperationException) when (process.HasExited) { return false; }
        return found;
    }

    private static bool CloseOwnedResultDialog(Process process, JsonObject observation)
    {
        var closed = false;
        var seen = new HashSet<IntPtr>();
        var windows = new JsonArray();
        EnumWindowsCallback inspect = (window, parameter) =>
        {
            if (!seen.Add(window)) return true;
            _ = GetWindowThreadProcessId(window, out var owner);
            if (owner != process.Id) return true;
            var title = new StringBuilder(256); var type = new StringBuilder(80);
            _ = GetWindowText(window, title, title.Capacity); _ = GetClassName(window, type, type.Capacity);
            var ok = GetDlgItem(window, 1);
            windows.Add(new JsonObject { ["handle"] = window.ToInt64().ToString(CultureInfo.InvariantCulture),
                ["class"] = type.ToString(), ["title"] = title.ToString(), ["hasIdOk"] = ok != IntPtr.Zero });
            if (type.ToString() != "#32770" || title.ToString() != "Pesto \u2014 Mise \u00e0 jour") return true;
            // MaintenanceHost shows this exact terminal result with MessageBoxButtons.OK. On the observed
            // Windows runner the dialog has no child with IDOK, although its PID/title/class match. Closing
            // that result window is the normal Close action; it cannot accept the differently titled recovery
            // confirmation and is never sent before a terminal journal. The process must still exit normally.
            closed = PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE, only this owned terminal result dialog.
            if (closed) observation["resultDialogCloseMethod"] = "WM_CLOSE";
            return !closed;
        };
        _ = EnumWindows(inspect, IntPtr.Zero);
        if (!closed)
        {
            // A CI console and its GUI child need not enumerate the same desktop through EnumWindows.
            // Enumerate only the already validated process's threads; the exact PID/title/class gate is unchanged.
            foreach (ProcessThread thread in process.Threads)
            using (thread)
            {
                _ = EnumThreadWindows((uint)thread.Id, inspect, IntPtr.Zero);
                if (closed) break;
            }
        }
        observation["resultWindows"] = windows;
        return closed;
    }

    /// <summary>
    /// Closes only the fatal "Pesto v2" dialog of this validated helper whose message is the base validator's refusal
    /// of one exact DEV source unknown to it. Any other dialog (another file, another error) is left open and fails.
    /// </summary>
    private static bool CloseOwnedRefusalDialog(Process process, JsonObject observation)
    {
        const string prefix = "Fichier hors du contenu autoris\u00e9 : ";
        var closed = false;
        var seen = new HashSet<IntPtr>();
        var windows = new JsonArray();
        EnumWindowsCallback inspect = (window, parameter) =>
        {
            if (!seen.Add(window)) return true;
            _ = GetWindowThreadProcessId(window, out var owner);
            if (owner != process.Id) return true;
            var title = new StringBuilder(256); var type = new StringBuilder(80);
            _ = GetWindowText(window, title, title.Capacity); _ = GetClassName(window, type, type.Capacity);
            var texts = new JsonArray();
            windows.Add(new JsonObject { ["handle"] = window.ToInt64().ToString(CultureInfo.InvariantCulture),
                ["class"] = type.ToString(), ["title"] = title.ToString(), ["staticTexts"] = texts });
            if (type.ToString() != "#32770" || title.ToString() != "Pesto v2") return true;
            string? message = null;
            EnumWindowsCallback inspectChild = (child, childParameter) =>
            {
                _ = GetWindowThreadProcessId(child, out var childOwner);
                if (childOwner != process.Id) return true;
                var childType = new StringBuilder(80); _ = GetClassName(child, childType, childType.Capacity);
                if (childType.ToString() != "Static") return true; // Never read edit fields or another process's text.
                var text = new StringBuilder(1025);
                if (SendMessageTimeout(child, 0x000D, (IntPtr)text.Capacity, text, 0x0023, 100, out _) == IntPtr.Zero) return true;
                texts.Add(text.ToString());
                if (text.ToString().StartsWith(prefix, StringComparison.Ordinal)) message = text.ToString();
                return true;
            };
            _ = EnumChildWindows(window, inspectChild, IntPtr.Zero);
            if (message is null || !UpdatePackage.DevExactSourcePaths.Contains(message[prefix.Length..])) return true;
            closed = PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE: the OK-only fatal dialog's normal close.
            if (closed)
            {
                observation["refusalMessage"] = message; observation["refusedPath"] = message[prefix.Length..];
                observation["formatRefused"] = true; observation["resultDialogCloseMethod"] = "WM_CLOSE";
            }
            return !closed;
        };
        _ = EnumWindows(inspect, IntPtr.Zero);
        if (!closed)
            foreach (ProcessThread thread in process.Threads)
            using (thread)
            {
                _ = EnumThreadWindows((uint)thread.Id, inspect, IntPtr.Zero);
                if (closed) break;
            }
        observation["resultWindows"] = windows;
        return closed;
    }

    private static Dictionary<int, int> SnapshotParents()
    {
        using var snapshot = CreateToolhelp32Snapshot(2, 0);
        Suite.Require(!snapshot.IsInvalid, "Cannot inspect process parent identities.");
        var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>(), Executable = "" };
        var result = new Dictionary<int, int>();
        if (!Process32First(snapshot, ref entry)) throw new InvalidOperationException("Cannot enumerate process identities.");
        do { result[(int)entry.ProcessId] = (int)entry.ParentProcessId; } while (Process32Next(snapshot, ref entry));
        var error = Marshal.GetLastWin32Error();
        if (error != 18) // ERROR_NO_MORE_FILES is the only complete end of the Toolhelp enumeration.
            throw new System.ComponentModel.Win32Exception(error, "Cannot complete the process identity snapshot.");
        return result;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        public uint Size; public uint Usage; public uint ProcessId; public UIntPtr DefaultHeapId; public uint ModuleId;
        public uint Threads; public uint ParentProcessId; public int PriorityClass; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Executable;
    }
    private sealed class SnapshotHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SnapshotHandle() : base(true) { }
        protected override bool ReleaseHandle() => CloseHandle(handle);
    }
    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern SnapshotHandle CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "Process32FirstW")]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Process32First(SnapshotHandle snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "Process32NextW")]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Process32Next(SnapshotHandle snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool EnumThreadWindows(uint threadId, EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool EnumChildWindows(IntPtr parent, EnumWindowsCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr SendMessageTimeout(IntPtr window,
        uint message, IntPtr wParam, StringBuilder text, uint flags, uint timeoutMilliseconds, out IntPtr result);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr window, int item);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
