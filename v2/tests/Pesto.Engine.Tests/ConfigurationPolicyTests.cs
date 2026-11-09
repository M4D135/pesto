using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

/// <summary>Representative of the exact V1 contract, including restrictions that V2 must refuse rather than drop.</summary>
internal static class ConfigurationPolicyFixture
{
    public static JsonObject Create()
    {
        var result = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject();
        var conf = result["CONF"]![0]!;
        conf["EntraPolicy"] = "HybridOnly";
        conf["DsregLeaveOnMove"] = true;
        conf["ClearProtectionOnMove"] = false;
        conf["MoveRollbackOnRenameFail"] = false;
        conf["AllowHybridRepair"] = true;
        result["POLICY"] = JsonNode.Parse("""
            {"Schema":1,
             "Scenario":{"Schema":1,"Name":"Postes Paris","Required":["Type","SiteCode","ServiceCode","TargetOU"],
                "Allowed":{"Type":["P","S"],"SiteCode":"PA","ServiceCode":["INF","001"],"TargetOU":"OU=Paris,OU=Postes,DC=example,DC=local"},
                "Locked":{"SiteCode":"PA"}},
             "ExcludedNames":["SRV*","DC-*"],"ExcludedOUs":["OU=Serveurs,OU=Postes,DC=example,DC=local"],
             "ExcludedGroupGuids":["aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"],
             "CoordinationRoot":"\\\\files.example.local\\pesto","CoordinationRequired":true,
             "AllowPasswordTaskFallback":false,"AllowPrecreatedJoin":false,"AllowOfflineJoin":false,"BlockJoinOnClockSkew":true,
             "MaxReaders":1,"ReadAttempts":1,"MaxBatch":7,"NameReservationMinutes":240,"ReserveNamesInAD":true,
             "RandomNameEnabled":true,"RandomNameChoice":2,"LogRetentionDays":3650,
             "UnattendedJoinEnabled":false,"UnattendedOperationsEnabled":false,"IncidentMode":true,"AuditEventLogEnabled":true}
            """);
        return result;
    }
}

internal sealed class ConfigurationPolicyTests
{
    [Test]
    public void AllV1RestrictionsRoundTripThroughPreviewImportAndExportUnchanged()
    {
        var raw = ConfigurationPolicyFixture.Create();
        var service = new ProfileConfigurationService(Path.Combine(Path.GetTempPath(), "pesto-policy-import-" + Guid.NewGuid().ToString("N")), "origin", ConfigurationAccessMode.Live);
        var bundle = ConfigurationDocument.Export(raw.ToJsonString(), "policy.1");
        var preview = service.PreviewImport(bundle.ToJsonString());
        Check.False(File.Exists(service.ConfigurationPath), "preview cannot weaken or write a local policy");
        service.ApplyImport(Harness.Str(preview, "planId"), true);
        var exported = service.Export("policy.2")["configuration"]!;
        Check.Equal(ConfigurationDocument.Canonical(raw["POLICY"]!), ConfigurationDocument.Canonical(exported["POLICY"]!), "every policy key, type and scenario value retained");
        foreach (var field in new[] { "EntraPolicy", "DsregLeaveOnMove", "ClearProtectionOnMove", "MoveRollbackOnRenameFail", "AllowHybridRepair" })
            Check.Equal(raw["CONF"]![0]![field]!.ToJsonString(), exported["CONF"]![0]![field]!.ToJsonString(), "CONF guard retained: " + field);
        Check.Null(exported["CONF"]![0]!["ADM"], "operator account excluded without affecting policies");
        var validated = V1Config.ValidateText(exported.ToJsonString());
        Check.Equal("policy.incident", Check.Pesto(() => { validated.OperationPolicy.RequireSupported("move"); return null; }, "policy.incident", "imported incident restriction still blocks mutation").Code, "policy remains effective");
    }

    [Test]
    public void UnknownPolicyAndMisnamedSecurityFieldsAreRefusedInsteadOfDiscarded()
    {
        foreach (var key in new[] { "SharedCoordinationRoot", "Incidentmode", "FutureMandatoryGuard", "Secret" })
        {
            var raw = ConfigurationPolicyFixture.Create();
            raw["POLICY"]![key] = key == "Secret" ? "do-not-export" : "required";
            Check.Pesto(() => ConfigurationDocument.Export(raw.ToJsonString(), "1"), "config.invalid", "unrecognized policy cannot become a weaker export: " + key);
        }
        var wrongConf = ConfigurationPolicyFixture.Create();
        wrongConf["CONF"]![0]!.AsObject().Remove("EntraPolicy");
        wrongConf["CONF"]![0]!["entrapolicy"] = "Disabled";
        Check.Pesto(() => ConfigurationDocument.Sanitize(wrongConf.ToJsonString()), "config.invalid", "wrong case cannot drop a disabled Entra policy and restore a default");
        var wrongRoot = ConfigurationPolicyFixture.Create();
        var policy = wrongRoot["POLICY"]!.DeepClone(); wrongRoot.Remove("POLICY"); wrongRoot["policy"] = policy;
        Check.Pesto(() => ConfigurationDocument.Sanitize(wrongRoot.ToJsonString()), "config.invalid", "root policy cannot silently disappear");
    }

    [Test]
    public void ExplicitInvalidNullGuardsNeverBecomeDefaults()
    {
        foreach (var key in new[] { "IncidentMode", "BlockJoinOnClockSkew", "MaxBatch", "CoordinationRoot", "ExcludedNames" })
        {
            var raw = ConfigurationPolicyFixture.Create(); raw["POLICY"]![key] = null;
            Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "null guard refused: " + key);
        }
        var conf = ConfigurationPolicyFixture.Create(); conf["CONF"]![0]!["ClearProtectionOnMove"] = null;
        Check.Pesto(() => ConfigurationDocument.Sanitize(conf.ToJsonString()), "config.invalid", "null protection switch cannot be removed before validation");
        conf = ConfigurationPolicyFixture.Create(); conf["Configured"] = null;
        Check.Pesto(() => ConfigurationDocument.Sanitize(conf.ToJsonString()), "config.invalid", "null initialization flag does not become configured");
    }

    [Test]
    public void NullScenarioAndAbsentOrEmptyEntraPolicyRetainTheirV1Meaning()
    {
        var raw = ConfigurationPolicyFixture.Create();
        raw["POLICY"]!["Scenario"] = null;
        raw["CONF"]![0]!.AsObject().Remove("EntraPolicy");
        var clean = ConfigurationDocument.Sanitize(raw.ToJsonString());
        Check.True(clean["POLICY"]!.AsObject().ContainsKey("Scenario"), "explicit disabled scenario remains explicit");
        Check.Null(clean["POLICY"]!["Scenario"], "null scenario round trips");
        Check.False(clean["CONF"]![0]!.AsObject().ContainsKey("EntraPolicy"), "absent V1 HybridOnly default is not rewritten as Disabled");
        raw["CONF"]![0]!["EntraPolicy"] = "";
        clean = ConfigurationDocument.Sanitize(raw.ToJsonString());
        Check.Equal("", clean["CONF"]![0]!["EntraPolicy"]!.GetValue<string>(), "empty V1 HybridOnly default is retained");
        raw["POLICY"] = null;
        clean = ConfigurationDocument.Sanitize(raw.ToJsonString());
        Check.True(clean.ContainsKey("POLICY"), "explicit default policy retained");
        Check.Null(clean["POLICY"], "null policy is the V1 default, not fabricated settings");
    }

    [Test]
    public void ScenarioIsClosedAndLockTypesAndAllowedValuesRemainStrict()
    {
        var invalidScenarios = new[]
        {
            "\"mandatory\"",
            "{\"Schema\":1,\"Name\":\"Paris\",\"Required\":[],\"Allowed\":{},\"Locked\":{},\"Secret\":\"x\"}",
            "{\"Schema\":1,\"Name\":\"Paris\",\"Required\":[\"Unknown\"],\"Allowed\":{},\"Locked\":{}}",
            "{\"Schema\":1,\"Name\":\"Paris\",\"Required\":[],\"Allowed\":{\"SiteCode\":[\"PA\"]},\"Locked\":{\"SiteCode\":\"pa\"}}",
            "{\"Schema\":1,\"Name\":\"Paris\",\"Required\":[],\"Allowed\":{},\"Locked\":{\"SiteCode\":[\"PA\"]}}",
            "{\"Schema\":1,\"Name\":\"Paris\",\"Required\":[],\"Allowed\":{\"Type\":{\"Secret\":\"x\"}},\"Locked\":{}}"
        };
        foreach (var scenario in invalidScenarios)
        {
            var raw = ConfigurationPolicyFixture.Create(); raw["POLICY"]!["Scenario"] = JsonNode.Parse(scenario);
            Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "invalid scenario cannot be stripped into an accepted policy");
        }
    }

    [Test]
    public void V1PolicyListAndTextBoundsAreEnforcedWithoutTruncatingRestrictions()
    {
        var raw = ConfigurationPolicyFixture.Create();
        raw["POLICY"]!["ExcludedNames"] = new JsonArray(Enumerable.Range(0, 200).Select(i => (JsonNode?)JsonValue.Create("PC" + i)).ToArray());
        raw["POLICY"]!["Scenario"]!["Allowed"]!["Type"] = new JsonArray(Enumerable.Range(0, 200).Select(i => (JsonNode?)JsonValue.Create(i == 0 ? "P" : "V" + i)).ToArray());
        raw["POLICY"]!["Scenario"]!["Allowed"]!["TargetOU"] = new string('x', 4096);
        var clean = ConfigurationDocument.Sanitize(raw.ToJsonString());
        Check.Equal(200, clean["POLICY"]!["ExcludedNames"]!.AsArray().Count, "all 200 exclusions preserved");
        Check.Equal(4096, clean["POLICY"]!["Scenario"]!["Allowed"]!["TargetOU"]!.GetValue<string>().Length, "4096-character V1 policy value preserved");
        raw["POLICY"]!["ExcludedNames"]!.AsArray().Add("PC201");
        Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "201 exclusions refused as in V1");
        raw["POLICY"]!["ExcludedNames"]!.AsArray().RemoveAt(200);
        raw["POLICY"]!["Scenario"]!["Allowed"]!["Type"]!.AsArray().Add("V201");
        Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "201 scenario choices refused");
        raw["POLICY"]!["Scenario"]!["Allowed"]!["Type"]!.AsArray().RemoveAt(200);
        raw["POLICY"]!["Scenario"]!["Allowed"]!["TargetOU"] = new string('x', 4097);
        Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "overlong value refused rather than truncated");
    }
}
