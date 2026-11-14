using System.Runtime.CompilerServices;

namespace Pesto.Engine.Tests;

/// <summary>Explicit test-only AD-only observations. Production adapters never inherit this fixture capability.</summary>
internal interface IFixtureEntraPreparation : IMutationEntraPreparation
{
    EntraRenameAuthorization IMutationEntraPreparation.PrepareEntra(EntraPreparationRequest request) =>
        FixtureEntraPreparation.Read(this, request);
}

internal sealed class FixtureEntraReadOnly : IMutationGateway, IFixtureEntraPreparation
{
    public string Description => "fixture de préparation Entra sans écriture";
    public MutationOutcome Execute(MutationRequest request) =>
        throw new TestFailureException("Cette fixture de préparation ne peut envoyer aucune mutation.");
}

internal static class FixtureEntraPreparation
{
    private sealed record Clock(TimeProvider Value);
    private static readonly ConditionalWeakTable<object, Clock> Clocks = new();
    public static void SetClock(object? gateway, TimeProvider clock)
    {
        if (gateway is not IFixtureEntraPreparation) return;
        Clocks.Remove(gateway); Clocks.Add(gateway, new(clock));
    }
    public static EntraRenameAuthorization Read(object gateway, EntraPreparationRequest request)
    {
        EntraPreparationRules.ValidateRequest(request);
        var now = (Clocks.TryGetValue(gateway, out var clock) ? clock.Value : TimeProvider.System).GetUtcNow();
        return new("fixture-" + Guid.NewGuid().ToString("N"), request, "adOnly", "Disabled",
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", now, now.AddMinutes(5));
    }
}
