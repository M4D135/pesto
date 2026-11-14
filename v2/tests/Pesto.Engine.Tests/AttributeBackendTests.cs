using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Full backend flows against a memory directory/provider and real on-disk receipt format. No AD, SMB, HTTP or process call.</summary>
internal sealed class AttributeBackendTests
{
    private sealed class Adapter(string configuration, GpFixture gp, FixedClock clock) : IMutationGateway, IMutationReceiptFinalizer, IMutationAttributes
    {
        private readonly PowerShellMutationGateway format = new(configuration, receiptGpRoot: gp.Root);
        private readonly Dictionary<string, MutationRequest> requests = new(StringComparer.Ordinal);
        private AttributeObservation? pending;
        public string Description => "fixture attributs en mémoire";
        public AttributeSnapshot Current = AttributeFixture.Snapshot(clock);
        public readonly Dictionary<string, AttributeReference> References = new(StringComparer.OrdinalIgnoreCase)
        { [AttributeFixture.ManagerDn] = new(AttributeFixture.ManagerDn, AttributeFixture.ManagerGuid) };
        public int Sends, Writes, PersistenceCalls;
        public bool LoseReply, MissingAfter, FailFinalization, FailObservationPersistence;
        public Action? AfterSend;
        public MutationOutcome? ForcedOutcome;
        public MutationRequest? LastRequest;
        public AttributeSnapshot ReadAttributes(AttributeTarget target)
        {
            if (MissingAfter && Sends > 0) throw AttributeMutationRules.Refused("Fixture target is no longer observable");
            return Current with { ObservedAt = clock.GetUtcNow() };
        }
        public AttributeReference ResolveAttributeReference(string domain, string dc, string dn) =>
            References.TryGetValue(dn, out var reference) ? reference : throw AttributeMutationRules.Refused("Fixture reference is missing");
        public MutationOutcome Execute(MutationRequest request)
        {
            AttributeMutationRules.RequireRequest(request); LastRequest = request; requests.Add(request.ReceiptId, request); Sends++;
            Write(request, "Running", 0, "Requested", null);
            var outcome = ForcedOutcome ?? new(MutationStatus.Succeeded, 30, "Fixture native confirmation", false, request.ComputerGuid);
            if (outcome.Status != MutationStatus.Failed) { Writes++; Current = AttributeFixture.Applied(request.Attributes!, Current); }
            AfterSend?.Invoke();
            Write(request, "Uncertain", 97, "Uncertain", null);
            if (LoseReply) throw new IOException("Fixture lost reply after the sole write");
            return outcome;
        }
        public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome)
        {
            if (FailFinalization) throw new IOException("Fixture final disk failure");
            var success = outcome.Status == MutationStatus.Succeeded;
            Write(request, success ? "Verified" : outcome.Status == MutationStatus.Failed ? "Failed" : "Uncertain", outcome.Code,
                success ? "Confirmed" : outcome.Status == MutationStatus.Failed ? "NotRequested" : "Uncertain", success ? Current with { ObservedAt = clock.GetUtcNow() } : null,
                outcome.Message);
        }
        private void Write(MutationRequest request, string phase, int code, string effect, AttributeSnapshot? proof, string? message = null)
        {
            var json = AttributeFixture.Render(format, request, phase, code); json["Attributes"] = effect;
            json["AttributeObservation"] = proof is null ? null : JsonSerializer.SerializeToNode(proof);
            if (message is not null) json["Message"] = message;
            gp.AdapterRaw(request.ReceiptId, json.ToJsonString());
        }
        public string PathOf(string id) => Path.Combine(gp.Root, "V2", "receipts", id + ".json");
        public AttributeObservation ReadAttributeObservation(string id)
        {
            var path = PathOf(id); var source = AttributeMutationRules.ReadReceipt(path, File.ReadAllBytes(path), DateTimeOffset.UtcNow);
            try { pending = new(source, ReadAttributes(source.Plan.Target)); }
            catch (PestoException) { pending = new(source, null, "Fixture unavailable"); }
            return pending!;
        }
        public void PersistAttributeObservation(AttributeObservation observation)
        {
            Check.True(ReferenceEquals(pending, observation), "Backend persists only the provider's retained observation"); pending = null;
            PersistenceCalls++;
            if (FailObservationPersistence) throw new IOException("Fixture final observation cannot flush");
            Check.True(AttributeMutationRules.AfterMatches(observation.Source.Plan, observation.Snapshot!), "Only verified expected values can be persisted");
            var bytes = File.ReadAllBytes(PathOf(observation.Source.Receipt.Id));
            Check.Equal(observation.Source.ReceiptSha256, ReceiptAcknowledgementSource.Digest(bytes), "Exact receipt snapshot remains bound");
            // Match the native observation finalizer: update the retained receipt, never run the initial
            // writer again or reconstruct a coordination intent under a possibly newer configuration.
            var stored = JsonNode.Parse(bytes)!.AsObject();
            stored["Attributes"] = "Confirmed"; stored["AttributeObservation"] = JsonSerializer.SerializeToNode(observation.Snapshot);
            stored["Phase"] = "Verified"; stored["Code"] = 30; stored["RestartRequired"] = false;
            stored["Utc"] = DateTimeOffset.UtcNow.ToString("o");
            stored["Message"] = "Attributs confirmés par observation explicite du GUID et des valeurs ; aucune modification AD rejouée.";
            using var completed = JsonDocument.Parse(stored.ToJsonString());
            Check.True(AttributeMutationRules.ReceiptMetadataIsValid(completed.RootElement), "The completed receipt retains its exact original identities and diff");
            gp.AdapterRaw(observation.Source.Receipt.Id, stored.ToJsonString());
        }
    }

    private sealed class World : IDisposable
    {
        public readonly string Config;
        public readonly GpFixture Gp = new();
        public readonly FixedClock Clock = new();
        public readonly FakeGateway Directory = new();
        public readonly Adapter Mutation;
        public IPestoBackend Backend;
        public World(Action<JsonObject>? configure = null)
        {
            var json = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject(); configure?.Invoke(json); Config = LiveTestConfig.Write(json.ToJsonString());
            Mutation = new(Config, Gp, Clock);
            Directory.Find = _ => new(AttributeFixture.Computer, null, AttributeFixture.Ou, null, AttributeFixture.Guid, AttributeFixture.Domain, null, null, null, null, null);
            Backend = Harness.Live(Config, Directory, Mutation, Clock, Gp.Root);
        }
        public JsonNode Inspect() => Harness.Call(Backend, "attributes.inspect", new { computer = AttributeFixture.Computer });
        public JsonNode Prepare(object? values = null, JsonNode? inspection = null) => Harness.Call(Backend, "attributes.prepare", new
        { inspectionId = Harness.Str(inspection ?? Inspect(), "inspectionId"), values = values ?? new { description = "  Valeur exacte  " } });
        public JsonNode Apply(JsonNode plan, string? confirmation = null) => Harness.Call(Backend, "attributes.apply", new
        { planId = Harness.Str(plan, "planId"), confirmationName = confirmation ?? AttributeFixture.Computer });
        public void Reopen() => Backend = Harness.Live(Config, Directory, Mutation, Clock, Gp.Root);
        public void Dispose() { System.IO.Directory.Delete(Config, true); System.IO.Directory.Delete(Gp.Root, true); }
    }

    [Test]
    public void InspectPrepareAndCancelWriteNothingThenOneExactConfirmationPersistsTheRealDiff()
    {
        using var w = new World(); var inspection = w.Inspect();
        Check.Equal(AttributeFixture.Guid, Harness.Str(inspection, "computerGuid"), "Observed object shown before mutation");
        Check.Equal(" Description initiale ", Harness.Str(inspection["values"]!, "description"), "Inspection preserves exact value");
        var plan = w.Prepare(new { description = "  Valeur exacte  ", location = "" }, inspection);
        Check.Equal("attributes", Harness.Str(plan, "kind"), "Specialized operation kind");
        Check.Equal(AttributeFixture.Computer, Harness.Str(plan, "confirmationName"), "Exact machine is the confirmation");
        Check.Equal(0, w.Mutation.Sends, "Preparing does not create a mutation");
        Check.Equal(0, System.IO.Directory.GetFiles(w.Gp.Root, "*", SearchOption.AllDirectories).Length, "No mutation receipt before confirmation");
        Check.Pesto(() => w.Apply(plan, "WRONG"), "confirmation.invalid", "Incorrect confirmation cannot send");
        var result = w.Apply(plan); var receipt = result["receipt"]!;
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "Success needs native plus engine re-read");
        Check.Equal("30", Harness.Str(receipt, "code"), "Actual verified attribute code");
        Check.Equal(1, w.Mutation.Sends, "One mutation request"); Check.Equal(1, w.Mutation.Writes, "One targeted write");
        Check.Null(w.Mutation.LastRequest!.NewName, "No rename authority"); Check.Null(w.Mutation.LastRequest.Entra, "No Entra authority");
        Check.Equal("", w.Mutation.Current.Values.Location, "Explicit clear applied");
        Check.False(Harness.Bool(receipt, "restartRequired"), "No reboot is implied");
        Check.Pesto(() => w.Apply(plan), "plan.consumed", "Successful or interrupted plans cannot be replayed");
        w.Reopen(); var durable = Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(receipt, "id") });
        Check.Equal("attributes", Harness.Str(durable, "kind"), "Kind survives window closure");
        Check.Equal("Confirmed", Harness.Str(durable, "attributes"), "Durable effect is projected on reopen");
        Check.Equal("  Valeur exacte  ", Harness.Str(Harness.Arr(durable, "attributeChanges")[0]!, "after"), "Diff is read from the durable receipt");
    }

    [Test]
    public void BrowserCannotSubmitGuidBeforeValuesReferenceAuthorityOrAReplacementComputer()
    {
        using var w = new World(); var inspection = w.Inspect(); var plan = w.Prepare(inspection: inspection);
        Check.Pesto(() => Harness.Call(w.Backend, "attributes.inspect", new { computer = AttributeFixture.Computer, computerGuid = AttributeFixture.Guid }), "invalid_arguments", "Browser cannot choose a GUID");
        Check.Pesto(() => Harness.Call(w.Backend, "attributes.prepare", new { inspectionId = Harness.Str(inspection, "inspectionId"), values = new { description = "x", before = "forged" } }), "invalid_arguments", "Before values come only from the read");
        Check.Pesto(() => Harness.Call(w.Backend, "attributes.apply", new { planId = Harness.Str(plan, "planId"), confirmationName = AttributeFixture.Computer, computer = "OTHER" }), "invalid_arguments", "No execution retargeting");
        Check.Pesto(() => Harness.Call(w.Backend, "attributes.observe", new { id = "receipt-forged", computerGuid = AttributeFixture.Guid }), "invalid_arguments", "Observation takes only an internal receipt id");
        Check.Equal(0, w.Mutation.Sends, "No native authority from augmented arguments");
    }

    [Test]
    public void ChangedBeforeValueAndEachObservedIdentityComponentRefuseBeforeSend()
    {
        foreach (var changed in new[] { "value", "guid", "ou", "ouGuid", "dc", "name" })
        {
            using var w = new World(); var plan = w.Prepare(); var current = w.Mutation.Current;
            w.Mutation.Current = changed switch
            {
                "value" => current with { Values = current.Values with { Description = "Changed elsewhere" } },
                "guid" => current with { Target = current.Target with { ComputerGuid = Guid.NewGuid().ToString("D") } },
                "ouGuid" => current with { Target = current.Target with { OuGuid = Guid.NewGuid().ToString("D") } },
                "dc" => current with { Target = current.Target with { Dc = "dc02.example.local" } },
                "name" => current with { Target = current.Target with { Computer = "OTHER", DistinguishedName = "CN=OTHER," + AttributeFixture.Ou } },
                _ => current with { Target = current.Target with { Ou = "OU=Other,OU=Postes,DC=example,DC=local", DistinguishedName = "CN=" + AttributeFixture.Computer + ",OU=Other,OU=Postes,DC=example,DC=local" } }
            };
            Check.Pesto(() => w.Apply(plan), changed == "value" ? "attributes.changed" : "attributes.evidence", "Concurrency invalidates: " + changed);
            Check.Equal(0, w.Mutation.Sends, "No command is sent on changed evidence");
        }
    }

    [Test]
    public void AChangedInspectionExpiredPlanOrConfigurationRequiresNewPreparation()
    {
        using (var w = new World())
        {
            var inspection = w.Inspect(); w.Mutation.Current = w.Mutation.Current with { Values = w.Mutation.Current.Values with { Location = "Changed" } };
            Check.Pesto(() => w.Prepare(inspection: inspection), "attributes.changed", "The displayed snapshot cannot be silently refreshed under an old form");
        }
        using (var w = new World())
        {
            var plan = w.Prepare(); w.Clock.Advance(TimeSpan.FromMinutes(6));
            Check.Pesto(() => w.Apply(plan), "plan.stale", "Expired confirmation cannot authorize a new write");
        }
        using (var w = new World())
        {
            var plan = w.Prepare(); File.AppendAllText(Path.Combine(w.Config, "cfg.json"), " ");
            Check.Pesto(() => w.Apply(plan), "config.changed", "A different config snapshot invalidates the plan");
            Check.Equal(0, w.Mutation.Sends, "No send with stale policy");
        }
    }

    [Test]
    public void ManagedByReplacementAfterPreparationCannotBeHiddenByTheSameDn()
    {
        using var w = new World(); var plan = w.Prepare(new { managedBy = AttributeFixture.ManagerDn });
        var change = Harness.Arr(plan, "changes").Single()!;
        Check.Equal(AttributeFixture.ManagerGuid, Harness.Str(change, "referenceGuid"), "Reference GUID displayed with diff");
        w.Mutation.References[AttributeFixture.ManagerDn] = new(AttributeFixture.ManagerDn, Guid.NewGuid().ToString("D"));
        Check.Pesto(() => w.Apply(plan), "attributes.changed", "A replacement at the same DN requires a new confirmation");
        Check.Equal(0, w.Mutation.Sends, "No set against an unconfirmed reference");
    }

    [Test]
    public void NativeSuccessWithoutExactAfterProofRemainsUncertainWithoutReplay()
    {
        foreach (var variant in new[] { "unavailable", "wrongValue", "wrongGuid", "wrongCode", "restart", "reference" })
        {
            using var w = new World(); var plan = w.Prepare(variant == "reference" ? new { managedBy = AttributeFixture.ManagerDn } : null);
            if (variant == "unavailable") w.Mutation.MissingAfter = true;
            if (variant == "wrongValue") w.Mutation.AfterSend = () => w.Mutation.Current = w.Mutation.Current with { Values = w.Mutation.Current.Values with { Description = "Intervening change" } };
            if (variant == "wrongGuid") w.Mutation.AfterSend = () => w.Mutation.Current = w.Mutation.Current with { Target = w.Mutation.Current.Target with { ComputerGuid = Guid.NewGuid().ToString("D") } };
            if (variant == "wrongCode") w.Mutation.ForcedOutcome = new(MutationStatus.Succeeded, 0, "Fixture missing code", false, AttributeFixture.Guid);
            if (variant == "restart") w.Mutation.ForcedOutcome = new(MutationStatus.Succeeded, 30, "Fixture contradictory reboot", true, AttributeFixture.Guid);
            if (variant == "reference") w.Mutation.AfterSend = () => w.Mutation.Current = w.Mutation.Current with { ManagedByReferenceGuid = Guid.NewGuid().ToString("D") };
            var receipt = w.Apply(plan)["receipt"]!;
            Check.Equal("uncertain", Harness.Str(receipt, "status"), "No success for " + variant);
            Check.Equal("97", Harness.Str(receipt, "code"), "Unknown effects are conserved");
            Check.False(Harness.Bool(receipt, "restartRequired"), "Attributes never create a reboot task");
            Check.Equal(1, w.Mutation.Writes, "No corrective second write");
            Check.Pesto(() => w.Apply(plan), "plan.consumed", "Uncertain plan remains consumed");
        }
    }

    [Test]
    public void LostReplyThenReopenedObservationCertifiesTheReceiptWithoutAnotherSet()
    {
        using var w = new World(); w.Mutation.LoseReply = true; var result = w.Apply(w.Prepare()); var receipt = result["receipt"]!;
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "Lost reply is not a refusal and not a success");
        var id = Harness.Str(receipt, "id"); w.Reopen(); var observed = Harness.Call(w.Backend, "attributes.observe", new { id });
        Check.True(Harness.Bool(observed, "verified"), "A later explicit exact observation certifies completion");
        Check.Equal("30", Harness.Str(observed["receipt"]!, "code"), "Verified code only after persistence");
        Check.True(Harness.Bool(observed, "targetReadOnly"), "Observation only reads AD");
        Check.False(Harness.Bool(observed, "replayAllowed"), "No replay authority returned");
        Check.Equal(1, w.Mutation.Sends, "No request repeated after reopening"); Check.Equal(1, w.Mutation.Writes, "Exactly the original Set remains");
        Check.Equal(1, w.Mutation.PersistenceCalls, "Local result is recorded once after verification");
        w.Reopen(); Check.Equal("succeeded", Harness.Str(Harness.Call(w.Backend, "receipts.get", new { id }), "status"), "Proof remains after a second reopening");
    }

    [Test]
    public void MismatchedObservationAndDiskFailuresNeverCreateSuccessOrReleaseEvidence()
    {
        using (var w = new World())
        {
            w.Mutation.FailFinalization = true; var receipt = w.Apply(w.Prepare())["receipt"]!;
            Check.Equal("uncertain", Harness.Str(receipt, "status"), "A success reply without final durable receipt stays uncertain");
            var id = Harness.Str(receipt, "id"); var before = File.ReadAllBytes(w.Mutation.PathOf(id));
            w.Mutation.Current = w.Mutation.Current with { Values = w.Mutation.Current.Values with { Description = "Divergent" } };
            var observed = Harness.Call(w.Backend, "attributes.observe", new { id });
            Check.False(Harness.Bool(observed, "verified"), "Current values do not certify the expected result");
            Check.Equal(0, w.Mutation.PersistenceCalls, "No completion is attempted");
            Check.True(before.AsSpan().SequenceEqual(File.ReadAllBytes(w.Mutation.PathOf(id))), "Unresolved receipt bytes remain intact");
        }
        using (var w = new World())
        {
            w.Mutation.LoseReply = true; var receipt = w.Apply(w.Prepare())["receipt"]!; var id = Harness.Str(receipt, "id");
            w.Mutation.FailObservationPersistence = true;
            Check.Pesto(() => Harness.Call(w.Backend, "attributes.observe", new { id }), "attributes.persistence", "Read proof is insufficient if it cannot be flushed");
            Check.Equal("Uncertain", JsonNode.Parse(File.ReadAllText(w.Mutation.PathOf(id)))!["Phase"]!.GetValue<string>(), "No false durable Verified");
        }
    }

    [Test]
    public void ConsultationMayInspectAndObserveButNeverPersistsOrPreparesAWritingPlan()
    {
        using var w = new World(); w.Mutation.LoseReply = true; var receipt = w.Apply(w.Prepare())["receipt"]!; var id = Harness.Str(receipt, "id");
        var original = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION"); var bytes = File.ReadAllBytes(w.Mutation.PathOf(id));
        try
        {
            Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", "1");
            var inspection = w.Inspect(); Check.True(Harness.Bool(inspection, "complete"), "Consultation still reads current attributes");
            Check.Pesto(() => w.Prepare(new { location = "Changed" }, inspection), "attributes.readonly", "Direct backend calls obey consultation admission");
            var observed = Harness.Call(w.Backend, "attributes.observe", new { id });
            Check.False(Harness.Bool(observed, "verified"), "Matching values do not complete a durable receipt in consultation");
            Check.Contains("consultation", Harness.Str(observed, "reason"), "The distinction is disclosed");
            Check.Equal(0, w.Mutation.PersistenceCalls, "No finalizer or lock cleanup is called");
            Check.True(bytes.AsSpan().SequenceEqual(File.ReadAllBytes(w.Mutation.PathOf(id))), "All durable bytes remain identical");
            Check.Equal(1, w.Mutation.Sends, "No second native send");
        }
        finally { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", original); }
    }

    [Test]
    public void IncidentAndConfiguredExclusionsBlockNewDiffsButIncidentAllowsObservation()
    {
        foreach (var name in new[] { "IncidentMode", "ExcludedNames", "ExcludedOUs", "ExcludedGroupGuids" })
        {
            using var w = new World(json => json["POLICY"]![name] = name == "IncidentMode" ? JsonValue.Create(true)
                : new JsonArray(name == "ExcludedNames" ? AttributeFixture.Computer : name == "ExcludedOUs" ? "OU=Postes,DC=example,DC=local" : Guid.NewGuid().ToString("D")));
            var expected = name switch { "IncidentMode" => "policy.incident", "ExcludedNames" => "policy.excluded_name", "ExcludedOUs" => "policy.excluded_ou", _ => "policy.group_unverified" };
            Check.Pesto(() => w.Prepare(), expected, "Existing mutation policy preserved: " + name);
            Check.Equal(0, w.Mutation.Sends, "No action bypasses policy through attributes");
        }
        using (var w = new World())
        {
            w.Mutation.LoseReply = true; var id = Harness.Str(w.Apply(w.Prepare())["receipt"]!, "id");
            var original = JsonNode.Parse(File.ReadAllText(w.Mutation.PathOf(id)))!.AsObject();
            var json = JsonNode.Parse(File.ReadAllText(Path.Combine(w.Config, "cfg.json")))!; json["POLICY"]!["IncidentMode"] = true;
            File.WriteAllText(Path.Combine(w.Config, "cfg.json"), json.ToJsonString()); w.Reopen();
            Check.False(original["ConfigurationSha256"]!.GetValue<string>() == AttributeFixture.ConfigurationSha(w.Config), "Incident activation actually changed the current configuration");
            Check.True(Harness.Bool(Harness.Call(w.Backend, "attributes.observe", new { id }), "verified"), "Explicit read-only AD verification remains possible during incident mode");
            Check.Equal(1, w.Mutation.Writes, "No mutation was added by observation");
            Check.Equal(1, w.Mutation.Sends, "No initial send pipeline was entered again");
            var completed = JsonNode.Parse(File.ReadAllText(w.Mutation.PathOf(id)))!.AsObject();
            foreach (var field in new[] { "ConfigurationSha256", "PlanId", "CreatedUtc", "Coordination", "AttributeChanges", "ComputerGuid", "Domain", "Dc", "InitialOu", "TargetOuGuid" })
                Check.Equal(original[field]?.ToJsonString() ?? "null", completed[field]?.ToJsonString() ?? "null", "Observation preserves historical authorization facts: " + field);
            Check.Equal("Verified", completed["Phase"]!.GetValue<string>(), "The final proof is durably verified under the unchanged original plan");
            w.Reopen(); Check.Equal("succeeded", Harness.Str(Harness.Call(w.Backend, "receipts.get", new { id }), "status"), "The observed result remains readable after reopening in incident mode");
        }
    }

    [Test]
    public void NativeAvailabilityAndDebugConfigurationCannotEnableAttributeAuthority()
    {
        using (var w = new World(json => json["DEBUG"]!["Simulation"] = "true"))
        {
            Check.Pesto(() => w.Inspect(), "attributes.evidence", "A real API never starts native reads with simulation flags");
            Check.Equal(0, w.Mutation.Sends, "No implicit real fallback");
        }
        using (var w = new World())
        {
            var backend = Harness.Live(w.Config, w.Directory, new FakeMutationGateway(), w.Clock, w.Gp.Root);
            var cap = Harness.Arr(Harness.Call(backend, "session.info"), "capabilities").Single(x => Harness.Str(x!, "id") == "attributes")!;
            Check.False(Harness.Bool(cap, "enabled"), "A generic adapter cannot claim attributes support");
            Check.Pesto(() => Harness.Call(backend, "attributes.inspect", new { computer = AttributeFixture.Computer }), "attributes.unavailable", "No unsupported native provider is used");
        }
    }
}
