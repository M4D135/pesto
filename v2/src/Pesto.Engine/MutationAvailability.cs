namespace Pesto.Engine;

/// <summary>Observed runtime availability; enabling an action does not claim Windows/AD qualification.</summary>
public interface IMutationAvailability
{
    bool IsAvailable { get; }
    string? UnavailableReason { get; }
}

/// <summary>Native prerequisites which the operator must be able to review before confirming the plan.</summary>
public interface IMutationPreparationDisclosure
{
    IReadOnlyList<string> PreparationNotes(string kind, string computer);
}
