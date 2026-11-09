using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class ProductionSecurityTests
{
    [Test]
    public void StoredAcknowledgementMustBeCompleteAndMatchCurrentReceipt()
    {
        var valid = """
{"Phase":"PendingRestart","ResultCode":20,"Acknowledged":{"Schema":1,"Utc":"2026-10-25T10:00:00Z","By":"operator","Reason":"Vérifié manuellement","Phase":"PendingRestart","ResultCode":20,"Observation":null}}
""";
        using var good = JsonDocument.Parse(valid);
        Check.True(StoredMutationBarrier.IsAcknowledged(good.RootElement), "Acquittement V1 complet et lié au résultat accepté");
        foreach (var invalid in new[]
        {
            "{\"Phase\":\"PendingRestart\",\"Acknowledged\":{}}",
            valid.Replace("\"By\":\"operator\"", "\"By\":\"\""),
            valid.Replace("\"Schema\":1", "\"Schema\":2"),
            valid.Replace("\"Utc\":\"2026-10-25T10:00:00Z\"", "\"Utc\":\"today\""),
            valid.Replace("\"Observation\":null", "\"Observation\":{}"),
            valid.Replace("\"ResultCode\":20,\"Acknowledged\"", "\"ResultCode\":97,\"Acknowledged\""),
            valid.Replace("{\"Phase\":\"PendingRestart\"", "{\"Phase\":\"Uncertain\"")
        })
        {
            using var document = JsonDocument.Parse(invalid);
            Check.False(StoredMutationBarrier.IsAcknowledged(document.RootElement), "Un acquittement incomplet ou périmé ne libère jamais la barrière");
        }
    }

    [Test]
    public void FinalReadbackPersistsAnUncertainOutcomeInsteadOfNativeSuccess()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-final-receipt-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "V2", "receipts");
        Directory.CreateDirectory(folder);
        try
        {
            var request = new MutationRequest("rename", "LAB-PC", "11111111-1111-1111-1111-111111111111", "LAB-NEW", null,
                "example.local", "dc.example.local", "plan-1", "receipt-1");
            var path = Path.Combine(folder, "receipt-1.json");
            File.WriteAllText(path, JsonSerializer.Serialize(new
            {
                Schema = 1, Phase = "Uncertain", ReceiptId = request.ReceiptId, PlanId = request.PlanId,
                Kind = request.Kind, Computer = request.Computer, NewName = request.NewName, TargetOu = request.TargetOu,
                ComputerGuid = request.ComputerGuid, Domain = request.Domain, InitialBootUtc = "2026-10-24T09:00:00Z",
                MachineId = "machine-fixture", InitialProtected = true, InitialOu = "OU=Initial,DC=example,DC=local"
            }));
            var gateway = new PowerShellMutationGateway(receiptGpRoot: root);
            gateway.PersistFinalReceipt(request, new MutationOutcome(MutationStatus.Uncertain, 97, "Relecture non confirmée.", true));
            using var stored = JsonDocument.Parse(File.ReadAllText(path));
            Check.Equal("Uncertain", stored.RootElement.GetProperty("Phase").GetString()!, "Le résultat relu, pas le succès natif provisoire, survit au redémarrage");
            Check.Equal(97, stored.RootElement.GetProperty("Code").GetInt32(), "Le code final du moteur est conservé");
            Check.Equal("2026-10-24T09:00:00Z", stored.RootElement.GetProperty("InitialBootUtc").GetString()!, "La lecture initiale ne change pas à la finalisation");
            Check.True(stored.RootElement.GetProperty("InitialProtected").GetBoolean(), "La protection initiale reste disponible pour la réconciliation");
            Check.True(stored.RootElement.GetProperty("RestartRequired").GetBoolean(), "L’effet Windows déjà engagé reste déclaré");
            var before = File.ReadAllText(path);
            var refused = false;
            try { gateway.PersistFinalReceipt(request with { PlanId = "other-plan" }, new(MutationStatus.Succeeded, 0, "Incorrect", false)); }
            catch (IOException) { refused = true; }
            Check.True(refused, "Une autre identité de plan ne peut pas remplacer le reçu");
            Check.Equal(before, File.ReadAllText(path), "Le reçu existant reste intact après le refus");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Test]
    public void PreSendRefusalDoesNotInventADurableReceipt()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-no-receipt-" + Guid.NewGuid().ToString("N"));
        var request = new MutationRequest("rename", "LAB-PC", null, "LAB-NEW", null, "example.local", null, "plan-1", "receipt-1");
        new PowerShellMutationGateway(receiptGpRoot: root).PersistFinalReceipt(request, new(MutationStatus.Failed, 96, "Aucun envoi.", false));
        Check.False(Directory.Exists(root), "Un refus préalable conserve l’absence réelle de reçu natif");
    }

    [Test]
    public void LegacyReceiptWithoutBoundGuidCannotBePromotedByReconciliation()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-legacy-reconcile-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "V2", "receipts");
        Directory.CreateDirectory(folder);
        try
        {
            var path = Path.Combine(folder, "receipt-legacy.json");
            var json = JsonSerializer.Serialize(new
            {
                Schema = 1, Phase = "PendingRestart", Utc = "2026-10-25T09:00:00Z", ReceiptId = "receipt-legacy", PlanId = "plan-legacy",
                Kind = "join", Computer = "LAB-PC", NewName = "LAB-NEW", TargetOu = "OU=Postes,DC=example,DC=local",
                Code = 10, Message = "Redémarrage à vérifier.", RestartRequired = true
            });
            File.WriteAllText(path, json);
            var gateway = new PowerShellMutationGateway(receiptGpRoot: root);
            var observation = gateway.ReadReconciliation("receipt-legacy");
            Check.True(observation.Error is not null, "Sans identité AD liée ni état initial, aucune réussite déduite");
            Check.Pesto(() => { gateway.PersistReconciliation(observation); return null; }, "receipt.stale", "Une preuve insuffisante ne peut lever la barrière");
            Check.Equal(json, File.ReadAllText(path), "L’ancien reçu reste intact");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    [Test]
    public void InstallationRootAndWadConfigFolderResolveToTheSameProtectedModule()
    {
        var installation = Path.Combine(Path.GetTempPath(), "pesto-layout-" + Guid.NewGuid().ToString("N"));
        var wad = Path.Combine(installation, "wad");
        Directory.CreateDirectory(wad);
        try
        {
            File.WriteAllText(Path.Combine(wad, "cfg.json"), LiveTestConfig.NoRandom);
            File.WriteAllText(Path.Combine(wad, "ActiveDirectory.psd1"), "# changed manifest: must never be imported");
            Check.Equal(wad, V1ConfigDirectory.Resolve(installation)!, "La racine d’installation trouve wad/cfg.json");
            Check.Equal(wad, V1ConfigDirectory.Resolve(wad)!, "Le dossier cfg direct reste canonique");
            Check.Equal(wad, HostWiring.Parse(["--v1-root", installation]).V1Root!, "L’hôte utilise le même dossier canonique");
            foreach (var root in new[] { installation, wad })
                Check.Pesto(() => TrustedActiveDirectoryModule.Resolve(root), "directory.module_untrusted",
                    "Les deux sélections vérifient le même manifeste et refusent le contenu modifié, jamais wad/wad");
        }
        finally { Directory.Delete(installation, recursive: true); }
    }

    [Test]
    public void PowerShellVersionUsesTheActualEngineVersionRatherThanWindowsFileVersion()
    {
        Check.True(WindowsPowerShellProbe.IsSupportedVersion(0, "5.1\r\n"), "Le moteur 5.1 est accepté indépendamment de la version du fichier Windows 10.x");
        foreach (var value in new[] { "5.0", "7.4", "10.0.26100", "5.1\nother-output", "", new string('x', 1025) })
            Check.False(WindowsPowerShellProbe.IsSupportedVersion(0, value), "Une sortie différente ou non bornée n’est pas un moteur 5.1 confirmé");
        Check.False(WindowsPowerShellProbe.IsSupportedVersion(1, "5.1"), "Une sonde en échec ne confirme pas le moteur");
    }

    [Test]
    public void ProtectedCredentialEnvelopeIsNativeOnlyAndDoesNotDiscloseItselfThroughToString()
    {
        var envelope = new ProtectedWindowsCredential("LAB\\operator", "encrypted-fixture-only");
        var json = JsonSerializer.Serialize(envelope);
        using var document = JsonDocument.Parse(json);
        Check.Equal("LAB\\operator", document.RootElement.GetProperty("userName").GetString()!, "Identifiant dans le transport natif");
        Check.Equal("encrypted-fixture-only", document.RootElement.GetProperty("blob").GetString()!, "Enveloppe DPAPI, pas de champ password");
        Check.False(envelope.ToString().Contains(envelope.Blob, StringComparison.Ordinal), "Même un ToString accidentel ne divulgue pas l’enveloppe");
        if (!OperatingSystem.IsWindows())
            Check.Pesto(() => WindowsAdCredentialSource.Prompt(), "credential.unavailable", "Aucune invite ou identité simulée hors Windows");
    }
}
