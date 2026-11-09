using System.Globalization;
using System.Text.RegularExpressions;

namespace Pesto.Engine;

/// <summary>Read-only observation from the explicitly selected DC. A null offset is unknown, never zero.</summary>
public sealed record ClockSkewObservation(string? Server, DateTimeOffset ObservedUtc, double? OffsetSeconds, string? ReasonCode = null);

public interface IClockSkewReader
{
    ClockSkewObservation ReadClockSkew(string server);
}

public sealed record JoinClockCheck(string State, string Message, string? Server, DateTimeOffset ObservedUtc, double? OffsetSeconds, bool Blocked);

public interface IJoinClockDisclosure
{
    JoinClockCheck? LastJoinClockCheck { get; }
}

/// <summary>V1 rule: only a finite, measured absolute skew of at least 300 seconds blocks. Unknown is a warning.</summary>
public static class JoinClockGuard
{
    public const double MaximumAllowedSkewSeconds = 300;
    private static readonly Regex Sample = new(@"(?m),\s*([+-]\d+(?:[.,]\d+)?)s\s*$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    public static bool IsServer(string? server) => server is { Length: > 0 and <= 253 }
        && Regex.IsMatch(server, @"\A[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);

    public static ClockSkewObservation Parse(string server, int exitCode, string output, DateTimeOffset now)
    {
        if (!IsServer(server) || exitCode != 0 || output.Length > 65536) return new(server, now, null, "clock.response_invalid");
        var matches = Sample.Matches(output);
        if (matches.Count != 1 || !double.TryParse(matches[0].Groups[1].Value.Replace(',', '.'), NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture, out var offset) || !double.IsFinite(offset)) return new(server, now, null, "clock.response_invalid");
        return new(server, now, offset);
    }

    public static JoinClockCheck Observe(IClockSkewReader? reader, string? server, TimeProvider? clock = null)
    {
        var now = (clock ?? TimeProvider.System).GetUtcNow();
        if (!IsServer(server)) return Unknown(server, now, "Contrôleur de domaine sélectionné non confirmé.");
        if (reader is null) return Unknown(server, now, "Lecteur d’horloge indisponible.");
        try
        {
            var observed = reader.ReadClockSkew(server!);
            if (observed is null || !string.Equals(server, observed.Server, StringComparison.OrdinalIgnoreCase)
                || observed.ObservedUtc > now.AddSeconds(15) || observed.ObservedUtc < now.AddSeconds(-30)
                || observed.OffsetSeconds is not { } offset || !double.IsFinite(offset))
                return Unknown(server, now, "Mesure absente, périmée ou non confirmée.");
            var blocked = Math.Abs(offset) >= MaximumAllowedSkewSeconds;
            var amount = offset.ToString("+0.###;-0.###;0", CultureInfo.InvariantCulture);
            return new(blocked ? "blocked" : "observed",
                "Horloge : écart mesuré de " + amount + " s avec " + server + ". "
                    + (blocked ? "Jonction refusée par POLICY.BlockJoinOnClockSkew (seuil absolu de 300 s). Aucune correction automatique."
                        : "Seuil de blocage non atteint ; une nouvelle mesure sera effectuée avant la jonction. Aucune correction automatique."),
                server, observed.ObservedUtc, offset, blocked);
        }
        catch (Exception) { return Unknown(server, now, "La lecture bornée n’a pas fourni de mesure exploitable."); }
    }

    private static JoinClockCheck Unknown(string? server, DateTimeOffset now, string reason) => new("warning",
        "Avertissement horloge : écart inconnu. " + reason + " La règle V1 ne bloque que l’écart mesuré d’au moins 300 s ; la jonction reste autorisée. Aucune correction automatique.",
        server, now, null, false);
}
