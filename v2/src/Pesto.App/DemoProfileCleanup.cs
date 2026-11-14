using System.Diagnostics;
using System.Text.Json.Nodes;

namespace Pesto.App;

/// <summary>Cleanup of the three private data trees of one new --qualify-demo report. No process inspection.</summary>
internal static class DemoProfileCleanup
{
    private static readonly string[] Owned = ["browser-profile", "coexistence/LocalData", "coexistence/GP"];
    private static readonly TimeSpan RetryBudget = TimeSpan.FromSeconds(6);
    private static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(100);

    internal sealed class Entry(string path)
    {
        public string Path { get; } = path;
        public int Attempts { get; set; }
        public long ElapsedMilliseconds { get; set; }
        public string State { get; set; } = "pending";
        public string? LastError { get; set; }
        public bool Removed => State is "absent" or "removed";
    }

    internal sealed record Result(Entry[] Entries, long ElapsedMilliseconds, long RetryBudgetMilliseconds)
    {
        public bool Removed => Entries.All(entry => entry.Removed);

        public JsonObject ToJson() => new()
        {
            ["elapsedMilliseconds"] = ElapsedMilliseconds, ["retryBudgetMilliseconds"] = RetryBudgetMilliseconds,
            ["targets"] = new JsonArray(Entries.Select(e => (JsonNode)new JsonObject
            {
                ["path"] = e.Path, ["state"] = e.State, ["attempts"] = e.Attempts,
                ["elapsedMilliseconds"] = e.ElapsedMilliseconds, ["lastError"] = e.LastError
            }).ToArray())
        };
    }

    internal static Result Run(string newReport) =>
        Run(newReport, RetryBudget, path => Directory.Delete(path, recursive: true));

    // Tests can reproduce a Windows sharing violation deterministically without opening WebView2.
    internal static Result Run(string newReport, TimeSpan budget, Action<string> remove)
    {
        var report = Path.TrimEndingDirectorySeparator(Path.GetFullPath(newReport));
        var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        if (report.Length <= temp.Length || !report.StartsWith(temp, OperatingSystem.IsWindows()
                ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new ArgumentException("A dedicated report under Temp is required.", nameof(newReport));
        if (budget < TimeSpan.Zero || budget > RetryBudget) throw new ArgumentOutOfRangeException(nameof(budget));
        var targets = Owned.Select(path => new Entry(path)).ToArray();
        var clock = Stopwatch.StartNew();
        while (true)
        {
            foreach (var entry in targets) Check(entry, delete: true);
            // A browser may recreate an earlier tree while another tree is being removed.
            foreach (var entry in targets) Check(entry, delete: false);
            var left = budget - clock.Elapsed;
            if (!targets.Any(entry => entry.State == "remaining") || left <= TimeSpan.Zero) break;
            Thread.Sleep(left < Interval ? left : Interval);
            // A loaded guest may resume much later than the requested sleep. Do not start a late retry.
            if (clock.Elapsed >= budget)
            {
                foreach (var entry in targets) Check(entry, delete: false);
                break;
            }
        }
        return new Result(targets, clock.ElapsedMilliseconds, (long)budget.TotalMilliseconds);

        void Check(Entry entry, bool delete)
        {
            if (entry.State == "unsafe") return;
            var before = entry.State;
            var attempts = entry.Attempts;
            try
            {
                var path = Path.Combine(report, entry.Path);
                var attributes = CheckedAttributes(path);
                if (attributes is null) entry.State = entry.Attempts > 0 ? "removed" : "absent";
                else if ((attributes & FileAttributes.Directory) == 0) throw new UnsafePathException();
                else if (delete)
                {
                    entry.Attempts++;
                    CheckTree(path);
                    remove(path);
                    entry.State = "remaining"; // Only the final observation can establish removal.
                }
                else entry.State = "remaining";
            }
            catch (UnsafePathException) { entry.State = "unsafe"; entry.LastError = "link-or-unexpected-entry"; }
            catch (UnauthorizedAccessException) { entry.State = "remaining"; entry.LastError = "access-denied"; }
            catch (IOException error)
            {
                entry.State = "remaining";
                entry.LastError = (error.HResult & 0xffff) is 32 or 33 ? "sharing-violation" : "io-error";
            }
            finally
            {
                if (entry.State != before || entry.Attempts != attempts || !entry.Removed)
                    entry.ElapsedMilliseconds = clock.ElapsedMilliseconds;
            }
        }
    }

    private sealed class UnsafePathException : Exception { }

    private static FileAttributes? CheckedAttributes(string path)
    {
        // Recheck the whole ancestor chain before each attempt, including a dangling link where Exists is false.
        if (Path.GetDirectoryName(path) is { Length: > 0 } parent)
        {
            var parentAttributes = CheckedAttributes(parent);
            if (parentAttributes is null) return null;
            if ((parentAttributes & FileAttributes.Directory) == 0) throw new UnsafePathException();
        }
        try
        {
            var attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new UnsafePathException();
            return attributes;
        }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    private static void CheckTree(string path)
    {
        // Directory.Delete(recursive) does not follow junctions. Also refuse to remove an observed link itself.
        var directories = new Stack<string>();
        directories.Push(path);
        while (directories.TryPop(out var current))
        {
            foreach (var entry in new DirectoryInfo(current).EnumerateFileSystemInfos())
            {
                var attributes = entry.Attributes;
                if ((attributes & FileAttributes.ReparsePoint) != 0) throw new UnsafePathException();
                if ((attributes & FileAttributes.Directory) != 0) directories.Push(entry.FullName);
            }
        }
    }
}
