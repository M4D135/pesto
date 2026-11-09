using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class AutomationTests
{
    [Test]
    public void ClosedArgumentsNeverAcceptSecretsCommandsOrImplicitExecution()
    {
        var plan = Path.GetFullPath("test-plan.json");
        foreach (var args in new string[][] { ["--cli", "unknown"], ["--cli", "join", "--password", "SECRET-SENTINEL"],
            ["--cli", "move", "--execute"], ["--cli", "move", "--execute", "--plan", plan],
            ["--cli", "inspect", "--execute"], ["--cli", "rename", "--confirm-entra-leave"],
            ["--cli", "move", "--computer", "A", "--computer", "B"], ["--cli", "rename", "--script", "SECRET-SENTINEL"] })
        {
            var error = Check.Pesto(() => PestoCliOptions.Parse(args), "automation.arguments", "Closed CLI rejects unsafe or incomplete intent");
            Check.False(error.Message.Contains("SECRET-SENTINEL", StringComparison.Ordinal), "No raw argument echoed");
        }
        var allowed = PestoCliOptions.Parse(["--cli", "move", "--execute", "--plan", plan, "--idempotency-key", "campaign/host:1"]);
        Check.True(allowed.Execute, "Explicit plan and key admitted");
    }

    [Test]
    public void PreparationExportsReviewedIdentityAndNeverCreatesAnExecutionIntent()
    {
        using var w = new AutomationFixture(); var plan = w.Prepare();
        Check.Equal(AutomationFixture.AdGuid, plan.ComputerGuid, "Observed source GUID retained");
        Check.Equal(AutomationFixture.SourceOu, plan.SourceOu, "Observed source OU retained");
        Check.Equal(w.Context.ProfileSid, plan.ProfileSid, "Original operator profile retained across explicit UAC context");
        Check.Equal(w.Context.OperatorSid, plan.OperatorSid, "Effective operator remains distinct");
        Check.True(plan.ProfileSid != plan.OperatorSid, "No artificial requirement to impersonate original profile");
        Check.Equal(0, w.Native.Sends, "No business send from preparation");
        Check.Equal(0, w.Native.Leases, "Portable preparation does not acquire a share lease");
        Check.False(System.IO.Directory.Exists(w.Gp), "No idempotent Started or fake receipt before --execute");
        Check.Equal(plan.Integrity, AutomationPlanRules.Read(w.PlanPath).Integrity, "Portable file validates its exact closed contents");
        Check.False(File.ReadAllText(w.PlanPath).Contains("fixture-authority", StringComparison.Ordinal), "Ephemeral native tokens never exported");
    }

    [Test]
    public void AcceptedRenameReturns3010AndReplaysLocallyEvenAfterPlanExpiration()
    {
        using var w = new AutomationFixture(); w.Prepare();
        var result = w.Run(w.ExecuteOptions());
        Check.Equal(3010, result.ExitCode, "Accepted rename is pending reboot, not success zero: " + result.Message);
        Check.Equal("PendingRestart", result.State, "Pending state preserved");
        Check.True(result.RestartRequired, "No actual reboot invoked");
        Check.Equal(1, w.Native.Sends, "Exactly one command in the fake native adapter");
        var calls = w.Factories; var reads = w.Directory.Reads;
        w.Clock.Advance(TimeSpan.FromDays(3));
        w.BeforeFactory = () => throw new TestFailureException("Replay must never construct an adapter");
        var replay = w.Run(w.ExecuteOptions());
        Check.True(replay.Replayed, "Stored result explicitly labelled replay");
        Check.Equal(3010, replay.ExitCode, "Original durable result preserved after expiry");
        Check.Equal(result.OperationId, replay.OperationId, "Original operation ID retained");
        Check.Equal(calls, w.Factories, "Factory not called again"); Check.Equal(reads, w.Directory.Reads, "No AD read on replay");
    }

    [Test]
    public void VerifiedMoveReturnsZeroOnlyWithTheMatchingDurableReceipt()
    {
        using var w = new AutomationFixture(); w.Prepare("move");
        var result = w.Run(w.ExecuteOptions("move"));
        Check.Equal(0, result.ExitCode, "Verified move has a meaningful zero code: " + result.Message);
        Check.Equal(30, result.EngineCode, "Native business code retained");
        Check.False(result.RestartRequired, "Moving AD needs no reboot");
        Check.True(File.Exists(Path.Combine(w.Gp, "V2", "receipts", result.OperationId + ".json")), "Actual disk receipt precedes zero");
    }

    [Test]
    public void CachedSuccessAndAcceptanceRequireTheSameBusinessReceiptBytesBeforeAnyFactory()
    {
        foreach (var action in new[] { "rename", "move" })
        foreach (var change in new[] { "deleted", "altered", "truncated" })
        {
            using var w = new AutomationFixture(); w.Prepare(action);
            var result = w.Run(w.ExecuteOptions(action));
            Check.Equal(action == "move" ? 0 : 3010, result.ExitCode, "Initial result proved: " + result.Message);
            var path = Path.Combine(w.Gp, "V2", "receipts", result.OperationId + ".json");
            var finalPath = Path.Combine(w.Gp, "V2", "automation", AutomationJournal.KeyHash(w.ExecuteOptions(action).IdempotencyKey!) + ".result.json");
            var final = JsonNode.Parse(File.ReadAllText(finalPath))!.AsObject();
            Check.Equal(AutomationPlanRules.Digest(File.ReadAllBytes(path)), final["ReceiptSha256"]!.GetValue<string>(), "Completed pins exact business bytes");
            if (change == "deleted") File.Delete(path);
            else if (change == "truncated") File.WriteAllText(path, "{}");
            else { var receipt = JsonNode.Parse(File.ReadAllText(path))!.AsObject(); receipt["Message"] = "Changed later"; File.WriteAllText(path, receipt.ToJsonString()); }
            var factories = w.Factories; var reads = w.Directory.Reads;
            w.BeforeFactory = () => throw new TestFailureException("Missing business evidence must never recreate the adapter");
            var replay = w.Run(w.ExecuteOptions(action));
            Check.Equal(97, replay.ExitCode, "Deleted or changed evidence cannot preserve a positive cached exit");
            Check.True(replay.Replayed, "Unknown historical attempt remains explicitly identified");
            Check.Equal(factories, w.Factories, "Replay proof is local only"); Check.Equal(reads, w.Directory.Reads, "No directory read");
            Check.Equal(1, w.Native.Sends, "The uncertain cached intent never sends again");
        }
    }

    [Test]
    public void ForgedCompletedCannotPromotePendingOrRebindIdentityEvenWithARecomputedReceiptHash()
    {
        foreach (var change in new[] { "missingHash", "promote", "phase", "NewName", "TargetOu", "ComputerGuid", "Domain", "Dc", "ConfigurationSha256", "MachineId", "InitialOu", "TargetOuGuid" })
        {
            using var w = new AutomationFixture(); w.Prepare(); var options = w.ExecuteOptions();
            var result = w.Run(options); Check.Equal(3010, result.ExitCode, "Initial pending receipt proved: " + result.Message);
            var path = Path.Combine(w.Gp, "V2", "receipts", result.OperationId + ".json");
            var finalPath = Path.Combine(w.Gp, "V2", "automation", AutomationJournal.KeyHash(options.IdempotencyKey!) + ".result.json");
            var final = JsonNode.Parse(File.ReadAllText(finalPath))!.AsObject();
            var receipt = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            if (change == "missingHash") final.Remove("ReceiptSha256");
            else if (change == "promote")
            { final["Result"]!["State"] = "Verified"; final["Result"]!["ExitCode"] = 0; final["Result"]!["EngineCode"] = 30; final["Result"]!["RestartRequired"] = false; }
            else
            {
                if (change == "phase") { receipt["Phase"] = "Verified"; receipt["Code"] = 30; receipt["RestartRequired"] = false; }
                else receipt[change] = change switch
                {
                    "NewName" => "P111301PAINF011", "TargetOu" or "InitialOu" => AutomationFixture.TargetOu,
                    "ComputerGuid" or "MachineId" or "TargetOuGuid" => "dddddddd-dddd-dddd-dddd-dddddddddddd",
                    "Domain" => "other.local", "Dc" => "dc02.example.local", _ => new string('f', 64),
                };
                File.WriteAllText(path, receipt.ToJsonString());
                final["ReceiptSha256"] = AutomationPlanRules.Digest(File.ReadAllBytes(path));
            }
            File.WriteAllText(finalPath, final.ToJsonString());
            var factories = w.Factories; var reads = w.Directory.Reads;
            var replay = w.Run(options);
            Check.Equal(97, replay.ExitCode, "Forged result cannot stand in for planned proof: " + change);
            Check.Equal(factories, w.Factories, "No new adapter"); Check.Equal(reads, w.Directory.Reads, "No new AD read");
            Check.Equal(1, w.Native.Sends, "No replay after invalid result");
        }
    }

    [Test]
    public void FirstPositiveResultMustAlreadyMatchTheReviewedPlanIdentity()
    {
        foreach (var field in new[] { "ComputerGuid", "Domain", "Dc", "ConfigurationSha256", "MachineId", "InitialOu" })
        {
            using var w = new AutomationFixture(); w.Prepare();
            w.Native.ChangeDurableReceipt = receipt => receipt[field] = field switch
            {
                "ComputerGuid" or "MachineId" => "dddddddd-dddd-dddd-dddd-dddddddddddd",
                "Domain" => "other.local", "Dc" => "dc02.example.local", "InitialOu" => AutomationFixture.TargetOu,
                _ => new string('f', 64),
            };
            var result = w.Run(w.ExecuteOptions());
            Check.Equal(97, result.ExitCode, "An exact transport result cannot hide a foreign durable identity: " + field);
            var factories = w.Factories;
            Check.Equal(97, w.Run(w.ExecuteOptions()).ExitCode, "Incoherent first result remains blocked");
            Check.Equal(factories, w.Factories, "No new adapter after the inconsistent receipt");
        }
    }

    [Test]
    public void ProvenRefusalNeverBecomesSuccessAndItsKeyCannotExecuteAgain()
    {
        using var w = new AutomationFixture(); w.Prepare(); w.Native.Status = MutationStatus.Failed;
        var result = w.Run(w.ExecuteOptions());
        Check.Equal(96, result.ExitCode, "Proven no-send refusal"); Check.False(result.MutationStarted, "No business effect claimed");
        var replay = w.Run(w.ExecuteOptions());
        Check.Equal(96, replay.ExitCode, "Refusal cached without retry"); Check.True(replay.Replayed, "Refusal key is final");
        Check.Equal(1, w.Native.Sends, "No automatic second attempt even after safe refusal");
    }

    [Test]
    public void MissingDurableReceiptLostReplyAndUnrecordableFinalResultAlwaysReturn97()
    {
        foreach (var failure in new[] { "receipt", "reply", "final" })
        {
            using var w = new AutomationFixture(); w.Prepare();
            w.Native.OmitReceipt = failure == "receipt"; w.Native.ThrowAfterSend = failure == "reply"; w.Native.FailFinalWrite = failure == "final";
            var result = w.Run(w.ExecuteOptions());
            Check.Equal(97, result.ExitCode, "Cannot report acceptance without all durable evidence: " + failure);
            var factories = w.Factories; var repeat = w.Run(w.ExecuteOptions());
            Check.Equal(97, repeat.ExitCode, "Unknown outcome remains unknown after process restart");
            Check.Equal(factories, w.Factories, "No adapter creation to replay unknown action"); Check.Equal(1, w.Native.Sends, "No retry");
        }
    }

    [Test]
    public void BareNativeZeroIsNeverAnAutomationSuccess()
    {
        using var w = new AutomationFixture(); w.Prepare(); w.Native.Status = MutationStatus.Succeeded; w.Native.Code = 0;
        Check.Equal(97, w.Run(w.ExecuteOptions()).ExitCode, "Exit0 requires Verified30/33, not a bare transport zero");
    }

    [Test]
    public void DurableStartedSurvivesInterruptionAndPreventsAdapterCreation()
    {
        using var w = new AutomationFixture(); var plan = w.Prepare(); var opts = w.ExecuteOptions();
        using (var journal = new AutomationJournal(w.Context, opts.IdempotencyKey!))
            _ = journal.Begin(plan, AutomationJournal.PayloadHash(plan, w.Context, false, null), false, null, w.Clock.GetUtcNow());
        var before = w.Factories;
        var result = w.Run(opts);
        Check.Equal(97, result.ExitCode, "Started without Completed is uncertain"); Check.True(result.Replayed, "Existing intention disclosed");
        Check.Equal(before, w.Factories, "No new adapter after interruption"); Check.Equal(0, w.Native.Sends, "No replay, even when this fixture knows no send occurred");
    }

    [Test]
    public void TornIntentOrFinalRecordStaysBlockedWithoutNetwork()
    {
        foreach (var which in new[] { "request", "result" })
        {
            using var w = new AutomationFixture(); var plan = w.Prepare(); var opts = w.ExecuteOptions();
            using (var journal = new AutomationJournal(w.Context, opts.IdempotencyKey!))
                _ = journal.Begin(plan, AutomationJournal.PayloadHash(plan, w.Context, false, null), false, null, w.Clock.GetUtcNow());
            File.WriteAllText(Path.Combine(w.Gp, "V2", "automation", AutomationJournal.KeyHash(opts.IdempotencyKey!) + "." + which + ".json"), "{}");
            var before = w.Factories; var result = w.Run(opts);
            Check.Equal(97, result.ExitCode, "Torn durable evidence never opens a fresh attempt"); Check.Equal(before, w.Factories, "No network factory");
        }
    }

    [Test]
    public void LegacyV1KeyAndDifferentIntentCannotBeReused()
    {
        using var w = new AutomationFixture(); var plan = w.Prepare(); var opts = w.ExecuteOptions();
        var folder = Path.Combine(w.Gp, "Automation"); System.IO.Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, AutomationJournal.KeyHash(opts.IdempotencyKey!) + ".json"), "{\"Status\":\"Started\"}");
        var before = w.Factories; Check.Equal(96, w.Run(opts).ExitCode, "An existing V1 key cannot be adopted by V2");
        Check.Equal(before, w.Factories, "Legacy evidence refusal occurs before network");
        File.Delete(Path.Combine(folder, AutomationJournal.KeyHash(opts.IdempotencyKey!) + ".json"));
        using (var journal = new AutomationJournal(w.Context, opts.IdempotencyKey!))
            _ = journal.Begin(plan, AutomationJournal.PayloadHash(plan, w.Context, false, null), false, null, w.Clock.GetUtcNow());
        var modified = AutomationPlanRules.Seal(plan with { NewName = "P111301PAINF011" });
        File.Delete(w.PlanPath); AutomationPlanRules.Write(w.PlanPath, modified);
        Check.Equal(96, w.Run(opts).ExitCode, "A coherent new plan cannot reuse a prior key"); Check.Equal(before, w.Factories, "Conflicting payload rejected locally");
    }

    [Test]
    public void ExpiredTamperedWrongProfileOrChangedConfigurationRefuseBeforeFactory()
    {
        foreach (var change in new[] { "expiry", "tamper", "profile", "operator", "machine", "config" })
        {
            using var w = new AutomationFixture(); w.Prepare(); var before = w.Factories;
            switch (change)
            {
                case "expiry": w.Clock.Advance(TimeSpan.FromDays(2)); break;
                case "tamper": File.WriteAllText(w.PlanPath, File.ReadAllText(w.PlanPath).Replace(AutomationFixture.NewName, "P111301PAINF011", StringComparison.Ordinal)); break;
                case "profile": w.Context = w.Context with { ProfileSid = "S-1-5-21-100-200-300-1002" }; break;
                case "operator": w.Context = w.Context with { OperatorSid = "S-1-5-21-100-200-300-1002" }; break;
                case "machine": w.Context = w.Context with { MachineId = Guid.NewGuid().ToString("D") }; break;
                default: w.ChangeConfiguration(json => json["POLICY"]!["MaxBatch"] = 4); break;
            }
            Check.Equal(96, w.Run(w.ExecuteOptions()).ExitCode, "Invalid reviewed intent rejected: " + change);
            Check.Equal(before, w.Factories, "No network factory on invalid intent"); Check.Equal(0, w.Native.Sends, "No mutation");
        }
    }

    [Test]
    public void DoubleOptInHklmCredentialAndElevationAreCheckedBeforeAnyAdapter()
    {
        foreach (var blocker in new[] { "flag", "gpo", "incident", "credential", "elevation", "membership", "debug" })
        {
            using var w = new AutomationFixture();
            switch (blocker)
            {
                case "flag": w.ChangeConfiguration(json => json["POLICY"]!["UnattendedOperationsEnabled"] = false); break;
                case "gpo": w.Managed = new(DisableUnattendedOperations: true); break;
                case "incident": w.Managed = new(IncidentMode: true); break;
                case "credential": w.Context = w.Context with { ExplicitCredentialAvailable = false }; break;
                case "elevation": w.Context = w.Context with { AlreadyElevated = false }; break;
                case "membership": w.Context = w.Context with { OperatorDomainJoined = null }; break;
                default: w.ChangeConfiguration(json => json["DEBUG"]!["GUI"] = true); break;
            }
            var result = w.Run(w.PrepareOptions());
            Check.Equal(96, result.ExitCode, "Admission refused before network: " + blocker);
            Check.Equal(0, w.Factories, "No network factory for disabled unattended policy or missing identity");
        }
    }

    [Test]
    public void FreshNativeIdentityAndNewEntraEffectCannotReplaceTheExportedIntent()
    {
        foreach (var change in new[] { "guid", "ou", "dc", "entra" })
        {
            using var w = new AutomationFixture(); w.Prepare();
            var old = w.Directory.Computers[AutomationFixture.Computer];
            switch (change)
            {
                case "guid": w.Directory.Computers[old.Name] = old with { Guid = Guid.NewGuid().ToString("D") }; break;
                case "ou": w.Directory.Computers[old.Name] = old with { Ou = AutomationFixture.TargetOu }; break;
                case "dc": w.Directory.DcName = "dc02.example.local"; break;
                default: w.Native.EntraState = "hybrid"; break;
            }
            var result = w.Run(w.ExecuteOptions());
            Check.Equal(96, result.ExitCode, "No new effect or target silently adopted: " + change);
            Check.Equal(0, w.Native.Sends, "Preflight changed intent never sends");
        }
    }

    [Test]
    public void CoordinatedRenameAcquiresItsFixedNameOnlyAfterStartedAndVerifiesItAgain()
    {
        using var w = new AutomationFixture();
        w.ChangeConfiguration(json => json["POLICY"]!["CoordinationRoot"] = Path.Combine(w.Root, "share-never-created"));
        w.Prepare(); Check.Equal(0, w.Native.Leases, "Export-only preparation acquires no share lease");
        var result = w.Run(w.ExecuteOptions());
        Check.Equal(3010, result.ExitCode, "Confirmed exact name can be coordinated: " + result.Message);
        Check.Equal(1, w.Native.Leases, "One exact name acquired, no retarget");
        Check.True(w.Native.LeaseVerifications >= 2, "Lease checked at fresh preparation and execution");
        Check.Equal(AutomationFixture.NewName, w.Native.Last!.NameReservation!.Name, "Lease cannot replace the reviewed name");
    }

    [Test]
    public void JoinUsesTheGlobalAliasSeriesAndKeepsTheNameBeforeExecute()
    {
        using var w = new AutomationFixture(); w.Context = w.Context with { OperatorDomainJoined = false };
        w.Directory.Computers.Clear(); w.Directory.Aliases = ["P111301PR765001", "P111301PR765002"];
        var options = new PestoCliOptions("join", Type: "P", SiteCode: "PR", ServiceCode: "765", OutPlanPath: w.PlanPath);
        var prepared = w.Run(options);
        Check.Equal(0, prepared.ExitCode, "Global series can be prepared: " + prepared.Message);
        Check.Equal("P111301PR765003", prepared.Plan!.NewName, "All aliases already occupied are excluded before display");
        Check.Equal("P111301PR765*", w.Directory.ObservedPattern, "Native reader gets one fixed naming series");
        Check.Equal(0, w.Native.Sends, "No join while calculating its name");
        var result = w.Run(w.ExecuteOptions("join"));
        Check.Equal(3010, result.ExitCode, "Accepted join remains pending reboot: " + result.Message);
        Check.Equal(prepared.Plan.NewName, w.Native.Last!.NewName, "Exact exported name is sent");
    }

    [Test]
    public void JoinCannotChangeItsCandidateOrBypassPreprodAndUnsupportedUnattendedPolicies()
    {
        using var w = new AutomationFixture(); w.Context = w.Context with { OperatorDomainJoined = false }; w.Directory.Computers.Clear();
        var options = new PestoCliOptions("join", Type: "P", SiteCode: "PR", ServiceCode: "765", OutPlanPath: w.PlanPath);
        var prepared = w.Run(options); Check.Equal(0, prepared.ExitCode, "Prepared initial join");
        w.Directory.Aliases = [prepared.Plan!.NewName];
        Check.Equal(96, w.Run(w.ExecuteOptions("join")).ExitCode, "Name collision refuses rather than choosing a new number");
        Check.Equal(0, w.Native.Sends, "No silent replacement join");
        using var preprod = new AutomationFixture(); preprod.Context = preprod.Context with { OperatorDomainJoined = false };
        Check.Equal(96, preprod.Run(new("join", Type: "P", SiteCode: "PA", ServiceCode: "INF")).ExitCode, "Preprod enforces its exact site/service");
        using var reserved = new AutomationFixture(); reserved.Context = reserved.Context with { OperatorDomainJoined = false };
        reserved.ChangeConfiguration(json => json["POLICY"]!["ReserveNamesInAD"] = true);
        Check.Equal(96, reserved.Run(options with { OutPlanPath = null }).ExitCode, "V1 unattended reservation restriction preserved");
        Check.Equal(0, reserved.Factories, "Restriction checked before network");
    }

    [Test]
    public void CampaignApprovalPinsSeparateSignerAndTheCompleteReviewedV2Intent()
    {
        using var w = new AutomationFixture();
        var metadata = Path.Combine(w.Root, "metadata.json"); File.WriteAllText(metadata, "{\"Campaign\":\"pilot-2026\",\"Stage\":\"canary\"}");
        var prepared = w.Run(w.PrepareOptions() with { MetadataPath = metadata });
        Check.Equal(0, prepared.ExitCode, "Metadata carried into portable plan"); var plan = prepared.Plan!;
        using var rsa = RSA.Create(2048);
        var csr = new CertificateRequest("CN=Pesto fixture approver", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var certificate = csr.CreateSelfSigned(w.Clock.GetUtcNow().AddDays(-1), w.Clock.GetUtcNow().AddDays(1));
        const string approver = "S-1-5-21-100-200-300-900";
        var policy = JsonSerializer.Serialize(new { Schema = 1, Campaigns = new[] { "pilot-2026" }, Signers = new[] { new { CertificateSHA256 = AutomationPlanRules.Digest(certificate.RawData), Sid = approver } } });
        string Approval(string sid, string hash, DateTimeOffset? expiry = null)
        {
            var payload = JsonSerializer.SerializeToUtf8Bytes(new { Schema = 1, Purpose = "PestoCampaignApproval", Campaign = "pilot-2026", ApproverSid = sid,
                CreatedUtc = w.Clock.GetUtcNow(), ExpiresUtc = expiry ?? w.Clock.GetUtcNow().AddMinutes(15), PlanHashes = new[] { hash } });
            return JsonSerializer.Serialize(new { Schema = 1, Payload = Convert.ToBase64String(payload), Certificate = Convert.ToBase64String(certificate.RawData),
                Signature = Convert.ToBase64String(rsa.SignData(payload, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) });
        }
        var valid = Approval(approver, plan.Integrity);
        AutomationCampaignApproval.Require(policy, valid, plan, w.Context.OperatorSid, w.Clock.GetUtcNow());
        foreach (var invalid in new[] { Approval(approver, new string('a', 64)), Approval(approver, plan.Integrity, w.Clock.GetUtcNow().AddSeconds(-1)), Approval(w.Context.OperatorSid, plan.Integrity) })
            Check.Pesto(() => { AutomationCampaignApproval.Require(policy, invalid, plan, w.Context.OperatorSid, w.Clock.GetUtcNow()); return null; }, "automation.approval", "Wrong plan/expired/same-operator agreement rejected");
        var sameOperatorPolicy = policy.Replace(approver, w.Context.OperatorSid, StringComparison.Ordinal);
        Check.Pesto(() => { AutomationCampaignApproval.Require(sameOperatorPolicy, Approval(w.Context.OperatorSid, plan.Integrity), plan, w.Context.OperatorSid, w.Clock.GetUtcNow()); return null; },
            "automation.approval", "An HKLM-listed signer still cannot approve their own operation");
        w.Managed = new(CampaignApprovalJson: policy);
        var before = w.Factories; Check.Equal(96, w.Run(w.ExecuteOptions()).ExitCode, "Missing required agreement blocks before adapter");
        Check.Equal(before, w.Factories, "No network without campaign approval");
        var path = Path.Combine(w.Root, "approval.json"); File.WriteAllText(path, valid);
        Check.Equal(3010, w.Run(w.ExecuteOptions() with { ApprovalPath = path }).ExitCode, "Valid exact approval reaches existing confirmed pipeline");
    }

    [Test]
    public void MetadataAndPortableDocumentSchemasRejectDuplicatesUnknownsAndSecretShapes()
    {
        using var w = new AutomationFixture(); var plan = w.Prepare();
        foreach (var body in new[] { "{\"Ticket\":\"123\"}", "{\"Campaign\":\"password=secret\"}", "{\"Stage\":\"a\",\"Stage\":\"b\"}" })
        {
            var path = Path.Combine(w.Root, "invalid-metadata.json"); File.WriteAllText(path, body);
            Check.Pesto(() => AutomationPlanRules.ReadMetadata(path), "automation.plan", "Metadata is closed and secret-free");
        }
        var original = File.ReadAllText(w.PlanPath);
        File.WriteAllText(w.PlanPath, original.Insert(1, "\"HiddenCommand\":\"ignored\","));
        Check.Pesto(() => AutomationPlanRules.Read(w.PlanPath), "automation.plan", "Unknown portable field refused, not ignored");
        File.WriteAllText(w.PlanPath, original.Insert(1, "\"Schema\":1,"));
        Check.Pesto(() => AutomationPlanRules.Read(w.PlanPath), "automation.plan", "Duplicate portable field refused");
        Check.Equal(plan.Integrity, AutomationCampaignApproval.PlanHash(plan), "Campaign hash covers entire reviewed V2 document");
    }

    [Test]
    public void NativeAutomationInventoryAndTransportAreReadOnlyBoundedAndNotCommandLinePayloads()
    {
        var script = PowerShellDirectoryGateway.ConstantScript;
        Check.Contains("'automationNames'", script, "Actual native series reader present");
        Check.Contains("SamAccountName,DNSHostName", script, "All three V1 aliases read");
        Check.Contains("-SearchBase $root -SearchScope Subtree", script, "Domain inventory, not site-only absence assumption");
        Check.Contains("-ResultSetSize ($max+1)", script, "Incomplete bounded read detected");
        Check.False(script.Contains("Set-ADComputer", StringComparison.Ordinal), "The inventory worker never mutates AD");
        var worker = typeof(PowerShellDirectoryGateway).Assembly.GetType("Pesto.Engine.Live.PowerShellFixedWorker")!;
        var start = (System.Diagnostics.ProcessStartInfo)worker.GetMethod("StartInfo")!.Invoke(null, [script])!;
        Check.True(start.ArgumentList.Sum(arg => arg.Length) < 8000, "Large complete reader travels through bounded verified stdin bootstrap");
        Check.False(string.Join(' ', start.ArgumentList).Contains("P111301", StringComparison.Ordinal), "No target or credential in command-line arguments");
    }
}
