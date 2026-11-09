using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal static class AuditWildcardCompatibilityTests
{
    [Test] private static void WildcardSetsRangesAndEscapesStayLiteralOutsideTheirSyntax()
    {
        foreach (var (pattern, value, expected) in new[] {
            ("[A-C]gence??", "bgencePA", true), ("[A-C]gence??", "ZgencePA", false),
            ("[-A]", "-", true), ("[A-]", "-", true), ("]", "]", true), ("[]A]", "]", true),
            ("[`-A]", "-", true), ("[^A]", "Z", false), ("[^A]", "^", true),
            ("`[Paris`]", "[Paris]", true), ("Paris`*", "Paris*", true), ("Paris`?", "ParisX", false),
            ("(Paris|Lyon)", "Paris", false), ("a.b", "axb", false), ("a+b", "a+b", true) })
            Check.Equal(expected, V1Config.MatchesWildcard(pattern, value), pattern + " / " + value);
        foreach (var pattern in new[] { "[", "[]", "[ABC", "[Z-A]" })
            Check.Pesto(() => V1Config.MatchesWildcard(pattern, "Paris"), "config.invalid", "motif invalide refusé : " + pattern);
    }

    [Test] private static void V1CharacterClassPatternShouldKeepMatchingOrdinarySites()
    {
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["TAGS"] = JsonNode.Parse("""[{"Site":"PREPROD","Tag":"PR"},{"Site":"[PL]aris*","Tag":"PA"}]""");
        var root = LiveTestConfig.Write(ConfigurationDocument.Sanitize(cfg.ToJsonString()).ToJsonString());
        try
        {
            Check.True(V1Config.MatchesWildcard("Paris*", "Paris-Nord"), "Témoin : étoile simple prise en charge");
            var gateway = new FakeGateway();
            gateway.ChildOus["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris-Nord"];
            var count = Harness.Arr(Harness.Call(Harness.Live(root, gateway), "directory.sites"), "items").Count;
            Console.WriteLine($"Audit wildcard : pattern=[PL]aris*, OU=Paris-Nord, sites visibles={count}");
            Check.Equal(1, count, "Le motif accepté à l’import doit conserver la sémantique -like de V1 ou être refusé explicitement");
        }
        finally { Directory.Delete(root, true); }
    }
}
