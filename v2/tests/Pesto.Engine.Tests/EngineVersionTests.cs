using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pesto.Engine.Tests;

/// <summary>The « moteur » label is the stamped build version shared with the pack, never a hardcoded string.</summary>
internal sealed class EngineVersionTests
{
    private static string V2Root()
    {
        for (DirectoryInfo? ancestor = new DirectoryInfo(AppContext.BaseDirectory); ancestor is not null; ancestor = ancestor.Parent)
            if (File.Exists(Path.Combine(ancestor.FullName, "Directory.Build.props"))
                && File.Exists(Path.Combine(ancestor.FullName, "tools", "pack", "pack-manifest.json")))
                return ancestor.FullName;
        throw new TestFailureException("Directory.Build.props et tools/pack/pack-manifest.json sont requis pour comparer les versions.");
    }

    [Test]
    public void EngineVersionIsTheStampedBuildAndPackVersion()
    {
        var root = V2Root();
        var stamped = Regex.Match(File.ReadAllText(Path.Combine(root, "Directory.Build.props")), "<Version>([^<]+)</Version>").Groups[1].Value;
        using var pack = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "tools", "pack", "pack-manifest.json")));
        Check.Equal(stamped, EngineVersion.Current, "Engine label comes from the build stamp");
        Check.Equal(pack.RootElement.GetProperty("version").GetString(), EngineVersion.Current, "Engine label matches the pack version");
        Check.False(EngineVersion.Current.Contains('+', StringComparison.Ordinal)
            || EngineVersion.Current.Contains("dev", StringComparison.OrdinalIgnoreCase), "No build metadata or development label");
    }

    [Test]
    public void EverySessionReportsTheEngineVersion()
    {
        Check.Equal(EngineVersion.Current, Harness.Str(Harness.Call(PestoBackend.CreateSimulation(), "session.info"), "version"), "Demo engine");
        var path = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var local = PestoBackend.CreateConfigurationOnly(path, Harness.IsolatedGpRoot());
        Check.Equal(EngineVersion.Current, Harness.Str(Harness.Call(local, "session.info"), "version"), "Real engine, local configuration");
    }

    [Test]
    public void BuildMetadataIsDroppedAndAMissingStampIsNamed()
    {
        Check.Equal("2.0.3", EngineVersion.Format("2.0.3+c4c3d671aa6bf3fe7454d8d67b4ba6f231b3262f", new Version(2, 0, 3, 0)), "Source revision dropped");
        Check.Equal("2.0.3", EngineVersion.Format("2.0.3", null), "Informational version kept");
        Check.Equal("2.0.3", EngineVersion.Format(null, new Version(2, 0, 3, 0)), "Assembly version as fallback");
        Check.Equal("2.0.3", EngineVersion.Format(" +abc", new Version(2, 0, 3, 0)), "Metadata-only stamp falls back");
        Check.Equal("2.0", EngineVersion.Format(null, new Version(2, 0)), "Short assembly version kept whole");
        Check.Equal("inconnue", EngineVersion.Format(null, null), "No invented number");
    }
}
