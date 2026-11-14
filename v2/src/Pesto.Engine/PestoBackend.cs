using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Single entry point that builds the authoritative engine behind the closed bridge.
/// The simulation is an isolated in-memory world; the live adapter only reports facts it can actually observe.
/// </summary>
public static class PestoBackend
{
    /// <summary>In-memory, clearly labelled demonstration. Never touches AD, disk, WMI or the network.</summary>
    public static IPestoBackend CreateSimulation(TimeProvider? clock = null) => new SimulationBackend(clock ?? TimeProvider.System);

    /// <summary>
    /// Real adapter without a directory reader: the local identity is observed, the V1 configuration is read from the
    /// installation path passed in, and every directory read is refused with an actionable reason. It never fabricates a
    /// fact and never enables writes implicitly.
    /// </summary>
    public static IPestoBackend CreateLive(string? v1InstallationPath = null) => new LiveBackend(v1InstallationPath, null, null, TimeProvider.System, null);

    /// <summary>Local settings/help only. No directory, mutation or credential provider is constructed.</summary>
    public static IPestoBackend CreateConfigurationOnly(string? configurationRoot, string? gpRoot = null)
        => new ConfigurationOnlyBackend(configurationRoot, gpRoot);

    /// <summary>
    /// Real adapter wired to a read-only directory gateway (the transient Windows PowerShell 5.1 adapter in production,
    /// a controlled fixture in qualification tests). The gateway observes facts; the engine remains the only authority.
    /// This overload never enables writes; the configured Windows host uses the mutation overload below.
    /// </summary>
    public static IPestoBackend CreateLive(string? v1InstallationPath, IDirectoryGateway gateway) => new LiveBackend(v1InstallationPath, gateway, null, TimeProvider.System, null);

    /// <summary>
    /// Configured Windows-host entry point: injects the native adapter behind the same fresh plans,
    /// exact confirmations, consume-before-send, durable receipts and re-read-after-send pipeline.
    /// The bridge cannot replace adapters. Availability is separate from Windows/AD qualification evidence.
    /// </summary>
    public static IPestoBackend CreateLive(string? v1InstallationPath, IDirectoryGateway gateway, IMutationGateway mutation)
        => new LiveBackend(v1InstallationPath, gateway, mutation, TimeProvider.System, null);

    /// <summary>Same injectable entry with a controllable clock, so preview and plan expiry can be exercised in tests.</summary>
    public static IPestoBackend CreateLive(string? v1InstallationPath, IDirectoryGateway gateway, IMutationGateway? mutation, TimeProvider clock)
        => new LiveBackend(v1InstallationPath, gateway, mutation, clock, null);

    /// <summary>
    /// Qualification entry with an explicit durable-history root (the GP folder: V1 Interventions ledger plus the
    /// adapter's durable receipts). On the ordinary host path this stays null and the engine derives %ProgramData%\GP
    /// on Windows only — never a fabricated folder on other systems, where durable history honestly reports "unknown".
    /// </summary>
    public static IPestoBackend CreateLive(string? v1InstallationPath, IDirectoryGateway gateway, IMutationGateway? mutation, TimeProvider clock, string? gpRoot)
        => new LiveBackend(v1InstallationPath, gateway, mutation, clock, gpRoot);
}
