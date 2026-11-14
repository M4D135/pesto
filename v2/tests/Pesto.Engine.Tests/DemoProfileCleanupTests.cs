using Pesto.App;

namespace Pesto.Engine.Tests;

internal sealed class DemoProfileCleanupTests
{
    private static string NewReport() => Directory.CreateDirectory(Path.Combine(Path.GetTempPath(),
        "Pesto-demo-cleanup-test-" + Guid.NewGuid().ToString("N"))).FullName;

    [Test]
    public void ReleasedProfileIsRetriedWithoutDeletingReportsOrSiblingDirectories()
    {
        var root = NewReport();
        try
        {
            var profile = Path.Combine(root, "coexistence", "LocalData");
            Directory.CreateDirectory(profile); File.WriteAllText(Path.Combine(profile, "held"), "fixture");
            var sibling = Path.Combine(root, "coexistence", "capture.png"); File.WriteAllText(sibling, "evidence");
            var attempts = 0;
            var result = DemoProfileCleanup.Run(root, TimeSpan.FromSeconds(2), path =>
            {
                if (++attempts == 1) throw new IOException("Synthetic Windows sharing violation", unchecked((int)0x80070020));
                Directory.Delete(path, recursive: true);
            });
            var target = result.Entries.Single(e => e.Path == "coexistence/LocalData");
            Check.True(result.Removed && !Directory.Exists(profile), "No successful proof before the released profile is actually gone");
            Check.Equal(2, target.Attempts, "Retried exactly once"); Check.Equal("removed", target.State, "Removal observed");
            Check.Equal("sharing-violation", target.LastError!, "Cause of the retry retained");
            Check.True(target.ElapsedMilliseconds > 0 && target.ElapsedMilliseconds <= result.ElapsedMilliseconds, "Completion time recorded");
            Check.True(result.Entries.Where(e => e != target).All(e => e.State == "absent" && e.Attempts == 0), "Absent private trees are identified");
            Check.Equal("evidence", File.ReadAllText(sibling), "Coexistence evidence is preserved");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void ExhaustedBudgetKeepsTheResidueAndOtherTargetsGetTheirOwnOutcome()
    {
        var root = NewReport();
        try
        {
            var browser = Directory.CreateDirectory(Path.Combine(root, "browser-profile")).FullName;
            var gp = Directory.CreateDirectory(Path.Combine(root, "coexistence", "GP")).FullName;
            var result = DemoProfileCleanup.Run(root, TimeSpan.Zero, path =>
            {
                if (path == browser) throw new UnauthorizedAccessException("Synthetic held file");
                Directory.Delete(path, true);
            });
            Check.False(result.Removed, "Remaining profile cannot be reported clean");
            var target = result.Entries.Single(e => e.Path == "browser-profile");
            Check.True(target.State == "remaining" && target.Attempts == 1 && target.LastError == "access-denied"
                && Directory.Exists(browser), "Transient access failure retained after the bounded attempt");
            Check.False(Directory.Exists(gp), "An independent temporary tree is cleaned");
            Check.Equal(3, result.ToJson()["targets"]!.AsArray().Count, "All three allowed targets reported");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void UnexpectedFileOrLinkIsPreservedAndCannotLeadOutsideTheReport()
    {
        var root = NewReport(); var outside = NewReport();
        try
        {
            var sentinel = Path.Combine(outside, "keep.txt"); File.WriteAllText(sentinel, "untouched");
            var marker = Path.Combine(root, "browser-profile"); File.WriteAllText(marker, "unexpected file");
            var localData = Directory.CreateDirectory(Path.Combine(root, "coexistence", "LocalData")).FullName;
            // Windows runners without symlink privilege still exercise the wrong-type refusal.
            if (!OperatingSystem.IsWindows())
                Directory.CreateSymbolicLink(Path.Combine(localData, "redirect"), outside);
            var result = DemoProfileCleanup.Run(root);
            Check.False(result.Removed, "Unsafe target cannot count as absent");
            Check.True(result.Entries.Single(e => e.Path == "browser-profile").State == "unsafe"
                && File.ReadAllText(marker) == "unexpected file", "Wrong-type target left alone");
            if (!OperatingSystem.IsWindows())
                Check.True(result.Entries.Single(e => e.Path == "coexistence/LocalData").State == "unsafe"
                    && Directory.Exists(localData), "Nested directory link refused before deletion");
            Check.Equal("untouched", File.ReadAllText(sentinel), "External sentinel preserved");
        }
        finally { Directory.Delete(root, true); Directory.Delete(outside, true); }
    }

    [Test]
    public void WindowsExclusiveHandleLeavesARealResidualUntilItIsReleased()
    {
        if (!OperatingSystem.IsWindows()) return;
        var root = NewReport();
        try
        {
            var profile = Directory.CreateDirectory(Path.Combine(root, "browser-profile")).FullName;
            using (File.Open(Path.Combine(profile, "held"), FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
            {
                var held = DemoProfileCleanup.Run(root, TimeSpan.FromMilliseconds(150), path => Directory.Delete(path, true));
                Check.False(held.Removed, "A still-open Windows file remains a failure");
                Check.True(held.Entries[0].State == "remaining" && held.Entries[0].Attempts >= 1, "Actual OS lock reported");
            }
            Check.True(DemoProfileCleanup.Run(root).Removed, "Released Windows tree can be removed");
        }
        finally { Directory.Delete(root, true); }
    }
}
