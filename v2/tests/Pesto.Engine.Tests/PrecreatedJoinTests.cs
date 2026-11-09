using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Existing-account fixtures only. No test imports AD or starts a native worker.</summary>
internal sealed class PrecreatedJoinTests
{
    [Test]
    public void SameGuidWithChangedNameOuOrDomainAfterSendRemainsUncertain()
    {
        foreach (var field in new[] { "name", "ou", "domain" })
        {
            using var w = new World(); var plan = w.Plan();
            w.Mutation.BeforeReturn = () =>
            {
                var previous = w.Account!;
                var changed = field switch { "name" => previous with { Name = "P111301PAINF002" },
                    "ou" => previous with { Ou = "OU=Other," + Container }, _ => previous with { Domain = "other.local" } };
                w.Directory.Find = _ => changed;
            };
            var receipt = w.Execute(plan);
            Check.Equal("uncertain", Harness.Str(receipt, "status"), "No pending acceptance for a changed " + field);
            Check.Equal("97", Harness.Str(receipt, "code"), "Identity contradiction requires inspection");
            Check.Equal(1, w.Mutation.Sends, "No automatic retry");
        }
    }

    private const string Name = "P111301PAINF001";
    private const string Identity = "11111111-2222-3333-4444-555555555555";
    private const string OuIdentity = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Ou = "OU=Paris-Nord," + Container;

    private sealed class Adapter : IMutationGateway, IMutationPrecreatedJoin
    {
        public string Description => "Fixture compte précréé";
        public bool SupportsPrecreatedJoin { get; set; } = true;
        public int Sends;
        public MutationRequest? Request;
        public Action? BeforeReturn;
        public MutationOutcome? Outcome;
        public MutationOutcome Execute(MutationRequest request)
        {
            PrecreatedJoinRules.RequireRequest(request); Request = request; Sends++; BeforeReturn?.Invoke();
            return Outcome ?? new(MutationStatus.PendingRestart, 10, "Fixture jonction acceptée sur GUID existant", true, request.PrecreatedJoin?.ComputerGuid);
        }
    }

    private sealed class World : IDisposable
    {
        public readonly string Config;
        public readonly string Gp = Harness.IsolatedGpRoot();
        public readonly FixedClock Clock = new();
        public readonly Adapter Mutation = new();
        public readonly FakeGateway Directory = new() { ChildOus = { [Container] = ["Paris-Nord"] } };
        public DirectoryComputer? Account = new(Name, null, Ou, null, Identity, "example.local", null, null, null, null, null);
        public readonly IPestoBackend Backend;
        public World(bool enabled = true, bool reserve = false, bool production = true)
        {
            var json = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
            json["POLICY"]!["AllowPrecreatedJoin"] = enabled;
            json["POLICY"]!["ReserveNamesInAD"] = reserve;
            json["CONF"]![0]!["DirectProd"] = production ? "true" : "false";
            Config = LiveTestConfig.Write(json.ToJsonString());
            Directory.Find = name => Account is { } account && name.Equals(account.Name, StringComparison.OrdinalIgnoreCase) ? account : null;
            Backend = Harness.Live(Config, Directory, Mutation, Clock, Gp);
        }
        public JsonNode Preview() => Harness.Call(Backend, "join.precreated.preview", new { name = Name });
        public JsonNode Plan(JsonNode? preview = null) => Harness.Call(Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview ?? Preview(), "previewId") });
        public JsonNode Execute(JsonNode plan) => Harness.Call(Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Name });
        public void Dispose() { System.IO.Directory.Delete(Config, true); System.IO.Directory.Delete(Gp, true); }
    }

    [Test]
    public void ExplicitPreviewDisplaysExactExistingIdentityBeforePreparationAndConfirmation()
    {
        using var w = new World(); var preview = w.Preview();
        Check.Equal(Name, Harness.Str(preview, "name"), "Le nom est affiché avant Ajouter");
        Check.Equal(Identity, Harness.Str(preview, "computerGuid"), "GUID réellement observé");
        Check.Equal(Ou, Harness.Str(preview, "ou"), "OU réellement observée");
        Check.Equal(Environment.MachineName, Harness.Str(preview, "computer"), "Jonction du poste local uniquement");
        Check.Equal("precreated", Harness.Str(preview, "joinAccountMode"), "Parcours explicitement annoncé");
        Check.True(Harness.IsNull(preview, "availableCount"), "Un compte existant n’est pas présenté comme un nom libre");
        var plan = w.Plan(preview);
        Check.Equal(0, w.Mutation.Sends, "Aperçu et plan ne lancent aucune mutation");
        Check.Equal(Identity, Harness.Str(plan, "computerGuid"), "Plan lié à ce GUID");
        Check.Equal(Name, Harness.Str(plan, "confirmationName"), "Confirmation sur le nom exact");
        Check.False(Harness.Bool(plan, "reservationRequired"), "Aucune création de réservation");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = "WRONG" }), "confirmation.invalid", "Confirmation exacte obligatoire");
        Check.Equal(0, w.Mutation.Sends, "Annulation/erreur de confirmation sans envoi");
        var receipt = w.Execute(plan);
        Check.Equal("pendingRestart", Harness.Str(receipt, "status"), "Acceptation sans redémarrage implicite");
        Check.Equal(1, w.Mutation.Sends, "Un seul envoi explicite");
        Check.NotNull(w.Mutation.Request!.PrecreatedJoin, "La demande native porte le compte interne");
        Check.Equal(Identity, w.Mutation.Request.ComputerGuid, "GUID natif épinglé");
        Check.Null(w.Mutation.Request.Reservation, "Aucune autorité de création/suppression de réservation");
        Check.Null(w.Mutation.Request.NameReservation, "Le nom AD existant n’est pas un bail de nom libre");
    }

    [Test]
    public void DisabledPolicyOrOldAdapterCannotEnablePrecreatedMode()
    {
        using (var w = new World(enabled: false))
        {
            Check.Pesto(() => w.Preview(), "join.precreated_unavailable", "Opt-in obligatoire");
            var cap = Harness.Arr(Harness.Call(w.Backend, "session.info"), "capabilities").Single(item => Harness.Str(item!, "id") == "joinPrecreated")!;
            Check.False(Harness.Bool(cap, "enabled"), "Capacité désactivée annoncée");
        }
        using (var w = new World())
        {
            w.Mutation.SupportsPrecreatedJoin = false;
            Check.Pesto(() => w.Preview(), "join.precreated_unavailable", "Adaptateur sans parcours déclaré refusé");
        }
    }

    [Test]
    public void BrowserCannotProvideGuidPolicyFlagOrArbitraryMutationAuthority()
    {
        using var w = new World();
        Check.Pesto(() => Harness.Call(w.Backend, "join.precreated.preview", new { name = Name, computerGuid = Identity }), "invalid_arguments", "GUID du navigateur interdit");
        var p = w.Preview();
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(p, "previewId"), allowExisting = true }), "invalid_arguments", "L’ancien booléen libre n’autorise rien");
        Check.Equal(0, w.Mutation.Sends, "Aucune commande via argument ajouté");
    }

    [Test]
    public void MissingAmbiguousOrOutOfScopeAccountNeverCreatesAReplacement()
    {
        using (var w = new World())
        {
            w.Account = null;
            Check.Pesto(() => w.Preview(), "join.precreated_missing", "Absence explicite refusée sans création");
        }
        using (var w = new World())
        {
            w.Directory.Find = _ => throw new PestoException("directory.ambiguous", "Fixture ambiguity");
            Check.Pesto(() => w.Preview(), "directory.ambiguous", "Aucune sélection arbitraire");
        }
        using (var w = new World())
        {
            w.Account = w.Account! with { Ou = "OU=Outside,DC=example,DC=local" };
            Check.Pesto(() => w.Preview(), "join.precreated_identity", "Hors périmètre refusé");
        }
    }

    [Test]
    public void PreprodAndChosenDestinationMustMatchTheExistingOu()
    {
        using (var w = new World(production: false))
            Check.Pesto(() => w.Preview(), "join.precreated_ou", "PREPROD obligatoire dans la configuration");
        using (var w = new World())
            Check.Pesto(() => Harness.Call(w.Backend, "join.precreated.preview", new { name = Name, targetOU = "OU=Other," + Container }), "join.precreated_ou", "Une reprise de compte ne le déplace pas");
    }

    [Test]
    public void ChangedGuidOuIdentityAndDisappearanceInvalidateTheConfirmedPlan()
    {
        foreach (var change in new[] { "guid", "ou", "missing", "ouGuid" })
        {
            using var w = new World(); var p = w.Plan();
            if (change == "guid") w.Account = w.Account! with { Guid = Guid.NewGuid().ToString("D") };
            else if (change == "ou") w.Account = w.Account! with { Ou = "OU=Other," + Container };
            else if (change == "missing") w.Account = null;
            else w.Directory.OuGuid = Guid.NewGuid().ToString("D");
            Check.Pesto(() => w.Execute(p), "join.precreated_changed", "Identité modifiée : " + change);
            Check.Equal(0, w.Mutation.Sends, "Aucune création/jonction de remplacement");
        }
    }

    [Test]
    public void ReserveNamesFlagNeverTurnsExplicitPrecreatedSelectionIntoCreation()
    {
        using var w = new World(reserve: true); var p = w.Plan();
        Check.False(Harness.Bool(p, "reservationRequired"), "Précréé prime sur la réservation de nom libre");
        _ = w.Execute(p);
        Check.False(w.Mutation.Request!.ReservationRequired, "Demande native sans création");
        Check.NotNull(w.Mutation.Request.PrecreatedJoin, "Compte existant explicitement confirmé");
    }

    [Test]
    public void ExistingAccountPresenceDoesNotTurnAWindowsRefusalIntoAnObservedJoin()
    {
        using var w = new World(); var p = w.Plan();
        w.Mutation.Outcome = new(MutationStatus.Failed, 2732, "Fixture refus Netjoin sans écriture", false);
        var result = w.Execute(p);
        Check.Equal("refused", Harness.Str(result, "status"), "La présence antérieure du compte n’est pas un effet de cette tentative");
        Check.Equal("2732", Harness.Str(result, "code"), "Refus Windows conservé sans contournement de propriétaire/ACL");
    }

    [Test]
    public void SameNameReplacementAfterSendIsUncertainNotPendingSuccess()
    {
        using var w = new World(); var p = w.Plan();
        w.Mutation.BeforeReturn = () => w.Account = w.Account! with { Guid = Guid.NewGuid().ToString("D") };
        var result = w.Execute(p);
        Check.Equal("uncertain", Harness.Str(result, "status"), "La réponse native ne couvre pas un autre GUID");
        Check.Equal("97", Harness.Str(result, "code"), "Identité perdue explicitement incertaine");
    }

    [Test]
    public void PreviewCannotBeReusedForRenameQueueOrASecondPlan()
    {
        using var w = new World(); var preview = w.Preview(); var id = Harness.Str(preview, "previewId");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Name, previewId = id }), "join.precreated_scope", "Aperçu réservé à la jonction locale");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "join", previewId = id }), "join.precreated_scope", "Pas de compte précréé en lot implicite");
        _ = w.Plan(preview);
        Check.Pesto(() => w.Plan(preview), "plan.stale", "Aperçu consommable une seule fois");
    }

    [Test]
    public void NormalNamePreviewDoesNotOptIntoPrecreatedReuse()
    {
        using var w = new World();
        w.Directory.DomainNames = [w.Account!.Name];
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.False(Harness.Str(preview, "name") == Name, "Le parcours libre continue d’éviter le nom pris");
        var p = w.Plan(preview);
        Check.Equal("new", Harness.Str(p, "joinAccountMode"), "La politique seule ne choisit pas de réutiliser un compte");
        Check.True(Harness.IsNull(p, "computerGuid"), "Aucun GUID d’un compte existant n’est adopté implicitement");
    }

    [Test]
    public void PureNativeContractRejectsMixedReservationOrChangedIdentity()
    {
        var account = new PrecreatedJoinAccount(Identity, Name, "example.local", "dc01.example.local", Ou, OuIdentity, new('c', 64));
        var request = new MutationRequest("join", Environment.MachineName, Identity, Name, Ou, account.Domain, account.Dc,
            "plan-fixture", "receipt-fixture", TargetOuGuid: OuIdentity, ConfigurationSha256: account.ConfigurationSha256, PrecreatedJoin: account);
        PrecreatedJoinRules.RequireRequest(request);
        foreach (var bad in new[] { request with { ReservationRequired = true }, request with { ComputerGuid = Guid.NewGuid().ToString("D") },
            request with { Dc = "dc02.example.local" }, request with { ConfigurationSha256 = new('d', 64) }, request with { Kind = "rename" } })
            Check.Pesto(() => { PrecreatedJoinRules.RequireRequest(bad); return null; }, "join.precreated_identity", "Contrat natif lié au seul compte confirmé");
        var script = PowerShellMutationGateway.PrecreatedJoinWorkerScript;
        Check.Contains("Get-ADComputer -Identity $id", script, "Relecture native par GUID");
        Check.Contains("$named.Count -ne 1", script, "Ambiguïté de nom refusée");
        foreach (var forbidden in new[] { "New-ADComputer", "Remove-ADComputer", "Set-Acl", "SetOwner", "AccountCreate" })
            Check.False(script.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Aucun pouvoir supplémentaire dans le garde précréé : " + forbidden);
    }
}
