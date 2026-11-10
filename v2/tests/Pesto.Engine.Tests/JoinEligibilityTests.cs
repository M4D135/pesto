using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class JoinEligibilityTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Preprod = "OU=Staging,OU=Postes,DC=example,DC=local";

    private sealed class World : IDisposable
    {
        public readonly FakeGateway Directory = new() { ChildOus = { [Container] = ["Paris-Nord", "Lyon-Sud"] } };
        public readonly FakeMutationGateway Mutation = new();
        public readonly string Root;
        public readonly IPestoBackend Backend;
        public World(bool production = false, string? configuration = null)
        {
            Root = LiveTestConfig.Write(configuration ?? (production ? LiveTestConfig.Production : LiveTestConfig.NoRandom));
            Backend = Harness.Live(Root, Directory, Mutation, new FixedClock(), Path.Combine(Root, "GP"));
        }
        public JsonNode Preview(string site = Preprod, string service = "765") => Harness.Call(Backend, "names.preview", new { purpose = "join", type = "P", site, service });
        public JsonNode Plan(JsonNode preview) => Harness.Call(Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        public void Dispose() => System.IO.Directory.Delete(Root, true);
    }

    [Test]
    public void MembershipBlocksBothJoinPathsBeforePreviewOrPreparationEvenWithoutAnAdObject()
    {
        foreach (var joined in new bool?[] { true, null })
        {
            using var w = new World(production: true);
            w.Directory.LocalComputerJoined = joined;
            var code = joined == true ? "join.alreadyJoined" : "join.membership_unknown";
            var session = Harness.Call(w.Backend, "session.info");
            foreach (var id in new[] { "join", "joinPrecreated" })
                Check.False(Harness.Arr(session, "capabilities").Single(c => c!["id"]!.GetValue<string>() == id)!["enabled"]!.GetValue<bool>(), "Membership closes " + id);
            Check.Pesto(() => w.Preview("PA", "INF"), code, "No join preview when membership is true or unknown");
            Check.Pesto(() => Harness.Call(w.Backend, "join.precreated.preview", new { name = "P111301PAINF001" }), code, "No precreated bypass");
            var generic = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
            Check.Pesto(() => w.Plan(generic), code, "A generic name preview cannot bypass the membership guard");
            Check.Equal(0, w.Mutation.Requests.Count, "No mutation requested");
        }
    }

    [Test]
    public void MembershipIsReadAgainAtExecution()
    {
        foreach (var joined in new bool?[] { true, null })
        {
            using var w = new World();
            var plan = w.Plan(w.Preview());
            w.Directory.LocalComputerJoined = joined;
            Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
                joined == true ? "join.alreadyJoined" : "join.membership_unknown", "Windows membership changed after confirmation");
            Check.Equal(0, w.Mutation.Requests.Count, "No mutation or reservation sent");
        }
    }

    [Test]
    public void PreproductionJoinOffersOnlyItsExactOuAndServiceWhileGeneralSitesRemainAvailable()
    {
        using var w = new World();
        var sites = Harness.Call(w.Backend, "directory.sites", new { purpose = "join" });
        Check.True(Harness.Bool(sites, "locked"), "Preproduction selection is fixed");
        Check.Equal(1, Harness.Arr(sites, "items").Count, "Only configured staging, although it is outside OUSite");
        Check.Equal(Preprod, Harness.Arr(sites, "items")[0]!["selector"]!.GetValue<string>(), "Exact configured OU");
        var services = Harness.Call(w.Backend, "directory.services", new { purpose = "join", site = Preprod });
        Check.Equal(1, Harness.Arr(services, "items").Count, "Only the configured staging service");
        Check.Equal("765", Harness.Arr(services, "items")[0]!["code"]!.GetValue<string>(), "PreprodSite is a service, not an OU or site code");
        var preview = w.Preview();
        Check.Equal("P111301PR765001", Harness.Str(preview, "name"), "V1 preproduction convention");
        Check.Equal(Preprod, Harness.Str(w.Plan(preview), "targetOU"), "Confirmed plan pins staging");
        Check.Equal(2, Harness.Arr(Harness.Call(w.Backend, "directory.sites"), "items").Count, "Rename/move retain both AD sites");
    }

    [Test]
    public void ProductionSiteServiceAndGenericPreviewCannotBypassPreproduction()
    {
        using var w = new World();
        Check.Pesto(() => w.Preview("PA", "INF"), "join.preprod", "Production site rejected at preview");
        Check.Pesto(() => w.Preview(service: "INF"), "join.preprod", "Another service rejected at preview");
        Check.Pesto(() => Harness.Call(w.Backend, "directory.services", new { purpose = "join", site = "PA" }), "join.preprod", "No production service list");
        var generic = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Pesto(() => w.Plan(generic), "join.preprod", "Omitting purpose cannot bypass prepare");
        var preview = w.Preview();
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId"), targetOU = "OU=Paris-Nord," + Container }),
            "preview.changed", "Target override refused");
        Check.Equal(0, w.Mutation.Requests.Count, "No mutation requested");
    }

    [Test]
    public void ProductionJoinStillOffersAndUsesOrdinaryAdSites()
    {
        using var w = new World(production: true);
        var sites = Harness.Call(w.Backend, "directory.sites", new { purpose = "join" });
        Check.False(Harness.Bool(sites, "locked"), "Production selection is free");
        Check.Equal(2, Harness.Arr(sites, "items").Count, "Production AD sites available");
        Check.Equal("OU=Paris-Nord," + Container, Harness.Str(w.Plan(w.Preview("PA", "INF")), "targetOU"), "Production join keeps selected site");
    }

    [Test]
    public void PreproductionUsesV1AliasesOrAnExplicitSiteAndNeverAnOuSuffixFallback()
    {
        using (var alias = new World(configuration: LiveTestConfig.NoRandom.Replace("\"PREPROD\", \"Tag\"", "\"765_PROD_A_NOMMER\", \"Tag\"")))
            Check.Equal("P111301PR765001", Harness.Str(alias.Preview(), "name"), "V1 alias resolves staging code");
        var json = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        json["TAGS"] = new JsonArray();
        using (var absent = new World(configuration: json.ToJsonString()))
            Check.Pesto(() => absent.Preview(), "config.invalid", "Never infer a code from Staging");
        json["TAGS"] = JsonNode.Parse("[{\"Site\":\"PREPROD\",\"Tag\":\"PR\"}]");
        json["V2DirectorySites"] = new JsonArray(new JsonObject { ["Id"] = "transit", ["Name"] = "Transit", ["Code"] = "ST", ["OU"] = Preprod });
        using var explicitSite = new World(configuration: json.ToJsonString());
        Check.Equal("P111301ST765001", Harness.Str(explicitSite.Preview(), "name"), "Explicit staging site supplies its configured code");
    }

    [Test]
    public void MissingPreproductionOuNeverFallsBackToProductionSites()
    {
        using var w = new World();
        w.Directory.FindOu = _ => null;
        Check.Pesto(() => Harness.Call(w.Backend, "directory.sites", new { purpose = "join" }), "destination.missing", "No production fallback when staging is absent");
    }
}
