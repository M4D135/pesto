namespace Pesto.Engine;

/// <summary>Validated native projection; a partial JSON read must never silently enable a reservation.</summary>
public sealed record JoinReservationPolicy(string Domain, string RootOu, bool Enabled)
{
    public static JoinReservationPolicy Read(string configurationJson)
    {
        var configuration = V1Config.ValidateText(configurationJson);
        return new(configuration.Domain, configuration.RootOu, configuration.OperationPolicy.ReserveNamesInAd);
    }
}
