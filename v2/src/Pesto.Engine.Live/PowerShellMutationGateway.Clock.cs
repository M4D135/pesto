namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IClockSkewReader, IJoinClockDisclosure
{
    private readonly IClockSkewReader clockReader;
    public JoinClockCheck? LastJoinClockCheck { get; private set; }
    public ClockSkewObservation ReadClockSkew(string server) => clockReader.ReadClockSkew(server);

    private MutationOutcome? JoinClockRefusal(MutationRequest request)
    {
        if (request.Kind != "join") return null;
        try
        {
            if (!ReadPolicyRequirements().BlockJoinOnClockSkew) { LastJoinClockCheck = null; return null; }
            LastJoinClockCheck = JoinClockGuard.Observe(clockReader, request.Dc);
            return LastJoinClockCheck.Blocked ? Refused(96, LastJoinClockCheck.Message) : null;
        }
        catch (Exception) { return Refused(96, "La politique de contrôle d’horloge ne peut pas être relue : aucune jonction engagée."); }
    }

    private MutationOutcome WithClockWarning(MutationRequest request, MutationOutcome outcome) => request.Kind == "join"
        && LastJoinClockCheck is { State: "warning" }
            ? outcome with { Message = "Avertissement horloge : écart inconnu, aucune correction automatique. " + outcome.Message }
            : outcome;
}
