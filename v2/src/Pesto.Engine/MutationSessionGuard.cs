using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Consultation permits pure reads, never task creation, durable-state transitions, name leases or AD effects.
/// IncidentMode remains a separate business policy: explicit recovery observations can still be permitted there.</summary>
public static class MutationSessionGuard
{
    public static void RequireWritableSession()
    {
        if (Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1")
            throw new PestoException("policy.readonly", "Session de consultation : aucune tâche, transition de reçu, réservation ou mutation autorisée.");
    }
}
