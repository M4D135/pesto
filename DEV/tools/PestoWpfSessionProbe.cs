// Isolated WPF/XAML lifecycle probe. It does not load the Pesto engine or business handlers.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Threading;

public static class PestoWpfSessionProbe
{
    public sealed class Snapshot
    {
        public int CompletedCycles;
        public int TrackedWindows;
        public int LiveWindowReferences;
        public long ManagedBytes;
        public long PrivateBytes;
        public long WorkingSet;
        public int Handles;
        public int Threads;
        public double ElapsedSeconds;
    }
    public sealed class Result
    {
        public int WarmupCycles;
        public int RequestedCycles;
        public int CompletedCycles;
        public string StopReason;
        public int MinimumDurationSeconds;
        public int MaxCycles;
        public double WorkloadSeconds;
        public Snapshot BeforeWarmup;
        public List<Snapshot> Samples = new List<Snapshot>();
    }
    // A separate stack frame prevents the last Window local being retained by the caller during GC.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference Cycle(string xaml)
    {
        Window window = (Window)XamlReader.Parse(xaml);
        try
        {
            window.ShowInTaskbar = false;
            window.ShowActivated = false;
            window.Opacity = 0;
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -32000;
            window.Top = -32000;
            window.Width = 1000;
            window.Height = 700;
            window.Show();
            TabControl tabs = window.FindName("MainTabs") as TabControl;
            if (tabs == null || tabs.Items.Count != 8)
                throw new InvalidOperationException("Expected eight shell pages.");
            for (int page = 0; page < tabs.Items.Count; page++)
            {
                tabs.SelectedIndex = page;
                window.UpdateLayout();
                window.Dispatcher.Invoke(DispatcherPriority.ApplicationIdle, new Action(delegate { }));
                if (tabs.SelectedIndex != page)
                    throw new InvalidOperationException("Page selection did not settle.");
            }
            return new WeakReference(window);
        }
        finally { window.Close(); }
    }
    private static Snapshot Measure(int completed, List<WeakReference> references, Stopwatch watch)
    {
        Dispatcher.CurrentDispatcher.Invoke(DispatcherPriority.ApplicationIdle, new Action(delegate { }));
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        int live = 0;
        foreach (WeakReference reference in references) if (reference.IsAlive) live++;
        using (Process process = Process.GetCurrentProcess())
        {
            process.Refresh();
            return new Snapshot {
                CompletedCycles = completed, TrackedWindows = references.Count, LiveWindowReferences = live,
                ManagedBytes = GC.GetTotalMemory(false), PrivateBytes = process.PrivateMemorySize64,
                WorkingSet = process.WorkingSet64, Handles = process.HandleCount, Threads = process.Threads.Count,
                ElapsedSeconds = Math.Round(watch.Elapsed.TotalSeconds, 3)
            };
        }
    }
    public static Result Run(string xaml, int cycles, int warmup, int every, int durationSeconds, int minimumDurationSeconds, int maxCycles)
    {
        if (cycles < 1 || cycles > 500 || warmup < 1 || warmup > 50 || every < 1 || every > 100 || durationSeconds < 1 || durationSeconds > 900 || minimumDurationSeconds < 0 || minimumDurationSeconds > 600 || maxCycles < cycles || maxCycles > 5000)
            throw new ArgumentOutOfRangeException("Probe bounds");
        Stopwatch watch = Stopwatch.StartNew();
        var references = new List<WeakReference>();
        var result = new Result { RequestedCycles = cycles, StopReason = "CyclesCollected", MinimumDurationSeconds = minimumDurationSeconds, MaxCycles = maxCycles };
        result.BeforeWarmup = Measure(0, references, watch);
        for (int index = 0; index < warmup; index++)
        {
            if (watch.Elapsed.TotalSeconds >= durationSeconds) { result.StopReason = "DurationLimitDuringWarmup"; break; }
            references.Add(Cycle(xaml)); result.WarmupCycles++;
        }
        result.Samples.Add(Measure(0, references, watch));
        if (result.WarmupCycles == warmup)
        {
            double workStarted = watch.Elapsed.TotalSeconds;
            for (int index = 1; index <= maxCycles; index++)
            {
                if (watch.Elapsed.TotalSeconds >= durationSeconds) { result.StopReason = "DurationLimit"; break; }
                references.Add(Cycle(xaml)); result.CompletedCycles = index;
                result.WorkloadSeconds = Math.Round(watch.Elapsed.TotalSeconds - workStarted, 3);
                if (index % every == 0) result.Samples.Add(Measure(index, references, watch));
                if (index >= cycles && result.WorkloadSeconds >= minimumDurationSeconds) break;
                if (index == maxCycles) result.StopReason = "CycleLimit";
            }
        }
        if (result.Samples[result.Samples.Count - 1].CompletedCycles != result.CompletedCycles)
            result.Samples.Add(Measure(result.CompletedCycles, references, watch));
        return result;
    }
}
