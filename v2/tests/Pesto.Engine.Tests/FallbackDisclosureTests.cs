using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>
/// Port du « control summary » V1 (Pesto-Core.ps1:4035 pour la confirmation de file, Pesto-Direct.ps1:345 pour la
/// confirmation unitaire) : l'aperçu du plan affiche la politique de repli RÉELLEMENT lue — mais uniquement quand
/// l'adaptateur de qualification injecté la déclare lui-même via <see cref="Pesto.Engine.IMutationFallbackDisclosure"/>.
/// Un adaptateur muet ne fait rien dire à personne ; la simulation et la production (aucun adaptateur injecté)
/// n'affichent jamais un état inventé. Les textes autorisés sont contrôlés mot pour mot contre la source V1.
/// </summary>
internal sealed class FallbackDisclosureTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";

    /// <summary>Texte V1 exact de la confirmation unitaire (Pesto-Direct.ps1:345).</summary>
    private const string V1UnitNote = "Politique : le repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Aucun repli sur résultat incertain.";

    /// <summary>Texte V1 exact de la confirmation de file (Pesto-Core.ps1:4035).</summary>
    private const string V1QueueNote = "Politique : un repli par tâche Windows utilisant le mot de passe du compte AD est autorisé en cas de refus confirmé. Les tâches sont suivies ; aucun repli après résultat incertain.";

    /// <summary>Adaptateur de qualification de fixture : déclare l'état qu'il a réellement lu (contrat de divulgation).</summary>
    private sealed class DisclosingMutationGateway : Pesto.Engine.IMutationGateway, Pesto.Engine.IMutationFallbackDisclosure, IFixtureEntraPreparation
    {
        public string Description => "fixture de qualification divulguante";
        public string FallbackPolicyState { get; init; } = TaskFallbackPolicy.False;
        public TaskFallbackAccountMode FallbackAccountMode { get; init; } = TaskFallbackAccountMode.ExplicitAccount;
        public Pesto.Engine.MutationOutcome Execute(Pesto.Engine.MutationRequest request) => new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);
    }

    private static DirectoryComputer Observed(string name, string? guid = ComputerGuid, string? ou = ParisOu) =>
        new(name, null, ou, null, guid, "example.local", null, null, null, null, null);

    /// <summary>Monde live avec un poste observé ; retourne le backend et l'aperçu de renommage prêt à préparer.</summary>
    private static (IPestoBackend Backend, string PreviewId, string Name) RenameWorld(Pesto.Engine.IMutationGateway? mutation)
    {
        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase) { [Computer] = Observed(Computer) };
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => machines.TryGetValue(name, out var c) ? c : null,
        };
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway, mutation, new FixedClock());
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        return (backend, Harness.Str(preview, "previewId"), Harness.Str(preview, "name"));
    }

    private static List<string> Warnings(JsonNode node) => Harness.Arr(node, "warnings").Select(n => n!.GetValue<string>()).ToList();

    private static string PrepareRename(IPestoBackend backend, string previewId)
    {
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        return string.Join('\n', Warnings(plan));
    }

    // ---- la note autorisée : texte V1 mot pour mot, rendue par l'adaptateur qui la déclare -------------------

    [Test]
    public void UnitPlanCarriesTheExactV1PolicyNoteWhenTheAdapterDeclaresItAdmitted()
    {
        var (backend, previewId, _) = RenameWorld(new DisclosingMutationGateway { FallbackPolicyState = TaskFallbackPolicy.True });
        var warnings = PrepareRename(backend, previewId);
        Check.True(warnings.Contains(V1UnitNote), "Le plan unitaire reprend mot pour mot le texte V1 de Pesto-Direct.ps1:345 (« " + V1UnitNote + " »)");
        Check.Contains("Compte de repli", warnings, "Le mode de compte réellement observé est divulgué aussi");
        Check.Contains("explicitement saisi", warnings, "La note dit que le compte est saisi, jamais le jeton de session");
        Check.Contains("jamais après un résultat incertain", warnings, "La note rappelle la règle V1 du jamais-après-incertain");
        Check.Contains("cette préparation n’écrit rien", warnings, "Les avertissements de base du mode réel restent présents");
    }

    [Test]
    public void BatchCarriesTheExactV1QueuePolicyNote()
    {
        var (backend, previewId, _) = RenameWorld(new DisclosingMutationGateway { FallbackPolicyState = TaskFallbackPolicy.True });
        Harness.Call(backend, "queue.add", new { kind = "rename", computer = Computer, previewId });
        var batch = Harness.Call(backend, "queue.prepare");
        var warnings = string.Join('\n', Warnings(batch));
        Check.True(warnings.Contains(V1QueueNote), "Le lot reprend mot pour mot le texte V1 de Pesto-Core.ps1:4035 (« " + V1QueueNote + " »)");
        Check.Contains("Les tâches sont suivies", warnings, "La variante file promet le suivi des tâches, comme V1");
    }

    [Test]
    public void MoveOnlyPlanNeverClaimsAFallbackThatV1LimitsToRenames()
    {
        var w = RenameWorld(new DisclosingMutationGateway { FallbackPolicyState = TaskFallbackPolicy.True });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "PA" });
        var warnings = string.Join('\n', Warnings(plan));
        Check.False(warnings.Contains("Politique :"), "Le repli V1 n'existe que pour le renommage : l'afficher sur un déplacement seul serait mensonger");
    }

    // ---- variantes fermées : false et unknown ne disent jamais « autorisé » ----------------------------------

    [Test]
    public void ClosedVariantWhenThePolicyIsReadFalse()
    {
        var (backend, previewId, _) = RenameWorld(new DisclosingMutationGateway { FallbackPolicyState = TaskFallbackPolicy.False });
        var warnings = PrepareRename(backend, previewId);
        Check.False(warnings.Contains("autorisé en cas de refus confirmé"), "Politique lue false : rien n'est jamais présenté comme autorisant le repli");
        Check.Contains("lu « false » (défaut V1)", warnings, "La note dit l'état réellement lu, pas un défaut de complaisance");
        Check.Contains("aucun repli", warnings, "La variante fermée nomme le refus");
        Check.Contains("jamais activée implicitement", warnings, "La règle V1 du jamais-implicite est rappelée");
    }

    [Test]
    public void ClosedVariantWhenThePolicyIsNotReliablyRead()
    {
        var (backend, previewId, _) = RenameWorld(new DisclosingMutationGateway { FallbackPolicyState = TaskFallbackPolicy.Unknown });
        var warnings = PrepareRename(backend, previewId);
        Check.False(warnings.Contains("autorisé en cas de refus confirmé"), "Politique non lue de façon fiable : jamais présentée comme autorisant le repli");
        Check.Contains("non lu de façon fiable", warnings, "L'état « unknown » est dit tel quel, jamais converti en vrai");
        Check.Contains("aucun repli", warnings, "Inconnu = refus, pas silence");
    }

    [Test]
    public void TruePolicyWithSsoSessionStillRefusesTheFallback()
    {
        var (backend, previewId, _) = RenameWorld(new DisclosingMutationGateway
        {
            FallbackPolicyState = TaskFallbackPolicy.True,
            FallbackAccountMode = TaskFallbackAccountMode.SessionSso,
        });
        var warnings = PrepareRename(backend, previewId);
        Check.False(warnings.Contains("autorisé en cas de refus confirmé"), "En session SSO le garde V1 refuse le repli : la note ne peut pas le dire autorisé");
        Check.Contains("indisponible", warnings, "La raison V1 du refus SSO est rendue");
        Check.Contains("explicitement saisi", warnings, "La note dit ce qu'il faudrait : un compte AD explicitement saisi");
    }

    // ---- silence honnête : aucun adaptateur déclarant = aucune note inventée ----------------------------------

    [Test]
    public void AdapterThatStaysSilentIsNeverGivenWords()
    {
        var (backend, previewId, _) = RenameWorld(new FakeMutationGateway());
        var warnings = PrepareRename(backend, previewId);
        Check.False(warnings.Contains("Politique :"), "Un adaptateur qui ne déclare rien ne fait jamais inventer de note au moteur");
    }

    [Test]
    public void SimulationAndProductionNeverInventAPolicyNote()
    {
        var simulation = Harness.Simulation();
        var preview = Harness.Call(simulation, "names.preview", new { type = "S", site = "paris", service = "ADM", computer = "S111301PAADM001" });
        var plan = Harness.Call(simulation, "operation.prepare", new { kind = "rename", computer = "S111301PAADM001", previewId = Harness.Str(preview, "previewId") });
        Check.False(string.Join('\n', Warnings(plan)).Contains("Politique :"), "La simulation n'a pas de politique AD : elle reste muette sur ce point");

        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase) { [Computer] = Observed(Computer) };
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => machines.TryGetValue(name, out var c) ? c : null,
        };
        var production = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway);
        var livePlan = Harness.Call(production, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "PA" });
        Check.False(string.Join('\n', Warnings(livePlan)).Contains("Politique :"), "La production sans adaptateur de mutation n'affiche aucun état de repli inventé");
    }

    // ---- l'adaptateur réel est bien raccordé au contrat de divulgation ----------------------------------------

    [Test]
    public void TheRealAdapterIsWiredToTheDisclosureContract()
    {
        Check.True(typeof(Pesto.Engine.IMutationFallbackDisclosure).IsAssignableFrom(typeof(PowerShellMutationGateway)),
            "PowerShellMutationGateway implémente le contrat de divulgation : l'aperçu du harnais verra l'état réellement lu");
        var root = LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"RandomNameEnabled\": true",
            "\"RandomNameEnabled\": true, \"AllowPasswordTaskFallback\": true"));
        var adapter = (Pesto.Engine.IMutationFallbackDisclosure)new PowerShellMutationGateway(root);
        Check.Equal(TaskFallbackPolicy.True, adapter.FallbackPolicyState, "L'état divulgué est celui lu dans le cfg.json de l'installation");
        Check.Equal(TaskFallbackAccountMode.SessionSso, adapter.FallbackAccountMode, "Sans source de compte injectée, le mode observé reste SSO : repli refusé, comme en V1");
    }
}
