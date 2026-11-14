using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private JoinClockCheck? lastJoinClockCheck;

    private JoinClockCheck? CheckJoinClock(V1OperationPolicy policy, string kind)
    {
        if (kind != "join" || !policy.BlockJoinOnClockSkew) return null;
        var check = JoinClockGuard.Observe(mutation as IClockSkewReader, DcOrNull(), clock);
        lastJoinClockCheck = check;
        if (check.Blocked) throw new PestoException("policy.clock_skew", check.Message);
        return check;
    }

    private Check ClockDiagnostic(V1OperationPolicy? policy)
    {
        if (policy is null) return new("Horloge de jonction", "unknown", "Configuration absente : politique d’horloge non lue.");
        if (!policy.BlockJoinOnClockSkew) return new("Horloge de jonction", "ok", "Contrôle POLICY.BlockJoinOnClockSkew désactivé ; aucune mesure lancée.");
        var observed = (mutation as IJoinClockDisclosure)?.LastJoinClockCheck ?? lastJoinClockCheck;
        if (observed is null) return new("Horloge de jonction", "unknown", "Mesure demandée lors de la préparation et juste avant jonction ; aucune mesure n’a encore été effectuée. Aucune correction automatique.");
        return new("Horloge de jonction", observed.State == "observed" ? "ok" : "warn", observed.Message
            + " Dernière observation : " + observed.ObservedUtc.ToString("O") + ".");
    }
}
