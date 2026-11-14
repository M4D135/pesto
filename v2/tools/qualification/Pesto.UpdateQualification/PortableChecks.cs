using System.Diagnostics;
using System.IO.Compression;
using System.Text.Json.Nodes;
using Pesto.Engine;

namespace Pesto.UpdateQualification;

/// <summary>Small fixtures validate the qualification harness, never pretending to execute Windows or real WebView2.</summary>
internal static class PortableChecks
{
    internal static async Task<object> RunAsync()
    {
        var sources = Path.Combine(Path.GetTempPath(), "pesto-native-fixture-sources-" + Guid.NewGuid().ToString("N"));
        var roots = new List<string>();
        string NewRoot() { var path = Path.Combine(Path.GetTempPath(), Suite.Prefix + Guid.NewGuid().ToString("N")); roots.Add(path); return path; }
        var count = 0;
        try
        {
            Directory.CreateDirectory(sources);
            var sharedJson = Path.Combine(sources, "shared-reader.json");
            File.WriteAllText(sharedJson, "{\"value\":\"prêt 🌿\"}");
            Suite.Require(Suite.Text(Suite.ReadSharedObject(sharedJson), "value") == "prêt 🌿", "Shared JSON preserves UTF-8 text."); count++;
            const string prefix = "{\"value\":\"", suffix = "\"}";
            var boundary = new string('x', 256 * 1024 - prefix.Length - suffix.Length);
            File.WriteAllText(sharedJson, prefix + boundary + suffix);
            Suite.Require(Suite.Text(Suite.ReadSharedObject(sharedJson), "value") == boundary, "Shared JSON admits exactly its existing size limit."); count++;
            File.AppendAllText(sharedJson, " ");
            Reject(() => Suite.ReadSharedObject(sharedJson)); count++;
            Suite.Require(!Suite.IsEvergreenBrowser(Path.Combine(sources, "Microsoft", "EdgeWebView", "Application", "1.0", "msedgewebview2.exe")),
                "A browser image outside the machine-wide Evergreen installation is not admitted."); count++;
            var evergreenRoot = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            if (evergreenRoot.Length > 0)
            {
                var application = Path.Combine(evergreenRoot, "Microsoft", "EdgeWebView", "Application", "156.0.4314.58");
                Suite.Require(Suite.IsEvergreenBrowser(Path.Combine(application, "msedgewebview2.exe"))
                    && !Suite.IsEvergreenBrowser(Path.Combine(application, "cmd.exe"))
                    && !Suite.IsEvergreenBrowser(Path.Combine(evergreenRoot, "Microsoft", "EdgeWebView", "ApplicationX", "msedgewebview2.exe")),
                    "Only the exact Evergreen browser image is admitted outside the case."); count++;
            }
            foreach (var channel in new[] { "PROD", "DEV" })
            {
                var source = Path.Combine(sources, channel, "base"); var candidate = Path.Combine(sources, channel, "candidate");
                var sameBinary = Path.Combine(sources, channel, "same-executable");
                Fixture(source, channel, 1, 'a'); Fixture(candidate, channel, 2, 'b'); Fixture(sameBinary, channel, 1, 'c');
                var archive = Path.Combine(sources, channel, "candidate.zip");
                ZipFile.CreateFromDirectory(candidate, archive, CompressionLevel.NoCompression, includeBaseDirectory: true);
                var official = Path.Combine(sources, channel, "official");
                Fixture(official, channel, 2, 'd');
                var officialManifestPath = Path.Combine(official, UpdatePackage.ManifestPath);
                var officialManifest = JsonNode.Parse(File.ReadAllText(officialManifestPath))!.AsObject();
                officialManifest["distribution"] = "official"; officialManifest["official"] = true;
                Suite.Save(officialManifestPath, officialManifest); UpdatePackage.Rehash(official);
                var officialArchive = Path.Combine(sources, channel, "official.zip");
                ZipFile.CreateFromDirectory(official, officialArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
                var officialRoot = NewRoot(); var officialState = Suite.Create(source, official, officialArchive, officialRoot);
                var officialRequest = await Suite.PrepareAsync(officialRoot, "normal");
                var officialStage = Path.Combine(officialRequest.TransactionDirectory, "stage");
                Suite.Require(UpdatePackage.Validate(officialStage).Distribution == "official"
                    && UpdatePackage.Hash(Path.Combine(officialStage, UpdatePackage.ManifestPath)) == UpdatePackage.Hash(officialManifestPath)
                    && officialState.Candidate.SourceCommit == new string('d', 40),
                    "Official qualification must preserve the exact source and original manifest bytes through ZIP acquisition."); count++;
                officialManifest["official"] = false;
                Suite.Save(officialManifestPath, officialManifest); UpdatePackage.Rehash(official);
                Reject(() => Suite.Create(source, official, officialArchive, NewRoot())); count++;
                officialManifest["official"] = true; officialManifest["qualification"] = "production";
                Suite.Save(officialManifestPath, officialManifest); UpdatePackage.Rehash(official);
                Reject(() => Suite.Create(source, official, officialArchive, NewRoot())); count++;
                officialManifest["qualification"] = "unqualified"; officialManifest["sourceCommit"] = "";
                Suite.Save(officialManifestPath, officialManifest); UpdatePackage.Rehash(official);
                Reject(() => Suite.Create(source, official, officialArchive, NewRoot())); count++;
                var initial = UpdatePackage.Validate(source).Fingerprint; var next = UpdatePackage.Validate(candidate).Fingerprint;
                if (channel == "DEV")
                {
                    Reject(() => Suite.Create(Path.Combine(sources, "PROD", "base"), candidate, archive, NewRoot())); count++;
                }
                Reject(() => Suite.Create(source, candidate, archive, Path.GetTempPath())); count++;
                var missingRoot = NewRoot();
                Reject(() => Suite.Create(source, candidate, archive + ".missing.zip", missingRoot));
                Suite.Require(!Directory.Exists(missingRoot), "Missing ZIP must fail before creating a fixture or allowing fallback."); count++;
                Reject(() => Suite.Create(source, sameBinary, archive, NewRoot())); count++;
                var root = NewRoot(); var state = Suite.Create(source, candidate, archive, root);
                Suite.Require(state.Base.Fingerprint == initial && state.Candidate.Fingerprint == next
                    && state.Base.ExecutableSha256 != state.Candidate.ExecutableSha256 && state.Base.Version == state.Candidate.Version,
                    "Distinct builds with the same real version must retain both exact identities."); count++;
                Reject(() => Suite.Create(source, candidate, archive, root)); count++;
                Reject(() => Suite.CaseDirectory(root, "../outside")); count++;
                if (channel == "DEV")
                {
                    await RejectAsync(() => Suite.PrepareAsync(root, "health-failure"));
                    Suite.Require(!Directory.Exists(Suite.CaseDirectory(root, "health-failure")), "DEV must not silently prepare additional fault cases."); count++;
                }
                Suite.Require(Suite.Scenarios(state).SequenceEqual(channel == "PROD" ? ["normal", "health-failure", "interruption"] : ["normal"])
                    && !Suite.RequiresNewDevInstallation(state), "Packs without new exact DEV sources keep the in-place scenarios."); count++;
                if (channel == "DEV")
                {
                    // A candidate carrying an exact DEV source unknown to its base is a new installation, never an update.
                    var formatCandidate = Path.Combine(sources, channel, "format-candidate"); Fixture(formatCandidate, channel, 3, 'e');
                    var favicon = Path.Combine(formatCandidate, "wad", "dev", "web", "assets", "pesto-favicon.png");
                    Directory.CreateDirectory(Path.GetDirectoryName(favicon)!); File.WriteAllBytes(favicon, [0x89, 0x50, 0x4e, 0x47]);
                    UpdatePackage.Rehash(formatCandidate);
                    var formatArchive = Path.Combine(sources, channel, "format-candidate.zip");
                    ZipFile.CreateFromDirectory(formatCandidate, formatArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
                    var formatRoot = NewRoot(); var formatState = Suite.Create(source, formatCandidate, formatArchive, formatRoot);
                    Suite.Require(Suite.RequiresNewDevInstallation(formatState) && Suite.Scenarios(formatState).SequenceEqual(["format-refusal"]),
                        "A base without the exact DEV sources must be qualified as an explicit refusal."); count++;
                    await RejectAsync(() => Suite.PrepareAsync(formatRoot, "normal")); count++;
                    var formatRequest = await Suite.PrepareAsync(formatRoot, "format-refusal");
                    Suite.Require(Suite.Case(formatRoot, "format-refusal").Acquisition == "zip"
                        && UpdatePackage.Validate(Path.Combine(formatRequest.TransactionDirectory, "stage")).Fingerprint == formatState.Candidate.Fingerprint,
                        "The refusal fixture must stage the exact real candidate from its ZIP."); count++;
                    Reject(() => Suite.Verify(formatRoot, "format-refusal", "install")); // No native observation: never a refusal proof.
                    Reject(() => Suite.Cleanup(formatRoot, "format-refusal")); count++;
                    // Both packs carry exact DEV sources: only the base clause can keep the in-place scenario.
                    var formatNext = Path.Combine(sources, channel, "format-next"); Fixture(formatNext, channel, 4, 'f');
                    var nextFavicon = Path.Combine(formatNext, "wad", "dev", "web", "assets", "pesto-favicon.png");
                    Directory.CreateDirectory(Path.GetDirectoryName(nextFavicon)!); File.WriteAllBytes(nextFavicon, [0x89, 0x50, 0x4e, 0x47, 0x0d]);
                    UpdatePackage.Rehash(formatNext);
                    var nextArchive = Path.Combine(sources, channel, "format-next.zip");
                    ZipFile.CreateFromDirectory(formatNext, nextArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
                    var reverse = NewRoot(); var reverseState = Suite.Create(formatCandidate, formatNext, nextArchive, reverse);
                    Suite.Require(!Suite.RequiresNewDevInstallation(reverseState) && Suite.Scenarios(reverseState).SequenceEqual(["normal"]),
                        "A base that already knows the exact DEV sources keeps in-place updates."); count++;
                }
                foreach (var scenario in Suite.Scenarios(state))
                {
                    var request = await Suite.PrepareAsync(root, scenario);
                    var journal = Suite.ReadSharedObject(Path.Combine(request.TransactionDirectory, "transaction.json"));
                    using var current = Process.GetCurrentProcess();
                    Suite.Require(journal["parentProcessId"]!.GetValue<int>() == current.Id
                        && journal["parentStartUtc"]!.GetValue<DateTimeOffset>().UtcDateTime == current.StartTime.ToUniversalTime(),
                        "Public preparation did not bind the requesting process identity.");
                    UpdateTransaction.ValidateHelperInvocation(request.TransactionDirectory, request.HelperExecutable);
                    var stage = Path.Combine(request.TransactionDirectory, "stage");
                    Suite.Require(UpdatePackage.Hash(request.HelperExecutable) == state.Base.ExecutableSha256
                        && Suite.Text(journal, "currentExecutableHash") == state.Base.ExecutableSha256
                        && Suite.Text(journal, "nextExecutableHash") == state.Candidate.ExecutableSha256
                        && UpdatePackage.Hash(Path.Combine(stage, "Pesto.exe")) == state.Candidate.ExecutableSha256
                        && Suite.RuntimeFingerprint(stage) == state.Candidate.RuntimeFingerprint, "Helper/base and candidate identities were mixed.");
                    Suite.Require(File.ReadAllText(Path.Combine(stage, "wad", "web", "index.html")).Contains("synthetic", StringComparison.OrdinalIgnoreCase) == (scenario != "normal"),
                        "Invalid page fixture selection.");
                    var prepared = Suite.Case(root, scenario);
                    Suite.Require(prepared.CandidateVersion == state.Candidate.Version && prepared.Acquisition == (scenario == "normal" ? "zip" : "directory"),
                        "Real version and acquisition type must remain explicit.");
                    if (scenario == "normal") Suite.Require(UpdatePackage.Validate(stage).Fingerprint == state.Candidate.Fingerprint
                        && UpdatePackage.Hash(Path.Combine(stage, UpdatePackage.ManifestPath)) == UpdatePackage.Hash(Path.Combine(candidate, UpdatePackage.ManifestPath)),
                        "Normal ZIP acquisition must preserve the original candidate manifest/source commit byte for byte.");
                    Reject(() => Suite.Cleanup(root, scenario)); // Missing native proof must prevent successful-case cleanup.
                    count++;
                }
                Suite.CheckUnchanged(root, state); count++;
                var sentinel = Path.Combine(root, "profile-sentinel", "cfg.json");
                var original = File.ReadAllText(sentinel); File.AppendAllText(sentinel, "changed");
                Reject(() => Suite.CheckUnchanged(root, state)); File.WriteAllText(sentinel, original); count++;
                var archiveBytes = File.ReadAllBytes(archive); File.AppendAllText(archive, "changed");
                Reject(() => Suite.CheckUnchanged(root, state)); File.WriteAllBytes(archive, archiveBytes); count++;

                // UI qualification starts with only a fresh installed copy. The companion must neither
                // pre-create the transaction nor accept a redirected request or missing native proof.
                var uiRoot = NewRoot(); var ui = UiSuite.Create(source, candidate, archive, uiRoot);
                var uiState = Suite.Load(uiRoot); var uiRequestPath = Path.Combine(uiRoot, "ui-request.json");
                Suite.Require(UpdatePackage.Validate(ui.Installation).Fingerprint == initial
                    && UpdateTransaction.List(ui.Installation).Count == 0 && !Directory.Exists(ui.ReportDirectory),
                    "UI initialization must not prepare a transaction or fabricate the app's evidence."); count++;
                Suite.Save(uiRequestPath, ui with { TargetFingerprint = new string('0', 64) });
                Reject(() => UiSuite.Request(uiRoot, uiState)); Suite.Save(uiRequestPath, ui); count++;
                Suite.Save(uiRequestPath, ui with { Installation = source });
                Reject(() => UiSuite.Request(uiRoot, uiState)); Suite.Save(uiRequestPath, ui); count++;
                var unknown = Suite.ReadSharedObject(uiRequestPath); unknown["skipConfirmation"] = true;
                Suite.Save(uiRequestPath, unknown);
                try { _ = UiSuite.Request(uiRoot, uiState); throw new InvalidOperationException("Unknown UI request properties were accepted."); }
                catch (System.Text.Json.JsonException) { }
                Suite.Save(uiRequestPath, ui); count++;
                Reject(() => UiSuite.Adopt(uiRoot)); count++;
                Reject(() => UiSuite.Cleanup(uiRoot));
                Suite.Require(Directory.Exists(ui.Installation), "Missing UI proof must never authorize fixture cleanup."); count++;

                var wrongArchive = Path.Combine(sources, channel, "wrong-content.zip");
                ZipFile.CreateFromDirectory(source, wrongArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
                var wrongRoot = NewRoot(); _ = Suite.Create(source, candidate, wrongArchive, wrongRoot);
                await RejectAsync(() => Suite.PrepareAsync(wrongRoot, "normal"));
                Suite.Require(UpdateTransaction.List(Path.Combine(Suite.CaseDirectory(wrongRoot, "normal"), "installation")).Count == 0
                    && !File.Exists(Path.Combine(wrongRoot, "evidence", "proof.json")), "A different ZIP cannot create a transaction or a qualification proof."); count++;

                var candidateIndex = Path.Combine(candidate, "wad", "web", "index.html"); var candidateHtml = File.ReadAllText(candidateIndex);
                File.AppendAllText(candidateIndex, "candidate changed"); UpdatePackage.Rehash(candidate);
                Reject(() => Suite.CheckUnchanged(root, state)); File.WriteAllText(candidateIndex, candidateHtml); UpdatePackage.Rehash(candidate); count++;
                File.AppendAllText(Path.Combine(source, "wad", "web", "index.html"), "base changed"); UpdatePackage.Rehash(source);
                Reject(() => Suite.CheckUnchanged(root, state)); count++;
            }
            return new { success = true, checks = count, channels = new[] { "PROD", "DEV" }, distinctFixtureBinaries = true,
                zipAcquisitionExercised = true, uiRequestGuardsExercised = true,
                nativeWindowsExecuted = false, adExecuted = false, fixtureRuntimeOnly = true };
        }
        finally
        {
            foreach (var root in roots) if (Directory.Exists(root)) Directory.Delete(root, true);
            if (Directory.Exists(sources)) Directory.Delete(sources, true);
        }
    }

    private static void Reject(Action operation)
    {
        try { operation(); }
        catch (Exception error) when (error is InvalidOperationException or IOException or Pesto.Core.PestoException) { return; }
        throw new InvalidOperationException("Expected qualification refusal was not produced.");
    }

    private static async Task RejectAsync(Func<Task> operation)
    {
        try { await operation(); }
        catch (Exception error) when (error is InvalidOperationException or IOException or Pesto.Core.PestoException) { return; }
        throw new InvalidOperationException("Expected asynchronous qualification refusal was not produced.");
    }

    private static void Fixture(string root, string channel, byte marker, char commit)
    {
        Directory.CreateDirectory(Path.Combine(root, "wad", "web"));
        Directory.CreateDirectory(Path.Combine(root, "wad", "docs"));
        var pe = new byte[256]; pe[0] = (byte)'M'; pe[1] = (byte)'Z';
        BitConverter.GetBytes(0x80).CopyTo(pe, 0x3c); BitConverter.GetBytes(0x00004550).CopyTo(pe, 0x80);
        BitConverter.GetBytes((ushort)0x8664).CopyTo(pe, 0x84); BitConverter.GetBytes((ushort)0x20b).CopyTo(pe, 0x98);
        pe[200] = marker; File.WriteAllBytes(Path.Combine(root, "Pesto.exe"), pe);
        var bundle = FindAdBundle();
        foreach (var (name, expected) in ActiveDirectoryBundle.Sha256)
        {
            var source = Path.Combine(bundle, name);
            Suite.Require(UpdatePackage.Hash(source) == expected, "Pinned AD fixture file differs from Microsoft source.");
            var destination = Path.Combine(root, ActiveDirectoryBundle.RelativeDirectory, name);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!); File.Copy(source, destination);
        }
        File.WriteAllText(Path.Combine(root, "wad", "web", "index.html"), "<html>portable fixture, no native execution</html>");
        Suite.Save(Path.Combine(root, UpdatePackage.ManifestPath), new JsonObject
        {
            ["schemaVersion"] = 2, ["packName"] = "Pesto-v2-portable", ["version"] = "2.0.0", ["channel"] = channel,
            ["entryPoint"] = "Pesto.exe", ["layout"] = "singlefile-wad", ["repository"] = "M4D135/pesto",
            ["webview2Runtime"] = "evergreen", ["distribution"] = "candidate", ["official"] = false, ["qualification"] = "unqualified",
            ["sourceCommit"] = new string(commit, 40)
        });
        UpdatePackage.Rehash(root);
    }

    private static string FindAdBundle()
    {
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        for (var current = start; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
        foreach (var candidate in new[] { Path.Combine(current, "DEV", "wad"), Path.Combine(current, ActiveDirectoryBundle.RelativeDirectory) })
            if (ActiveDirectoryBundle.Sha256.Keys.All(name => File.Exists(Path.Combine(candidate, name)))) return candidate;
        throw new InvalidOperationException("Run portable qualification checks from the repository or a DEV pack with its pinned AD bundle. No module is imported or executed.");
    }
}
