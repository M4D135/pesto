namespace Pesto.Engine;

/// <summary>Persists the engine's final readback decision over the adapter's transport outcome.
/// The adapter validates receipt/request identity; failures throw and must never become success.</summary>
public interface IMutationReceiptFinalizer
{
    void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome);
}
