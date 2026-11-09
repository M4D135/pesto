using System.Diagnostics;
using System.Diagnostics.Tracing;

namespace Pesto.Engine;

/// <summary>Opt-in ETW/EventPipe timings. Only fixed operation/phase names and milliseconds are emitted.</summary>
[EventSource(Name = "Pesto-DirectoryRead", Guid = "b705d7fc-108d-4e8d-9150-8191fb15936a")]
public sealed class DirectoryReadEvents : EventSource
{
    public static readonly DirectoryReadEvents Log = new();
    private DirectoryReadEvents() : base(EventSourceSettings.EtwSelfDescribingEventFormat) { }

    [NonEvent]
    public Measurement Measure(string operation, string phase) => IsEnabled() && IsMeasured(operation)
        ? new(operation, phase, Stopwatch.GetTimestamp()) : default;

    private static bool IsMeasured(string op) => op is "session.info" or "dashboard.read" or "directory.sites" or
        "directory.services" or "names.preview" or "dc" or "sites" or "siteServices" or "automationNames" or "reader";

    [Event(1, Level = EventLevel.Informational)]
    public void Duration(string operation, string phase, double milliseconds) => WriteEvent(1, operation, phase, milliseconds);

    public readonly struct Measurement : IDisposable
    {
        private readonly string? operation, phase;
        private readonly long start;
        internal Measurement(string operation, string phase, long start) => (this.operation, this.phase, this.start) = (operation, phase, start);
        public bool Enabled => operation is not null;
        public void Mark(string name)
        {
            if (operation is not null) Log.Duration(operation, name, Stopwatch.GetElapsedTime(start).TotalMilliseconds);
        }
        public void Dispose() { if (phase is not null) Mark(phase); }
    }
}
