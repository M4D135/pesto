using System.Reflection;

namespace Pesto.Engine;

/// <summary>Version shown as « moteur » by session.info: the one Directory.Build.props stamps into this build, which
/// the pack manifest carries too. Build metadata after '+' is dropped; an unstamped build says so instead of a number.</summary>
public static class EngineVersion
{
    public static string Current { get; } = Format(
        typeof(EngineVersion).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
        typeof(EngineVersion).Assembly.GetName().Version);

    internal static string Format(string? informational, Version? version)
    {
        var stamped = informational?.Split('+', 2)[0].Trim();
        if (!string.IsNullOrEmpty(stamped)) return stamped;
        return version is null ? "inconnue" : version.Build >= 0 ? version.ToString(3) : version.ToString();
    }
}
