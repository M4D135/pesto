using Pesto.Core;
using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal sealed class LiveProductionSafetyTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Target = "OU=Paris-Nord," + Container;
    private const string Source = "OU=Lyon-Sud," + Container;
    private const string Computer = "P111301LYINF009";
    private const string Identity = "11111111-1111-1111-1111-111111111111";
    private static DirectoryComputer Observed(string name, string ou = Source, string guid = Identity) =>
        new(name, null, ou, null, guid, "example.local", null, null, null, null, null);

    private static (IPestoBackend Backend, FakeGateway Directory, FakeMutationGateway Mutation) World()
    {
        var directory = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord", "Lyon-Sud"] },
            Find = name => name == Computer ? Observed(name) : null,
        };
        var mutation = new FakeMutationGateway();
        return (Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), directory, mutation), directory, mutation);
    }
    private static JsonNode Prepare(IPestoBackend backend, string kind = "move")
    {
        if (kind == "move") return Harness.Call(backend, "operation.prepare", new { kind, computer = Computer, targetOU = "PA" });
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        return Harness.Call(backend, "operation.prepare", new { kind, computer = Computer, previewId = Harness.Str(preview, "previewId") });
    }
    private static JsonNode Execute(IPestoBackend backend, JsonNode plan) => Harness.Call(backend, "operation.execute",
        new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void AdapterAvailabilityUnlocksActionsButSettingsCannotCreateAnAdapter()
    {
        var (backend, _, _) = World();
        var session = Harness.Call(backend, "session.info");
        Check.False(Harness.Bool(session, "readOnly"), "Adaptateur injecté disponible");
        foreach (var capability in Harness.Arr(session, "capabilities").Where(c => Harness.Str(c!, "id") is not ("joinPrecreated" or "acknowledge" or "attributes"))) Check.True(Harness.Bool(capability!, "enabled"), "Action disponible");
        Check.True(Harness.Bool(Harness.Call(backend, "settings.get"), "liveExecutionEnabled"), "État de l’hôte exposé, pas un interrupteur");
        Check.True(Harness.Bool(Harness.Call(Harness.Live(), "session.info"), "readOnly"), "Sans adaptateur aucune écriture");
    }

    [Test]
    public void UnattendedAuthorizationDoesNotDisableConfirmedInteractiveJoinOrStartAnything()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom.Replace("\"MaxBatch\": 50", "\"MaxBatch\": 50, \"UnattendedJoinEnabled\": true"));
        var directory = new FakeGateway { ChildOus = { ["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris-Nord"] }, Find = _ => null };
        var mutation = new FakeMutationGateway();
        var backend = Harness.Live(root, directory, mutation);
        var capabilities = Harness.Arr(Harness.Call(backend, "session.info"), "capabilities");
        var join = capabilities.Single(c => Harness.Str(c!, "id") == "join")!;
        Check.True(Harness.Bool(join, "enabled"), "L’autorisation d’automatisation ne désactive pas la jonction interactive");
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        Check.Equal(Harness.Str(preview, "name"), Harness.Str(plan, "confirmationName"), "Aperçu et confirmation exacte restent requis");
        Check.Equal(0, mutation.Requests.Count, "Aucun envoi au démarrage ni pendant la préparation");
        Check.True(Harness.Bool(capabilities.Single(c => Harness.Str(c!, "id") == "move")!, "enabled"), "Le déplacement reste disponible indépendamment");
    }

    [Test]
    public void FinalDirectoryFailureKeepsUncertainReceiptAndCannotReplay()
    {
        var (backend, directory, mutation) = World();
        var plan = Prepare(backend);
        mutation.Respond = _ => { directory.FailOn = "find"; return new(MutationStatus.Succeeded, 30, "Déplacement accepté", false); };
        var receipt = Execute(backend, plan);
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "La panne de relecture ne perd pas le reçu");
        Check.Equal("97", Harness.Str(receipt, "code"), "Code incertain");
        Check.Equal("uncertain", Harness.Str(Harness.Call(backend, "receipts.get", new { id = Harness.Str(receipt, "id") }), "status"), "Reçu consultable");
        Check.Pesto(() => Execute(backend, plan), "plan.consumed", "Aucun rejeu");
        Check.Equal(1, mutation.Requests.Count, "Un seul envoi");
    }

    [Test]
    public void RenameMoveCannotSucceedOnNameOnlyWithoutDestination()
    {
        var (backend, directory, mutation) = World();
        var plan = Prepare(backend, "renameMove");
        mutation.Respond = request =>
        {
            directory.Find = name => name == request.NewName ? Observed(name) : null;
            return new(MutationStatus.Succeeded, 77, "Fixture prétend déplacement", true);
        };
        var receipt = Execute(backend, plan);
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "GUID et nom seuls ne confirment pas l’OU");
    }

    [Test]
    public void MoveCannotSucceedOnReplacementObjectWithSameName()
    {
        var (backend, directory, mutation) = World();
        var plan = Prepare(backend);
        mutation.Respond = _ =>
        {
            directory.Find = name => name == Computer ? Observed(name, Target, "22222222-2222-2222-2222-222222222222") : null;
            return new(MutationStatus.Succeeded, 30, "Fixture prétend déplacement", false);
        };
        Check.Equal("uncertain", Harness.Str(Execute(backend, plan), "status"), "La relecture doit retrouver le GUID d’origine");
    }

    [Test]
    public void UncertainOutcomePreservesKnownRestartRequirement()
    {
        var (backend, _, mutation) = World();
        var plan = Prepare(backend, "rename");
        mutation.Respond = _ => new(MutationStatus.Uncertain, 97, "Renommage préalable engagé", true);
        var receipt = Execute(backend, plan);
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "Effet non confirmé");
        Check.True(Harness.Bool(receipt, "restartRequired"), "Le besoin connu de redémarrage n’est pas effacé");
    }

    [Test]
    public void ConfirmedRenameMoveRemainsPendingUntilRebootIsVerified()
    {
        var (backend, directory, mutation) = World();
        var plan = Prepare(backend, "renameMove");
        mutation.Respond = request =>
        {
            directory.Find = name => name == request.NewName ? Observed(name, Target) : null;
            return new(MutationStatus.Succeeded, 77, "Nom et déplacement confirmés, redémarrage requis", true);
        };
        var receipt = Execute(backend, plan);
        Check.Equal("pendingRestart", Harness.Str(receipt, "status"), "Une acceptation AD ne prouve pas le redémarrage Windows");
        Check.Equal("77", Harness.Str(receipt, "code"), "Le résultat natif complet reste conservé");
        Check.True(Harness.Bool(receipt, "restartRequired"), "La vérification explicite reste nécessaire");
    }

    [Test]
    public void ExternalConfigChangeInvalidatesPreparedMutationBeforeSend()
    {
        var directory = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord", "Lyon-Sud"] }, Find = name => name == Computer ? Observed(name) : null };
        var mutation = new FakeMutationGateway();
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var backend = Harness.Live(root, directory, mutation);
        var plan = Prepare(backend);
        File.AppendAllText(Path.Combine(root, "cfg.json"), " ");
        Check.Pesto(() => Execute(backend, plan), "config.changed", "Une configuration externe invalide le plan avant envoi");
        Check.Equal(0, mutation.Requests.Count, "Aucune mutation avec une politique périmée");
    }

    [Test]
    public void DurableReceiptIdsCannotCollideAcrossProcessSessions()
    {
        string Send()
        {
            var (backend, _, mutation) = World();
            mutation.Respond = _ => new(MutationStatus.Failed, 31, "Refus fixture", false);
            return Harness.Str(Execute(backend, Prepare(backend)), "id");
        }
        Check.False(Send() == Send(), "Deux sessions distinctes ne réutilisent jamais le même chemin de reçu durable");
    }
    [Test]
    public void MutationRequiresSourceGuidAndManagedScopeBeforePreparing()
    {
        foreach (var source in new[] { Observed(Computer, "OU=External,DC=example,DC=local"), Observed(Computer, Source, "") })
        {
            var (backend, directory, mutation) = World();
            directory.Find = name => name == Computer ? source : null;
            Check.Pesto(() => Prepare(backend), source.Guid == "" ? "identity.missing" : "source.out_of_scope", "Aucune préparation avec identité ou périmètre manquant");
            Check.Equal(0, mutation.Requests.Count, "Aucun appel de mutation");
        }
    }

    [Test]
    public void PreparedMutationRefusesSourceOuDriftEvenWithSameComputerGuid()
    {
        foreach (var changedOu in new[] { Target, "OU=External,DC=example,DC=local" })
        {
            var (backend, directory, mutation) = World();
            var plan = Prepare(backend);
            directory.Find = name => name == Computer ? Observed(name, changedOu) : null;
            Check.Pesto(() => Execute(backend, plan), "source.changed", "Même GUID mais OU déplacée : re-préparation obligatoire");
            Check.Equal(0, mutation.Requests.Count, "Aucune commande envoyée après dérive");
        }
    }

    [Test]
    public void DestinationOuRecreatedAtSameDnInvalidatesConfirmedPlan()
    {
        var (backend, directory, mutation) = World();
        var plan = Prepare(backend);
        directory.OuGuid = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
        Check.Pesto(() => Execute(backend, plan), "destination.changed", "Même DN, autre GUID cible : confirmation périmée");
        Check.Equal(0, mutation.Requests.Count, "Aucune commande envoyée vers une OU remplacée");
    }

    [Test]
    public void DestinationRequiresAnExactObservedOuGuid()
    {
        foreach (var observed in new DirectoryOrganizationalUnit?[] { null, new(Target, ""), new(Source, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") })
        {
            var (backend, directory, mutation) = World();
            directory.FindOu = _ => observed;
            Check.Pesto(() => Prepare(backend), "destination.missing", "Le DN cible seul ne suffit pas sans identité exacte");
            Check.Equal(0, mutation.Requests.Count, "Aucune mutation sur une destination non liée");
        }
    }

    [Test]
    public void StandaloneMoveCarriesExactSourceAndDestinationIdentityWithoutPriorRename()
    {
        var (backend, directory, mutation) = World();
        mutation.Respond = request =>
        {
            directory.Find = name => name == Computer ? Observed(name, Target) : null;
            return new(MutationStatus.Succeeded, 30, "Déplacement relu", false);
        };
        Check.Equal("succeeded", Harness.Str(Execute(backend, Prepare(backend)), "status"), "Déplacement seul V1 disponible dès inspection et confirmation");
        Check.Equal(Source, mutation.Requests.Single().SourceOu!, "L’OU source confirmée est transmise au précontrôle natif");
        Check.Equal(directory.OuGuid, mutation.Requests.Single().TargetOuGuid!, "L’identité cible confirmée est transmise au précontrôle natif");
    }

}
