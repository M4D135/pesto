using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class OperationPolicyTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string LyonOu = "OU=Lyon," + Container;
    private const string Computer = "P111301PAINF009";
    private const string Second = "P111301PAINF010";
    private const string Guid = "11111111-1111-1111-1111-111111111111";

    private sealed class ManagedMutation : IMutationGateway, IMutationManagedPolicy, IFixtureEntraPreparation
    {
        public string Description => "fixture politique, sans système";
        public MutationManagedPolicy Managed = new();
        public readonly List<MutationRequest> Requests = [];
        public MutationManagedPolicy ReadManagedPolicy() => Managed;
        public MutationOutcome Execute(MutationRequest request)
        { Requests.Add(request); return new(MutationStatus.PendingRestart, 20, "Fixture acceptée", true); }
    }

    private static string Configuration(string policy)
    {
        var json = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        foreach (var item in JsonNode.Parse(policy)!.AsObject()) json["POLICY"]![item.Key] = item.Value?.DeepClone();
        return json.ToJsonString();
    }

    private static (IPestoBackend Backend, ManagedMutation Mutation) World(string policy = "{}", string sourceOu = ParisOu)
    {
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord", "Lyon"] }, ScopeNames = [Computer, Second],
            Find = name => name is Computer or Second
                ? new DirectoryComputer(name, null, sourceOu, null, name == Computer ? Guid : "22222222-2222-2222-2222-222222222222", "example.local", null, null, null, null, null) : null,
        };
        var mutation = new ManagedMutation();
        return (Harness.Live(LiveTestConfig.Write(Configuration(policy)), gateway, mutation, new FixedClock()), mutation);
    }

    private static JsonNode Preview(IPestoBackend backend, string? computer = Computer, string site = "PA") =>
        Harness.Call(backend, "names.preview", computer is null ? (object)new { type = "P", site, service = "INF" }
            : new { type = "P", site, service = "INF", computer });

    private static JsonNode Prepare(IPestoBackend backend, JsonNode preview, string computer = Computer) =>
        Harness.Call(backend, "operation.prepare", new { kind = "rename", computer, previewId = Harness.Str(preview, "previewId") });

    [Test]
    public void DirectPreparationAndPreviouslyPreparedMutationCannotBypassConsultation()
    {
        var previous = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION");
        try
        {
            Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", null);
            var world = World(); var preview = Preview(world.Backend); var plan = Prepare(world.Backend, preview);
            Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", "1");
            Check.Pesto(() => Prepare(world.Backend, preview), "policy.readonly", "An already calculated preview cannot bypass current consultation");
            Check.Pesto(() => Harness.Call(world.Backend, "operation.execute", new
                { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
                "policy.readonly", "Consultation enabled after confirmation prevents a native mutation");
            Check.Contains("consultation", MutationPolicyGuard.Refusal(LiveTestConfig.NoRandom,
                new("rename", Computer, Guid, Second, ParisOu, "example.local", "dc01.example.local", "plan", "receipt", ParisOu), new())!,
                "Native admission uses the same current process guard");
            Check.Equal(0, world.Mutation.Requests.Count, "No mutation was sent");
        }
        finally { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", previous); }
    }

    [Test]
    public void MalformedPolicyListsAndScenarioAreNotSilentlyIgnored()
    {
        foreach (var bad in new[]
        {
            "{\"ExcludedNames\":\"*\"}", "{\"ExcludedNames\":[\"bad[name]\"]}", "{\"ExcludedOUs\":[\"not-an-ou\"]}",
            "{\"ExcludedGroupGuids\":[\"00000000-0000-0000-0000-000000000000\"]}", "{\"Scenario\":true}",
            "{\"CoordinationRoot\":\"relative/path\"}", "{\"CoordinationRoot\":false}",
        }) Check.Pesto(() => V1Config.ValidateText(Configuration(bad)), "config.invalid", "Politique invalide refusée");
        var invalidType = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        invalidType["POLICY"] = true;
        Check.Pesto(() => V1Config.ValidateText(invalidType.ToJsonString()), "config.invalid", "Un booléen n’est pas une politique");
        foreach (var invalid in new[]
        {
            LiveTestConfig.NoRandom.Replace("\"POLICY\"", "\"policy\"", StringComparison.Ordinal),
            LiveTestConfig.NoRandom.Replace("\"ClearProtectionOnMove\"", "\"clearprotectiononmove\"", StringComparison.Ordinal),
            LiveTestConfig.NoRandom.Replace("\"Schema\": 1", "\"Schema\": 1, \"Schema\": 1", StringComparison.Ordinal),
        }) Check.Pesto(() => V1Config.ValidateText(invalid), "config.invalid", "Un cfg édité directement ne contourne pas une politique par casse ou doublon");
    }

    [Test]
    public void ExcludedNamesAreNeverProposedAndDirectSourceCallsAreRefused()
    {
        var world = World("{\"ExcludedNames\":[\"p111301painf00?\"]}");
        var preview = Preview(world.Backend, computer: null);
        Check.Equal("P111301PAINF011", Harness.Str(preview, "name"), "Les noms 001..009 exclus et le nom 010 occupé sont ignorés");
        Check.Pesto(() => Preview(world.Backend), "policy.excluded_name", "L’ancien nom du poste est aussi protégé");
        Check.Pesto(() => Harness.Call(world.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "LY" }),
            "policy.excluded_name", "Appel API sans formulaire également protégé");
        Check.Equal(0, world.Mutation.Requests.Count, "Aucun envoi");
    }

    [Test]
    public void ExcludedOuProtectsSourceDescendantsAndDestination()
    {
        var source = World("{\"ExcludedOUs\":[\"" + ParisOu + "\"]}", "OU=Ateliers," + ParisOu);
        Check.Pesto(() => Harness.Call(source.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "LY" }),
            "policy.excluded_ou", "Une sous-OU reste exclue");
        var destination = World("{\"ExcludedOUs\":[\"" + LyonOu + "\"]}");
        Check.Pesto(() => Harness.Call(destination.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "LY" }),
            "policy.excluded_ou", "La destination est aussi protégée");
        Check.Equal(0, source.Mutation.Requests.Count + destination.Mutation.Requests.Count, "Aucun envoi");
    }

    [Test]
    public void RequiredServicesWithoutTheirProviderRefuseAndExposeTheirPolicy()
    {
        var coordination = World("{\"CoordinationRoot\":\"\\\\\\\\server\\\\share\"}");
        Check.Pesto(() => Preview(coordination.Backend, computer: null), "names.reservation_unavailable", "Un adaptateur sans registre ne confirme pas un bail");
        Check.Contains("CoordinationRoot", Harness.Call(coordination.Backend, "diagnostics.read").ToJsonString(), "Registre absent signalé");
        Check.Equal(0, coordination.Mutation.Requests.Count, "Aucun envoi sans coordination");
        var reserved = World("{\"ReserveNamesInAD\":true}");
        var preview = Preview(reserved.Backend, computer: null);
        Check.Pesto(() => Harness.Call(reserved.Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") }),
            "reservation.unavailable", "Un adaptateur sans parcours réservation ne prépare pas cette jonction");
        Check.Contains("ReserveNamesInAD", Harness.Call(reserved.Backend, "diagnostics.read").ToJsonString(), "Réservation absente signalée");
        Check.Equal(0, reserved.Mutation.Requests.Count, "Aucun envoi ni réservation fictive");
    }

    [Test]
    public void IncidentModeDisablesCapabilitiesAndBlocksPreparation()
    {
        var (backend, mutation) = World("{\"IncidentMode\":true}");
        var session = Harness.Call(backend, "session.info");
        Check.True(session["readOnly"]!.GetValue<bool>(), "Mode lecture seule explicite");
        Check.True(Harness.Arr(session, "capabilities").All(c => !c!["enabled"]!.GetValue<bool>()), "Tous les boutons d’écriture sont bloqués");
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "LY" }),
            "policy.incident", "L’appel direct ne contourne pas le mode incident");
        Check.Equal(0, mutation.Requests.Count, "Aucun envoi");
    }

    [Test]
    public void ManagedIncidentIsReReadBeforeSendAndCannotBeRelaxedByLocalConfig()
    {
        var (backend, mutation) = World();
        var plan = Prepare(backend, Preview(backend));
        mutation.Managed = new(IncidentMode: true);
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
            "policy.incident", "Changement GPO entre préparation et envoi");
        Check.Equal(0, mutation.Requests.Count, "La politique relue bloque avant l’envoi");
        mutation.Managed = new();
        Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal(1, mutation.Requests.Count, "Un refus avant envoi ne consomme pas le plan");
    }

    [Test]
    public void ManagedBatchLimitIsTheMinimumAndReCheckedAtExecution()
    {
        var (backend, mutation) = World();
        mutation.Managed = new(MaxBatch: 1);
        var first = Preview(backend);
        Harness.Call(backend, "queue.add", new { kind = "rename", computer = Computer, previewId = Harness.Str(first, "previewId") });
        var second = Preview(backend, Second);
        Check.Pesto(() => Harness.Call(backend, "queue.add", new { kind = "rename", computer = Second, previewId = Harness.Str(second, "previewId") }),
            "queue.limit", "La GPO ne peut pas être dépassée par MaxBatch local");
        mutation.Managed = new(MaxBatch: 2);
        Harness.Call(backend, "queue.add", new { kind = "rename", computer = Second, previewId = Harness.Str(second, "previewId") });
        var batch = Harness.Call(backend, "queue.prepare");
        mutation.Managed = new(MaxBatch: 1);
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }),
            "queue.limit", "Une réduction après préparation bloque le lot avant sa première ligne");
        Check.Equal(0, mutation.Requests.Count, "Aucun envoi");
    }

    [Test]
    public void ScenarioLocksAndManagedUnreadabilityCannotBeBypassed()
    {
        const string scenario = "{\"Schema\":1,\"Name\":\"Paris seulement\",\"Required\":[\"SiteCode\"],\"Allowed\":{\"SiteCode\":[\"PA\"]},\"Locked\":{\"TargetOU\":\"" + ParisOu + "\"}}";
        var (backend, mutation) = World("{\"Scenario\":" + scenario + "}");
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "LY" }),
            "policy.scenario", "Destination interdite même dans le même site nommé");
        var plan = Prepare(backend, Preview(backend));
        mutation.Managed = new(Refusal: "POLICY HKLM illisible");
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
            "policy.unsupported", "Une erreur de lecture GPO n’est pas une autorisation");
        mutation.Managed = new(ScenarioJson: "{}");
        Check.Pesto(() => Prepare(backend, Preview(backend)), "policy.unsupported", "Un scénario GPO invalide n’assouplit pas le cfg");
        Check.Equal(0, mutation.Requests.Count, "Aucun envoi");
    }

    [Test]
    public void NativePolicyGuardReusesTheSameRestrictions()
    {
        var request = new MutationRequest("rename", Computer, Guid, "P111301PAINF001", ParisOu, "example.local", null, "plan1", "receipt1", ParisOu);
        Check.Contains("ExcludedNames", MutationPolicyGuard.Refusal(Configuration("{\"ExcludedNames\":[\"*\"]}"), request, new())!, "Dernière relecture native applique les exclusions");
        Check.Contains("IncidentMode", MutationPolicyGuard.Refusal(Configuration("{}"), request, new(IncidentMode: true))!, "Dernière relecture native applique HKLM");
        Check.True(MutationPolicyGuard.Refusal(Configuration("{}"), request, new()) is null, "Configuration normale admissible");
    }

    [Test]
    public void WholeConfigurationFingerprintIncludesTheOriginalBytesAndCannotBeOmitted()
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes("\uFEFF" + Configuration("{}"));
        var fingerprint = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant();
        Check.Null(MutationPolicyGuard.ConfigurationRefusal(bytes, fingerprint), "Le SHA porte exactement les octets, BOM compris");
        Check.NotNull(MutationPolicyGuard.ConfigurationRefusal(bytes, null), "Pas de mutation native sans empreinte du plan");
        Check.NotNull(MutationPolicyGuard.ConfigurationRefusal(bytes, ""), "Empreinte vide refusée");
        Check.NotNull(MutationPolicyGuard.ConfigurationRefusal(System.Text.Encoding.UTF8.GetBytes(Configuration("{}")), fingerprint), "Une réécriture de fichier n’est pas silencieusement assimilée au plan confirmé");
        var changed = System.Text.Encoding.UTF8.GetBytes("\uFEFF" + Configuration("{\"ReserveNamesInAD\":true}"));
        Check.NotNull(MutationPolicyGuard.ConfigurationRefusal(changed, fingerprint), "La réservation ne peut pas apparaître après confirmation d’un plan sans création AD");
    }

    [Test]
    public void ParsedConfigurationAndFingerprintComeFromTheSameRawSnapshot()
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes("\uFEFF" + Configuration("{\"BlockJoinOnClockSkew\":true}"));
        var root = LiveTestConfig.Write(Configuration("{}"));
        try
        {
            File.WriteAllBytes(Path.Combine(root, "cfg.json"), bytes);
            var config = V1Config.Load(root, out var fingerprint);
            Check.True(config.OperationPolicy.BlockJoinOnClockSkew, "Le modèle correspond au contenu chargé");
            Check.Equal(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant(), fingerprint,
                "Empreinte des mêmes octets, BOM compris, sans seconde lecture qui pourrait viser une autre version");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void NativeRequestCarriesTheConfigurationFingerprintFrozenByItsPlan()
    {
        var world = World();
        var plan = Prepare(world.Backend, Preview(world.Backend));
        Harness.Call(world.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        var request = world.Mutation.Requests.Single();
        var expected = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Configuration("{}")))).ToLowerInvariant();
        Check.Equal(expected, request.ConfigurationSha256, "L’adaptateur peut relire la même configuration sous mutex et après les attentes");
        Check.False(request.ReservationRequired, "Une politique de réservation non montrée n’est pas activée dans le request");
    }

    [Test]
    public void EntraObservationAcceptsOnlyOneConfirmedAdOnlyState()
    {
        Check.True(EntraRenameGuard.Refusal(0, "AzureAdJoined : NO\r\nDomainJoined : YES\r\n") is null, "État AD seul confirmé");
        foreach (var text in new[] { "", "AzureAdJoined : YES\nDomainJoined : YES", "AzureAdJoined : NO\nDomainJoined : NO", "AzureAdJoined : NO\nAzureAdJoined : NO\nDomainJoined : YES" })
            Check.True(EntraRenameGuard.Refusal(0, text) is not null, "Hybride, hors AD, ambigu et inconnu refusés");
        Check.True(EntraRenameGuard.Refusal(1, "AzureAdJoined : NO\nDomainJoined : YES") is not null, "Code natif en erreur ne produit pas une preuve");
    }
}
