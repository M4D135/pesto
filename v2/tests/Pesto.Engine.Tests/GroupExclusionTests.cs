using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class GroupExclusionTests
{
    private const string Domain = "example.local", Dc = "dc01.example.local";
    private const string Computer = "P111301PAINF009", Second = "P111301PAINF010";
    private const string Identity = "11111111-1111-1111-1111-111111111111", SecondIdentity = "22222222-2222-2222-2222-222222222222";
    private const string Group = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", OtherGroup = "bbbbbbbb-cccc-dddd-eeee-ffffffffffff";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local", Source = "OU=Paris-Nord," + Container, Target = "OU=Lyon," + Container;

    private sealed class Reader : IGroupExclusionReader
    {
        public int Reads;
        public bool Throw, Excluded;
        public DateTimeOffset Now = DateTimeOffset.UtcNow;
        public Func<GroupExclusionObservation, GroupExclusionObservation>? Change;
        public GroupExclusionObservation ReadGroupExclusions(string domain, string? dc, string computerGuid, IReadOnlyList<string> groups)
        {
            Reads++;
            if (Throw) throw new IOException("SECRET-NETWORK-DETAIL");
            var observed = new GroupExclusionObservation(computerGuid, domain, dc ?? domain, computerGuid == Identity ? Computer : Second,
                Source, groups, true, false, Excluded ? groups[0] : null, Now);
            return Change?.Invoke(observed) ?? observed;
        }
    }
    private sealed class Directory(FakeGateway inner, Reader reader) : IDirectoryGateway, IAutomationNameInventory, IGroupExclusionReader
    {
        public string Description => "fixture groupes, aucun système";
        public string? DiscoverDomainController(string domain) => inner.DiscoverDomainController(domain);
        public DirectoryOrganizationalUnit? FindOrganizationalUnit(string domain, string? dc, string dn) => inner.FindOrganizationalUnit(domain, dc, dn);
        public DirectorySearchResult SearchComputers(string domain, string? dc, string query, int limit) => inner.SearchComputers(domain, dc, query, limit);
        public DirectoryComputer? FindComputer(string domain, string? dc, string name) => inner.FindComputer(domain, dc, name);
        public IReadOnlyList<string> ListChildOuNames(string domain, string? dc, string ou) => inner.ListChildOuNames(domain, dc, ou);
        public DirectoryNameInventory ListComputerNames(string domain, string? dc, string scope, int max) => inner.ListComputerNames(domain, dc, scope, max);
        public DirectoryNameInventory ListAutomationComputerNames(string domain, string dc, string series, int maximum) => inner.ListAutomationComputerNames(domain, dc, series, maximum);
        public GroupExclusionObservation ReadGroupExclusions(string domain, string? dc, string id, IReadOnlyList<string> groups) => reader.ReadGroupExclusions(domain, dc, id, groups);
    }
    private sealed class Mutation : IMutationGateway, IFixtureEntraPreparation
    {
        public string Description => "fixture sans mutation native";
        public int Sends;
        public MutationOutcome Execute(MutationRequest request) { Sends++; return new(MutationStatus.Failed, 96, "Fixture sans envoi", false); }
    }
    private static string Configuration(bool enabled = true, bool fallback = false)
    {
        var json = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        json["POLICY"]!["ExcludedGroupGuids"] = enabled ? new JsonArray(Group, OtherGroup) : new JsonArray();
        json["POLICY"]!["AllowPasswordTaskFallback"] = fallback;
        return LiveTestConfig.Write(json.ToJsonString());
    }
    private static (IPestoBackend Backend, Reader Reader, Mutation Mutation, string Root) World(bool readerPresent = true, bool enabled = true)
    {
        var clock = new FixedClock(); var reader = new Reader { Now = clock.GetUtcNow() }; var mutation = new Mutation();
        var inner = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord", "Lyon"] }, ScopeNames = [Computer, Second],
            Find = name => name is Computer or Second ? new(name, null, Source, null, name == Computer ? Identity : SecondIdentity, Domain, null, null, null, null, null) : null
        };
        var root = Configuration(enabled);
        return (Harness.Live(root, readerPresent ? new Directory(inner, reader) : inner, mutation, clock), reader, mutation, root);
    }
    private static JsonNode Prepare(IPestoBackend backend, string computer = Computer) => Harness.Call(backend, "operation.prepare", new { kind = "move", computer, targetOU = "LY" });
    private static JsonNode Execute(IPestoBackend backend, JsonNode plan) => Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void StableGuidFilterMatchesV1AndNeverInterpolatesAnAdNameOrDn()
    {
        var filter = GroupExclusionGuard.MembershipFilter(Guid.Parse("00112233-4455-6677-8899-aabbccddeeff"), Guid.Parse(Group));
        Check.Equal(@"(&(objectGUID=\33\22\11\00\55\44\77\66\88\99\aa\bb\cc\dd\ee\ff)(memberOf:1.2.840.113556.1.4.1941:=<GUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee>))", filter, "Octets GUID RFC4515 et identité alternative du groupe exacts V1");
        Check.Equal(1, GroupExclusionGuard.Normalize([Group, Group.ToUpperInvariant()]).Count, "Canonicalisation de GUIDs dupliqués");
        Check.Pesto(() => GroupExclusionGuard.Normalize(["CN=Evil)(name=*),DC=example,DC=local"]), "policy.group_unverified", "Aucun DN ou filtre arbitraire");
    }

    [Test]
    public void CompleteObservationAllowsAndDirectOrNestedMembershipRefuses()
    {
        var clock = new FixedClock(); var reader = new Reader { Now = clock.GetUtcNow() };
        Check.NotNull(GroupExclusionGuard.Require(reader, Domain, Dc, Identity, [Group, OtherGroup], Computer, Source, clock), "Tous les groupes sont confirmés");
        reader.Excluded = true;
        var error = Check.Pesto(() => GroupExclusionGuard.Require(reader, Domain, Dc, Identity, [Group, OtherGroup], Computer, Source, clock), "policy.excluded_group", "Une appartenance récursive positive refuse");
        Check.Contains("directement ou par imbrication", error.Message, "Aucune limitation aux seuls groupes directs");
        var before = reader.Reads;
        Check.Null(GroupExclusionGuard.Require(reader, Domain, Dc, Identity, [], Computer, Source, clock), "Liste vide sans lecture");
        Check.Equal(before, reader.Reads, "Politique désactivée sans sonde inutile");
    }

    [Test]
    public void PartialMissingMismatchedOrUnreadableEvidenceNeverMeansNotAMember()
    {
        var clock = new FixedClock(); var reader = new Reader { Now = clock.GetUtcNow() };
        foreach (var change in new Func<GroupExclusionObservation, GroupExclusionObservation>[]
        {
            o => o with { ComputerGuid = SecondIdentity }, o => o with { Domain = "elsewhere.local" }, o => o with { Server = "other.example.local" },
            o => o with { ComputerName = "OTHER" }, o => o with { SourceOu = Target }, o => o with { Complete = false },
            o => o with { CheckedGroupGuids = [Group] }, o => o with { CheckedGroupGuids = [Group, Group] },
            o => o with { CheckedGroupGuids = [Group, SecondIdentity] }, o => o with { DomainController = true }, o => o with { DomainController = null },
            o => o with { ExcludedGroupGuid = SecondIdentity }, o => o with { ObservedUtc = clock.GetUtcNow().AddMinutes(-2) }
        })
        {
            reader.Change = change;
            Check.Pesto(() => GroupExclusionGuard.Require(reader, Domain, Dc, Identity, [Group, OtherGroup], Computer, Source, clock), "policy.group_unverified", "Une preuve partielle ou déliée reste un refus");
        }
        reader.Change = null; reader.Throw = true;
        var error = Check.Pesto(() => GroupExclusionGuard.Require(reader, Domain, Dc, Identity, [Group], Computer, Source, clock), "policy.group_unverified", "Groupe manquant, droits ou réseau illisibles refusent");
        Check.False(error.Message.Contains("SECRET-NETWORK-DETAIL", StringComparison.Ordinal), "Aucun détail de transport sensible exporté");
        Check.Pesto(() => GroupExclusionGuard.Require(null, Domain, Dc, Identity, [Group], Computer, Source, clock), "policy.group_unverified", "Lecteur absent ne signifie pas appartenance négative");
    }

    [Test]
    public void DirectApiPreparationCannotBypassGroupOrMissingReaderRefusal()
    {
        foreach (var readerPresent in new[] { true, false })
        {
            var world = World(readerPresent);
            try
            {
                world.Reader.Excluded = true;
                Check.Pesto(() => Prepare(world.Backend), readerPresent ? "policy.excluded_group" : "policy.group_unverified", "Appel API direct également contrôlé");
                Check.Equal(0, world.Mutation.Sends, "Aucun envoi à la préparation");
                var diagnostics = Harness.Arr(Harness.Call(world.Backend, "diagnostics.read"), "checks");
                Check.Equal("warn", Harness.Str(diagnostics.Single(c => Harness.Str(c!, "label") == "Groupes exclus")!, "state"), "Motif de refus visible");
            }
            finally { System.IO.Directory.Delete(world.Root, true); }
        }
    }

    [Test]
    public void MembershipIsReadAgainAfterConfirmationAndBeforeAnySend()
    {
        var world = World();
        try
        {
            var plan = Prepare(world.Backend);
            var before = world.Reader.Reads;
            Check.Pesto(() => Harness.Call(world.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = "wrong" }), "confirmation.invalid", "Confirmation exacte conservée");
            Check.Equal(before, world.Reader.Reads, "Pas d’exécution de contrôle de mutation sans confirmation valide");
            world.Reader.Excluded = true;
            Check.Pesto(() => Execute(world.Backend, plan), "policy.excluded_group", "Nouvelle appartenance après aperçu bloque");
            Check.Equal(before + 1, world.Reader.Reads, "Relecture finale obligatoire");
            Check.Equal(0, world.Mutation.Sends, "Le plan ne quitte pas le moteur");
        }
        finally { System.IO.Directory.Delete(world.Root, true); }
    }

    [Test]
    public void BatchRechecksEachLineAndStopsBeforeAnExcludedTarget()
    {
        var world = World();
        try
        {
            foreach (var computer in new[] { Computer, Second }) Harness.Call(world.Backend, "queue.add", new { kind = "move", computer, targetOU = "LY" });
            var initialReads = world.Reader.Reads;
            var batch = Harness.Call(world.Backend, "queue.prepare");
            Check.Equal(initialReads + 2, world.Reader.Reads, "Les deux lignes sont revérifiées à la préparation du lot");
            world.Reader.Excluded = true;
            var result = Harness.Call(world.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
            Check.True(Harness.Bool(result, "stopped"), "Lot interrompu devant appartenance exclue");
            Check.Equal(0, Harness.Arr(result, "receipts").Count, "Pas de reçu de succès fictif");
            Check.Equal(0, world.Mutation.Sends, "Aucune ligne envoyée");
        }
        finally { System.IO.Directory.Delete(world.Root, true); }
    }

    [Test]
    public void FreshJoinWithoutAnAdIdentityDoesNotInventAGroupMembership()
    {
        var world = World();
        try
        {
            world.Reader.Throw = true;
            var preview = Harness.Call(world.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
            var plan = Harness.Call(world.Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
            Execute(world.Backend, plan);
            Check.Equal(0, world.Reader.Reads, "Règle V1 : aucun compte AD avant une jonction neuve");
            Check.Equal(1, world.Mutation.Sends, "Le contrôle n’est pas remplacé par une interdiction générale de jonction");
        }
        finally { System.IO.Directory.Delete(world.Root, true); }
    }

    private sealed class Credentials(Action confirmed) : ITaskFallbackCredentialSource
    {
        public TaskFallbackAccountMode Mode => TaskFallbackAccountMode.ExplicitAccount;
        public string? DisplayUserName => "EXAMPLE\\operator";
        public int Acquisitions;
        public PestoAdCredential? AcquireForFallback(string computer, string? newName, string operationId)
        { Acquisitions++; confirmed(); return new("EXAMPLE\\operator", "FIXTURE-SECRET"); }
    }

    private sealed class Continuation(FixedClock clock) : IMutationGateway, IMutationMoveContinuation
    {
        public string Description => "fixture déplacement restant";
        public int Sends;
        public MoveContinuationPreparation PrepareMoveContinuation(string id, string planId)
        {
            var receipt = new Receipt(id, clock.GetUtcNow(), "renameMove", "OLD-PC", Computer, Target, "fixture", "uncertain", 89, "Partiel", false);
            var proof = new ReceiptReconciliationObservation(receipt, new string('a', 64), Identity, Domain,
                clock.GetUtcNow().AddHours(-2), clock.GetUtcNow().AddHours(-1), Identity, Computer, Source, Source,
                true, true, Computer, Computer, Domain, true, true, true, true, null);
            var authorization = new MoveContinuationAuthorization("fixture-token", id, proof.ReceiptSha256, planId,
                Computer, Identity, Source, Target, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", clock.GetUtcNow().AddMinutes(2));
            return new(proof, authorization, authorization.TargetOuGuid);
        }
        public MutationOutcome Execute(MutationRequest request) { Sends++; return new(MutationStatus.Failed, 96, "Aucun envoi attendu", false); }
    }

    [Test]
    public void RemainingMoveCannotSkipTheGroupCheckAtPreparationOrExecution()
    {
        var root = Configuration();
        try
        {
            var clock = new FixedClock(); var reader = new Reader { Now = clock.GetUtcNow(), Excluded = true };
            var inner = new FakeGateway
            {
                ChildOus = { [Container] = ["Paris-Nord", "Lyon"] },
                Find = name => name == Computer ? new(Computer, null, Source, null, Identity, Domain, null, null, null, null, null) : null
            };
            var mutation = new Continuation(clock);
            var backend = Harness.Live(root, new Directory(inner, reader), mutation, clock);
            Check.Pesto(() => Harness.Call(backend, "receipts.prepareMove", new { id = "receipt-parent" }), "policy.excluded_group", "Le reçu parent ne dispense pas du contrôle des groupes");
            reader.Excluded = false;
            var plan = Harness.Call(backend, "receipts.prepareMove", new { id = "receipt-parent" });
            reader.Throw = true;
            Check.Pesto(() => Execute(backend, plan), "policy.group_unverified", "Lecture devenue illisible avant continuation");
            Check.Equal(0, mutation.Sends, "Aucun déplacement enfant envoyé");
        }
        finally { System.IO.Directory.Delete(root, true); }
    }
    private sealed class NoTask : ITaskSchedulerTransport
    {
        public int Registrations;
        public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal)
        { Registrations++; throw new InvalidOperationException("No task expected"); }
        public void Run(string computer, string taskName) => throw new InvalidOperationException();
        public TaskProbeResult Probe(string computer, string taskName) => throw new InvalidOperationException();
        public void Delete(string computer, string taskName) => throw new InvalidOperationException();
        public string? ReadTaskLogTail(string computer, string localLogPath) => null;
    }

    [Test]
    public void NativeFallbackRechecksGroupsAfterItsOwnCredentialConfirmation()
    {
        var root = Configuration(fallback: true); var gp = Harness.IsolatedGpRoot();
        try
        {
            var reader = new Reader(); var credentials = new Credentials(() => { reader.Excluded = true; reader.Now = DateTimeOffset.UtcNow; });
            var task = new NoTask();
            var native = new PowerShellMutationGateway(root, credentials, task, gp, gp, groupReader: reader);
            var request = new MutationRequest("rename", Computer, Identity, "P111301PAINF001", Source, Domain, Dc, "plan-fixture", "receipt-fixture", Source);
            request = request with { ConfigurationSha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(Path.Combine(root, "cfg.json")))) };
            var after = typeof(PowerShellMutationGateway).GetMethod("AfterDirectAttempt", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var result = (MutationOutcome)after.Invoke(native, [request, new MutationOutcome(MutationStatus.Failed, 5, "Refus Windows confirmé", false)])!;
            Check.Equal(1, credentials.Acquisitions, "Le dialogue de repli est passé");
            Check.Equal(1, reader.Reads, "Lecture postérieure au changement intervenu pendant le dialogue");
            Check.Equal(0, task.Registrations, "Aucune création de tâche pour une cible désormais exclue");
            Check.Equal(MutationStatus.Failed, result.Status, "Refus avant tout envoi de repli");
            Check.Contains("ExcludedGroupGuids", result.Message, "Motif de politique explicite");
            Check.False(result.Message.Contains("FIXTURE-SECRET", StringComparison.Ordinal), "Secret jamais exposé");
        }
        finally { System.IO.Directory.Delete(root, true); System.IO.Directory.Delete(gp, true); }
    }

    [Test]
    public void NativeReaderAndMutationUseTheSameFinalGuidBasedGuard()
    {
        Check.Contains(GroupExclusionScript.Source, PowerShellDirectoryGateway.ConstantScript, "Même règle dans la lecture");
        var mutation = PowerShellMutationGateway.ConstantScript;
        Check.Contains(GroupExclusionScript.Source, mutation, "Même règle dans la mutation native");
        Check.Contains("Get-ADGroup -Identity $groupId -Properties ObjectGUID -ErrorAction Stop @adp", mutation, "Chaque GUID de groupe est vérifié");
        Check.Contains("memberOf:1.2.840.113556.1.4.1941:=<GUID=", mutation, "Appartenances récursives V1");
        var renameCheck = mutation.IndexOf("Assert-PestoGroupExclusions $guid", StringComparison.Ordinal);
        var moveCheck = mutation.IndexOf("Assert-PestoGroupExclusions $parsedGuid", StringComparison.Ordinal);
        Check.True(renameCheck > 0 && renameCheck < mutation.IndexOf("Rename-Computer -NewName", StringComparison.Ordinal), "Lecture finale avant renommage");
        Check.True(moveCheck > 0 && moveCheck < mutation.IndexOf("Set-ADObject -Identity $parsedGuid -ProtectedFromAccidentalDeletion:$false", StringComparison.Ordinal), "Lecture finale avant toute levée de protection");
        var request = new MutationRequest("move", Computer, Identity, null, Target, Domain, Dc, "plan", "receipt", Source);
        using var payload = JsonDocument.Parse(PowerShellMutationGateway.BuildPayload(request, "true", excludedGroupGuids: [Group]));
        Check.Equal(Group, payload.RootElement.GetProperty("ExcludedGroupGuids")[0].GetString()!, "Seuls les GUID validés de la politique passent au script constant");
    }
}
