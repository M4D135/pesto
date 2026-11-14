using System.Diagnostics;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Only memory values and temporary receipts. No test starts the native worker or imports AD.</summary>
internal static class AttributeFixture
{
    public const string Computer = "P111301PAINF009";
    public const string Guid = "11111111-1111-1111-1111-111111111111";
    public const string OuGuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    public const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    public const string Domain = "example.local";
    public const string Dc = "dc01.example.local";
    public const string ManagerDn = "CN=Operateur,OU=Utilisateurs,DC=example,DC=local";
    public const string ManagerGuid = "22222222-2222-2222-2222-222222222222";
    public static AttributeTarget Target => new(Computer, Guid, "CN=" + Computer + "," + Ou, Ou, OuGuid, Domain, Dc);
    public static AttributeSnapshot Snapshot(TimeProvider clock) => new(Target, new(" Description initiale ", "Bureau 12", ""), clock.GetUtcNow());
    public static string ConfigurationSha(string path) => ReceiptAcknowledgementSource.Digest(File.ReadAllBytes(Path.Combine(path, "cfg.json")));
    public static MutationRequest Request(string configuration, string id = "receipt-attributes-fixture")
    {
        var plan = new AttributeMutationPlan(Target, [new("description", " Description initiale ", "  Valeur exacte  ", null)], ConfigurationSha(configuration));
        return new("attributes", Computer, Guid, null, Ou, Domain, Dc, "attributes-plan-fixture", id, Ou, OuGuid,
            ConfigurationSha256: plan.ConfigurationSha256, Attributes: plan);
    }
    public static JsonObject Render(PowerShellMutationGateway native, MutationRequest request, string phase = "Running", int code = 0)
    {
        var baselineType = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.NativeReceiptSnapshot")!;
        var baseline = Activator.CreateInstance(baselineType, [null, null, null, null, null, null, null,
            request.ComputerGuid, request.Computer, request.SourceOu, null, null, false, null])!;
        return JsonNode.Parse((string)typeof(PowerShellMutationGateway).GetMethod("ReceiptJson", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(native, [request, phase, code, "Fixture du vrai writer attributs", false, baseline])!)!.AsObject();
    }
    public static AttributeSnapshot Applied(AttributeMutationPlan plan, AttributeSnapshot before)
    {
        var values = before.Values; var manager = before.ManagedByReferenceGuid;
        foreach (var change in plan.Changes)
        {
            values = change.Attribute switch { "description" => values with { Description = change.After },
                "location" => values with { Location = change.After }, _ => values with { ManagedBy = change.After } };
            if (change.Attribute == "managedBy") manager = change.ReferenceGuid;
        }
        return before with { Values = values, ManagedByReferenceGuid = manager };
    }
    public static JsonElement Element(string json) { using var document = JsonDocument.Parse(json); return document.RootElement.Clone(); }
}

internal sealed class AttributeMutationTests
{
    [Test]
    public void ExactValuesOmissionAndExplicitEmptyHaveDifferentMeaning()
    {
        var before = AttributeFixture.Snapshot(new FixedClock());
        var requested = AttributeMutationRules.ReadRequested(AttributeFixture.Element("""{"description":"  Texte exact  ","location":""}"""));
        var changes = AttributeMutationRules.Changes(before, requested, _ => throw new TestFailureException("No reference was requested"));
        Check.Equal(2, changes.Count, "Only supplied and different attributes are included");
        Check.Equal("  Texte exact  ", changes.Single(x => x.Attribute == "description").After, "Spaces are neither trimmed nor normalized");
        Check.Equal("", changes.Single(x => x.Attribute == "location").After, "An empty string explicitly clears");
        Check.False(changes.Any(x => x.Attribute == "managedBy"), "An omitted value remains untouched");
        var after = AttributeFixture.Applied(new(before.Target, changes, new('c', 64)), before);
        Check.Equal("", after.Values.Location, "The expected after-state includes clearing");
        AttributeMutationRules.RequireValue(new string('a', 1024));
    }

    [Test]
    public void RequestedObjectIsClosedAndRejectsDuplicateNullControlOrOversizedValues()
    {
        foreach (var json in new[] { "{}", "[]", "{\"description\":null}", "{\"Description\":\"x\"}",
                     "{\"description\":\"x\",\"description\":\"y\"}", "{\"description\":\"x\",\"before\":\"injected\"}" })
            Check.Pesto(() => AttributeMutationRules.ReadRequested(AttributeFixture.Element(json)), "invalid_arguments", "Closed request: " + json);
        foreach (var value in new[] { "new\nline", "nul\0value", "del\u007f", "c1\u0085", new string('a', 1025) })
            Check.Pesto(() => AttributeMutationRules.ReadRequested(JsonSerializer.SerializeToElement(new { description = value })), "attributes.value", "Bounded exact text");
        var before = AttributeFixture.Snapshot(new FixedClock());
        Check.Pesto(() => AttributeMutationRules.Changes(before, new Dictionary<string, string> { ["description"] = before.Values.Description }, _ => null!),
            "attributes.empty", "A plan must contain an actual difference");
    }

    [Test]
    public void ManagedByDiffPinsTheObservedDnAndGuidAndRejectsReplacement()
    {
        var before = AttributeFixture.Snapshot(new FixedClock());
        var changes = AttributeMutationRules.Changes(before, new Dictionary<string, string> { ["managedBy"] = AttributeFixture.ManagerDn.ToLowerInvariant() },
            _ => new(AttributeFixture.ManagerDn, AttributeFixture.ManagerGuid));
        var plan = new AttributeMutationPlan(before.Target, changes, new('c', 64));
        Check.Equal(AttributeFixture.ManagerDn, changes[0].After, "The displayed diff uses the observed DN");
        Check.Equal(AttributeFixture.ManagerGuid, changes[0].ReferenceGuid, "GUID is read by the provider, not accepted from the browser");
        var after = AttributeFixture.Applied(plan, before);
        Check.True(AttributeMutationRules.AfterMatches(plan, after), "Both reference facts agree");
        Check.False(AttributeMutationRules.AfterMatches(plan, after with { ManagedByReferenceGuid = System.Guid.NewGuid().ToString("D") }), "Recreated manager at the same DN is different");
        Check.Pesto(() => { AttributeMutationRules.RequireChanges([changes[0] with { ReferenceGuid = null }], AttributeFixture.Domain); return null; },
            "attributes.evidence", "Nonempty managedBy always requires its pinned GUID");
        Check.Pesto(() => AttributeMutationRules.Changes(before, new Dictionary<string, string> { ["managedBy"] = "CN=Other,DC=foreign,DC=local" },
            dn => new(dn, AttributeFixture.ManagerGuid)), "attributes.evidence", "A reference cannot escape the configured domain");
    }

    [Test]
    public void IdentityTupleAndNativeKindCannotBeMixedWithAnotherAction()
    {
        var config = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        try
        {
            var request = AttributeFixture.Request(config); AttributeMutationRules.RequireRequest(request);
            foreach (var bad in new[] { request with { Kind = "join" }, request with { NewName = request.Computer },
                         request with { ComputerGuid = System.Guid.NewGuid().ToString("D") }, request with { TargetOuGuid = System.Guid.NewGuid().ToString("D") },
                         request with { Dc = "dc02.example.local" }, request with { ReservationRequired = true },
                         request with { ConfigurationSha256 = new('d', 64) }, request with { EntraLeaveConfirmed = true }, request with { Attributes = null } })
                Check.Pesto(() => { AttributeMutationRules.RequireRequest(bad); return null; }, "attributes.evidence", "Mixed native authority cannot target AD");
            var before = AttributeFixture.Snapshot(new FixedClock()); var plan = request.Attributes!;
            foreach (var target in new[] { before.Target with { ComputerGuid = System.Guid.NewGuid().ToString("D") },
                         before.Target with { OuGuid = System.Guid.NewGuid().ToString("D") }, before.Target with { Dc = "dc02.example.local" } })
                Check.False(AttributeMutationRules.BeforeMatches(plan, before with { Target = target }), "Exact tuple is pinned");
        }
        finally { Directory.Delete(config, true); }
    }
}

internal sealed class AttributeNativeReceiptTests
{
    [Test]
    public void ActualPreSendWriterRetainsRequestedDiffAndGuidBeforeAnyNativeSend()
    {
        var config = LiveTestConfig.Write(LiveTestConfig.NoRandom); var gp = new GpFixture();
        try
        {
            var request = AttributeFixture.Request(config); var native = new PowerShellMutationGateway(config, receiptGpRoot: gp.Root);
            var json = AttributeFixture.Render(native, request); var path = gp.AdapterRaw(request.ReceiptId, json.ToJsonString());
            Check.Equal("Requested", json["Attributes"]!.GetValue<string>(), "Real writer records the effect before send");
            Check.Equal("  Valeur exacte  ", json["AttributeChanges"]![0]!["After"]!.GetValue<string>(), "Durable value preserves exact spaces");
            var source = AttributeMutationRules.ReadReceipt(path, File.ReadAllBytes(path), DateTimeOffset.UtcNow);
            Check.Equal("attributes", source.Receipt.Kind, "Never classified as join");
            Check.Equal("uncertain", source.Receipt.Status, "A pre-send interruption is unresolved");
            Check.True(AttributeMutationRules.SameTarget(request.Attributes!.Target, source.Plan.Target), "Tuple survives reopening");
            Check.False(source.Receipt.RestartRequired, "Attributes never require a reboot");
            var forged = json.DeepClone().AsObject(); forged["Phase"] = "Verified"; forged["Code"] = 30; forged["Attributes"] = "Confirmed";
            gp.AdapterRaw(request.ReceiptId, forged.ToJsonString());
            Check.False(GpHistory.Read(gp.Root).Entries.Single().Readable, "Changing phase and effect without native after-proof cannot create success");
        }
        finally { Directory.Delete(config, true); Directory.Delete(gp.Root, true); }
    }

    [Test]
    public void ActualFinalDecoratorRequiresItsRetainedNativeProofAndClosedSnapshot()
    {
        var config = LiveTestConfig.Write(LiveTestConfig.NoRandom); var gp = new GpFixture();
        try
        {
            var request = AttributeFixture.Request(config); var native = new PowerShellMutationGateway(config, receiptGpRoot: gp.Root);
            var json = AttributeFixture.Render(native, request, "Verified", 30);
            var method = typeof(PowerShellMutationGateway).GetMethod("ApplyAttributeReceipt", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var outcome = new MutationOutcome(MutationStatus.Succeeded, 30, "Fixture confirmed", false, request.ComputerGuid);
            try { method.Invoke(native, [json, request, outcome]); throw new TestFailureException("No success without proof"); }
            catch (TargetInvocationException error) when (error.InnerException is PestoException) { }
            var proof = AttributeFixture.Applied(request.Attributes!, AttributeFixture.Snapshot(TimeProvider.System));
            var held = (Dictionary<string, AttributeSnapshot>)typeof(PowerShellMutationGateway).GetField("attributeProofs", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(native)!;
            held[request.ReceiptId] = proof; method.Invoke(native, [json, request, outcome]);
            gp.AdapterRaw(request.ReceiptId, json.ToJsonString());
            Check.True(GpHistory.Read(gp.Root).Entries.Single().Readable, "Actual final decorator and reader agree");
            foreach (Action<JsonObject> corrupt in new Action<JsonObject>[] { r => r["AttributeObservation"]!["Values"]!["Description"] = "different",
                         r => r["AttributeObservation"]!["Target"]!["ComputerGuid"] = System.Guid.NewGuid().ToString("D"),
                         r => r["AttributeObservation"]!["Unknown"] = true, r => r["AttributeChanges"]![0]!["Other"] = "injected",
                         r => r["RestartRequired"] = true, r => r["NewName"] = AttributeFixture.Computer,
                         r => r["Kind"] = "join", r => r["ReservationId"] = "reservation-injected" })
            {
                var changed = json.DeepClone().AsObject(); corrupt(changed); gp.AdapterRaw(request.ReceiptId, changed.ToJsonString());
                Check.False(GpHistory.Read(gp.Root).Entries.Single().Readable, "A contradictory or extended snapshot stays unreadable");
            }
        }
        finally { Directory.Delete(config, true); Directory.Delete(gp.Root, true); }
    }

    [Test]
    public void ActualV1CopiedPlanWithoutActionIsAttributesAndExplicitActionMustAgree()
    {
        var gp = new GpFixture(); var id = System.Guid.NewGuid();
        try
        {
            // Matches Pesto-Safety.Start-PestoIntervention's closed copy, followed by Extensions.Set-PestoEffect.
            var receipt = JsonNode.Parse(GpFixture.V1Json(id, "Uncertain", false, false, "2026-10-23T08:00:00Z", 97, null))!.AsObject();
            var plan = receipt["Plan"]!.AsObject(); plan["Nouveau_Nom"] = AttributeFixture.Computer; plan["TargetOUGuid"] = "";
            receipt["Protection"] = "NotChanged"; receipt["Attributes"] = "Requested";
            receipt["AttributeChanges"] = JsonSerializer.SerializeToNode(new[] { new AttributeChange("description", "Before", "After", "") });
            gp.V1Raw(id, receipt.ToJsonString()); var actual = GpHistory.Read(gp.Root).Entries.Single();
            Check.True(actual.Readable, "The real V1 writer output remains readable");
            Check.Equal("attributes", actual.Receipt.Kind, "Missing Action is not misclassified as a join");
            Check.Equal("uncertain", actual.Receipt.Status, "Requested stays unresolved");
            plan["Action"] = "Attributes"; plan["Changes"] = receipt["AttributeChanges"]!.DeepClone(); plan["Metadata"] = null;
            gp.V1Raw(id, receipt.ToJsonString()); Check.True(GpHistory.Read(gp.Root).Entries.Single().Readable, "Explicit Action and equal closed diff are also recognized");
            foreach (Action<JsonObject> corrupt in new Action<JsonObject>[] { r => r["Plan"]!["Action"] = "Join",
                         r => r["Plan"]!["Changes"]![0]!["After"] = "Other", r => r["Plan"]!["Renommer"] = true,
                         r => r["Plan"]!["OU_Destination"] = "OU=Other,DC=example,DC=local", r => r["Phase"] = "PendingRestart",
                         r => r["Phase"] = "Verified", r => r["AttributeChanges"]![0]!["Unknown"] = true })
            {
                var changed = receipt.DeepClone().AsObject(); corrupt(changed); gp.V1Raw(id, changed.ToJsonString());
                Check.False(GpHistory.Read(gp.Root).Entries.Single().Readable, "Mixed actions and forged effects fail closed");
            }
        }
        finally { Directory.Delete(gp.Root, true); }
    }

    [Test]
    public void AttributeWorkerHasOneWriteSiteAndUsesBoundedCompiledBootstrap()
    {
        var script = PowerShellMutationGateway.AttributesWorkerScript;
        Check.Equal(1, Regex.Matches(script, @"(?m)^\s*Set-ADObject\s").Count, "One possible targeted write, no retry branch");
        foreach (var command in new[] { "Add-Computer", "Rename-Computer", "New-ADComputer", "Remove-ADComputer", "Move-ADObject", "Set-Acl", "Restart-Computer" })
            Check.False(script.Contains(command, StringComparison.OrdinalIgnoreCase), "No unrelated effect: " + command);
        Check.Contains("Get-ADComputer -Identity $guid", script, "Target is read by GUID");
        Check.Contains("$latest=Read-Target;Assert-Changes $latest", script, "Before values are rechecked after slow group reads");
        Check.Contains("GUID managedBy absent.", script, "Worker itself requires reference authority");
        Check.Contains("$result.MutationMayHaveStarted=$true", script, "Send boundary is explicit");
        var worker = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.PowerShellFixedWorker")!;
        var start = (ProcessStartInfo)worker.GetMethod("StartInfo", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)!.Invoke(null, [script])!;
        Check.True(start.ArgumentList.Sum(x => x.Length + 3) < 8000, "The complete script does not overflow CreateProcess's command-line limit");
        var decoded = Encoding.Unicode.GetString(Convert.FromBase64String(start.ArgumentList.Last()));
        Check.Contains("Pesto", decoded, "A live compiled worker remains detectable before acknowledgement or observation");
        Check.False(decoded.Contains("Set-ADObject", StringComparison.Ordinal), "Only the compiled hash bootstrap is in the command line");
    }
}
