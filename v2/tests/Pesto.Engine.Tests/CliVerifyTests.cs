using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>CLI verify = Interventions > Vérifier l’état without the window: one receipt, the engine reconciliation, no plan.</summary>
internal sealed class CliVerifyTests
{
    private const string ReceiptId = "receipt-0123456789abcdef0123456789abcdef";

    private sealed class ReconcileBackend(Func<string, JsonObject> answer) : IPestoBackend
    {
        public readonly List<string> Operations = [];
        public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
        {
            Operations.Add(operation);
            if (operation != "receipts.reconcile") throw new TestFailureException("Verify only reconciles one receipt");
            return Task.FromResult<object?>(answer(args.GetProperty("id").GetString()!));
        }
    }

    private static ReconcileBackend Answer(string status, bool verified, string text, string? id = null) =>
        new(requested => new JsonObject { ["id"] = id ?? requested, ["status"] = status, ["verified"] = verified,
            ["message"] = verified ? text : "Message historique du reçu", ["reason"] = verified ? null : text });

    private static PestoCliResult Verify(AutomationFixture w, IPestoBackend backend) =>
        PestoCliRunner.Run(new PestoCliOptions("verify", ReceiptId: ReceiptId), w.Context, () => backend, w.Clock);

    [Test]
    public void VerifyAcceptsOnlyOneReceiptIdentifier()
    {
        var plan = Path.GetFullPath("test-plan.json");
        Check.Equal(ReceiptId, PestoCliOptions.Parse(["--cli", "verify", "--receipt", ReceiptId]).ReceiptId, "Receipt identifier admitted");
        foreach (var args in new string[][] { ["--cli", "verify"], ["--cli", "verify", "--receipt", "../receipt"],
            ["--cli", "verify", "--receipt", "r1", "--execute"], ["--cli", "verify", "--receipt", "r1", "--computer", "PC1"],
            ["--cli", "verify", "--receipt", "r1", "--plan", plan], ["--cli", "verify", "--receipt", "r1", "--credential-stdin"],
            ["--cli", "verify", "--receipt", "r1", "--idempotency-key", "k1"], ["--cli", "inspect", "--receipt", "r1"],
            ["--cli", "rename", "--computer", "PC1", "--new-name", "PC2", "--receipt", "r1"] })
            Check.Pesto(() => PestoCliOptions.Parse(args), "automation.arguments", "Verify stays a closed single-receipt check");
    }

    [Test]
    public void ProvedReceiptIsVerifiedWithoutJournalOrMutation()
    {
        using var w = new AutomationFixture();
        var backend = Answer("succeeded", true, "État final confirmé par vérification explicite.");
        var result = Verify(w, backend);
        Check.Equal(0, result.ExitCode, "Verified receipt exits zero: " + result.Message);
        Check.Equal("Verified", result.State, "Verified state reported");
        Check.Equal(ReceiptId, result.OperationId, "The checked receipt is named");
        Check.False(result.MutationStarted || result.RestartRequired, "Verification sends nothing and asks no reboot");
        Check.Equal(1, backend.Operations.Count, "Exactly one engine reconciliation");
        Check.False(System.IO.Directory.Exists(w.Gp), "No idempotent intent is written for a verification");
    }

    [Test]
    public void UnprovedReceiptKeepsItsStatusAndBarrier()
    {
        using var w = new AutomationFixture();
        var pending = Verify(w, Answer("pendingRestart", false, "Le redémarrage attendu n’est pas observé : le reçu reste bloquant."));
        Check.Equal(3010, pending.ExitCode, "A receipt still waiting for its reboot stays 3010");
        Check.Equal("PendingRestart", pending.State, "Pending state kept");
        Check.True(pending.RestartRequired, "Reboot still required");
        Check.Contains("reste bloquant", pending.Message, "The engine reason is shown, not the historical message");
        var uncertain = Verify(w, Answer("uncertain", false, "Observation incomplète."));
        Check.Equal(97, uncertain.ExitCode, "An uncertain receipt is never turned into a success");
        Check.Equal("Uncertain", uncertain.State, "Uncertain state kept");
    }

    [Test]
    public void ForeignAnswerOrEngineRefusalIsRefused()
    {
        using var w = new AutomationFixture();
        var foreign = Verify(w, Answer("succeeded", true, "ok", id: "receipt-other"));
        Check.Equal(96, foreign.ExitCode, "Another receipt in the answer is refused");
        var refused = Verify(w, new ReconcileBackend(_ => throw new PestoException("receipt.not_reconcilable", "Seuls les reçus en attente peuvent être vérifiés.")));
        Check.Equal(96, refused.ExitCode, "Engine refusal stays a refusal");
        Check.Contains("Seuls les reçus en attente", refused.Message, "Engine reason kept");
    }

    [Test]
    public void VerifyNeedsAnAllowedAutomationWithoutHklmBan()
    {
        using var w = new AutomationFixture();
        w.ChangeConfiguration(j => { j["POLICY"]!["UnattendedOperationsEnabled"] = false; j["POLICY"]!["UnattendedJoinEnabled"] = false; });
        var backend = Answer("succeeded", true, "ok");
        Check.Equal(96, Verify(w, backend).ExitCode, "No CLI verification while automation is disabled");
        Check.Equal(0, backend.Operations.Count, "Refused before any engine call");
        w.ChangeConfiguration(j => j["POLICY"]!["UnattendedJoinEnabled"] = true);
        Check.Equal(0, Verify(w, backend).ExitCode, "Join automation is enough to verify a receipt");
        w.Managed = new(DisableUnattendedJoin: true);
        Check.Equal(96, Verify(w, backend).ExitCode, "HKLM ban wins over the configuration");
        w.ChangeConfiguration(j => j["POLICY"]!["UnattendedOperationsEnabled"] = true);
        Check.Equal(0, Verify(w, backend).ExitCode, "Operations automation still allowed");
    }
}
