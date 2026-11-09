using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal static class UpdateTests
{
    [Test] private static void DevAdditionalSourcesUseExactPathsAndRemainHashed()
    {
        using var f = new Fixture();
        var manifestPath = Path.Combine(f.Install, UpdatePackage.ManifestPath);
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        manifest["channel"] = "DEV"; File.WriteAllText(manifestPath, manifest.ToJsonString());
        var names = new[] { "src/Pesto.App/Assets/Pesto.ico", "src/Pesto.App/Assets/pesto-master.png",
            "web/assets/pesto.png", "web/assets/pesto-favicon.png", "tools/check-ui-kit.py", "tools/m4d-components/components.py" };
        foreach (var name in names)
        {
            var path = Path.Combine(f.Install, "wad/dev", name); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "explicit DEV source payload fixture");
        }
        UpdatePackage.Rehash(f.Install);
        Check.Equal("DEV", UpdatePackage.Validate(f.Install).Channel, "les chemins exacts permettent la refabrication et les contrôles DEV");
        var icon = Path.Combine(f.Install, "wad/dev", names[0]);
        File.AppendAllText(icon, "changed");
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.hashes", "les images restent protégées par le manifeste");
        UpdatePackage.Rehash(f.Install);
        foreach (var name in new[] { "src/Pesto.App/Assets/extra.png", "src/Pesto.App/Assets/extra.ico",
            "web/assets/extra.png", "web/other/pesto-favicon.png", "tools/extra.py", "tools/m4d-components/extra.py" })
        {
            var path = Path.Combine(f.Install, "wad/dev", name); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "unexpected image fixture"); UpdatePackage.Rehash(f.Install);
            Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.file", "aucune extension image ou Python admise globalement dans DEV");
            File.Delete(path); UpdatePackage.Rehash(f.Install);
        }
        manifest["channel"] = "PROD"; File.WriteAllText(manifestPath, manifest.ToJsonString()); UpdatePackage.Rehash(f.Install);
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.file", "les sources de marque DEV restent interdites en PROD");
    }

    [Test] private static void ClosedPackageRequiresThePinnedActiveDirectoryBundleEvenAfterRehash()
    {
        using var f = new Fixture();
        var bundle = Path.Combine(f.Install, ActiveDirectoryBundle.RelativeDirectory);
        Check.Equal(6, ActiveDirectoryBundle.Sha256.Count, "contrat fermé de six fichiers Microsoft");
        foreach (var name in ActiveDirectoryBundle.Sha256.Keys)
        {
            var path = Path.Combine(bundle, name); var original = File.ReadAllBytes(path);
            File.AppendAllText(path, "tampered"); UpdatePackage.Rehash(f.Install);
            Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.ad_module", "recalculer les sommes ne rend pas un module modifié fiable");
            File.Delete(path); UpdatePackage.Rehash(f.Install);
            Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.incomplete", "chaque fichier AD est obligatoire");
            File.WriteAllBytes(path, original); UpdatePackage.Rehash(f.Install);
        }
        foreach (var name in new[] { "extra.dll", "extra.psm1", "cfg.json", "fr-FR/extra.dll.mui" })
        {
            var path = Path.Combine(bundle, name);
            File.WriteAllText(path, "unexpected"); UpdatePackage.Rehash(f.Install);
            Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.file", "aucune ouverture de l’allowlist au dossier entier");
            File.Delete(path); UpdatePackage.Rehash(f.Install);
        }
        Check.Equal("2.0.0", UpdatePackage.Validate(f.Install).Version, "pack intact de nouveau valide");
    }

    [Test] private static void ClosedPackageRejectsChangedMissingExtraAndCaseAmbiguousFiles()
    {
        using var f = new Fixture();
        Check.Equal("2.0.0", UpdatePackage.Validate(f.Install).Version, "fixture complète");
        File.AppendAllText(Path.Combine(f.Install, "wad/web/index.html"), "changed");
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.hashes", "modification refusée");
        UpdatePackage.Rehash(f.Install);
        File.WriteAllText(Path.Combine(f.Install, "private.json"), "{}");
        UpdatePackage.Rehash(f.Install);
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.file", "fichier privé refusé même avec somme");
        File.Delete(Path.Combine(f.Install, "private.json"));
        var duplicate = Path.Combine(f.Root, "duplicate.zip");
        using (var zip = ZipFile.Open(duplicate, ZipArchiveMode.Create))
        {
            zip.CreateEntry("Pesto.exe"); zip.CreateEntry("pesto.EXE");
        }
        Check.Pesto(() => { UpdatePackage.ExtractZip(duplicate, Path.Combine(f.Root, "duplicate")); return null; },
            "package.path", "casse Windows ambiguë refusée avant extraction");
    }

    [Test] private static void ZipTraversalLinksAndDuplicatePathsNeverEscapeExtraction()
    {
        using var f = new Fixture();
        foreach (var bad in new[] { "../outside", "C:/escape", "/absolute", "wad/CON.txt", "wad/trailing.", "wad\\escape" })
        {
            var archive = Path.Combine(f.Root, Guid.NewGuid().ToString("N") + ".zip");
            using (var zip = ZipFile.Open(archive, ZipArchiveMode.Create))
            using (var writer = new StreamWriter(zip.CreateEntry(bad).Open())) writer.Write("bad");
            Check.Pesto(() => { UpdatePackage.ExtractZip(archive, Path.Combine(f.Root, Guid.NewGuid().ToString("N"))); return null; }, "package.path", bad);
        }
        var symlink = Path.Combine(f.Root, "link.zip");
        using (var zip = ZipFile.Open(symlink, ZipArchiveMode.Create))
        {
            var entry = zip.CreateEntry("wad/link"); entry.ExternalAttributes = 0xA1FF << 16;
            using var writer = new StreamWriter(entry.Open()); writer.Write("../../outside");
        }
        Check.Pesto(() => { UpdatePackage.ExtractZip(symlink, Path.Combine(f.Root, "unzip-link")); return null; }, "package.link", "symlink Unix refusé");
        Check.False(File.Exists(Path.Combine(f.Root, "outside")), "aucune sortie de l’extraction");
    }

    [Test] private static async Task DemoDirectApisRejectBeforeFileSystem()
    {
        using var f = new Fixture();
        var absent = Path.Combine(f.Root, "must-not-exist");
        using var service = new UpdateService(new("/nonexistent", absent, "PROD", true));
        Check.Pesto(() => service.Status(), "demo.isolated", "statut démo isolé");
        Check.Pesto(() => service.InspectLocal(@"\\server\share\pack.zip"), "demo.isolated", "UNC démo isolé");
        Check.Pesto(() => service.RequestInstall("anything", true), "demo.isolated", "installation directe démo refusée");
        Check.Pesto(() => service.RequestRollback(true), "demo.isolated", "rollback démo refusé");
        Check.Pesto(() => service.RequestRecovery(true), "demo.isolated", "reprise démo refusée");
        await ThrowsAsync(() => service.PrepareAsync("anything"), "demo.isolated");
        Check.False(Directory.Exists(absent), "aucun dossier réel");
    }

    [Test] private static async Task PreparationDoesNotInstallAndDetectsChangedSelection()
    {
        using var f = new Fixture(); using var service = f.Service();
        var initial = UpdatePackage.Validate(f.Install).Fingerprint;
        var candidate = service.InspectLocal(f.Next)["candidateId"]!.GetValue<string>();
        var ready = await service.PrepareAsync(candidate);
        Check.Equal(initial, UpdatePackage.Validate(f.Install).Fingerprint, "préparation sans remplacement");
        Check.Pesto(() => service.RequestInstall(ready["preparedId"]!.GetValue<string>(), false), "update.confirmation", "confirmation obligatoire");
        var request = service.RequestInstall(ready["preparedId"]!.GetValue<string>(), true);
        Check.True(File.Exists(request.HelperExecutable), "copie helper du même Pesto.exe");
        Check.Equal(initial, UpdatePackage.Validate(f.Install).Fingerprint, "handoff sans remplacement");
        UpdateTransaction.ValidateHelperInvocation(request.TransactionDirectory, request.HelperExecutable);
        Check.Pesto(() => { UpdateTransaction.ValidateHelperInvocation(request.TransactionDirectory, Path.Combine(f.Install, "Pesto.exe")); return null; }, "update.helper", "helper origine refusée");
        File.AppendAllText(Path.Combine(f.Next, "wad/web/index.html"), "new change"); UpdatePackage.Rehash(f.Next);
        await ThrowsAsync(() => service.PrepareAsync(candidate), "update.changed");
    }

    [Test] private static void ReviewedCopyRejectsACoherentReplacementAtTheCopyBoundary()
    {
        using var f = new Fixture();
        var inspected = UpdatePackage.Validate(f.Next);
        var originalInstallation = UpdatePackage.Validate(f.Install).Fingerprint;
        // Deterministically model a share changed after its source check and before the copy starts.
        // The replacement is internally valid and keeps the same version; hashes alone are insufficient.
        File.AppendAllText(Path.Combine(f.Next, "wad/web/index.html"), "<p>Concurrent publisher</p>");
        UpdatePackage.Rehash(f.Next);
        var concurrent = UpdatePackage.Validate(f.Next);
        Check.Equal(inspected.Version, concurrent.Version, "la version seule ne distingue pas la modification concurrente");
        Check.False(inspected.Fingerprint == concurrent.Fingerprint, "le pack concurrent est différent mais entièrement valide");
        var destination = Path.Combine(f.Root, "reviewed-copy");
        Check.Pesto(() => { UpdatePackage.CopyToNew(f.Next, destination, inspected.Fingerprint); return null; },
            "update.changed", "la copie doit rester liée à l’empreinte inspectée");
        Check.False(Directory.Exists(destination), "seule la copie non autorisée est nettoyée");
        Check.Equal(concurrent.Fingerprint, UpdatePackage.Validate(f.Next).Fingerprint, "la source concurrente est conservée");
        Check.Equal(originalInstallation, UpdatePackage.Validate(f.Install).Fingerprint, "l’installation reste intacte");
        UpdatePackage.CopyToNew(f.Next, destination, concurrent.Fingerprint);
        Check.Equal(concurrent.Fingerprint, UpdatePackage.Validate(destination).Fingerprint, "une nouvelle inspection exacte permet la copie");
    }

    [Test] private static async Task LocalZipPreparationRetainsTheExactReviewedPackAndNeverInstalls()
    {
        using var f = new Fixture(); using var service = f.Service();
        var archive = Path.Combine(f.Root, "candidate.zip");
        ZipFile.CreateFromDirectory(f.Next, archive, CompressionLevel.NoCompression, includeBaseDirectory: true);
        var archiveHash = UpdatePackage.Hash(archive); var next = UpdatePackage.Validate(f.Next);
        var current = UpdatePackage.Validate(f.Install).Fingerprint;
        var inspected = service.InspectLocal(archive);
        Check.Equal(next.Fingerprint, inspected["fingerprint"]!.GetValue<string>(), "le ZIP à dossier unique est réellement inspecté");
        var prepared = await service.PrepareAsync(inspected["candidateId"]!.GetValue<string>());
        Check.Equal(next.Fingerprint, prepared["fingerprint"]!.GetValue<string>(), "la préparation conserve exactement le contenu inspecté du ZIP");
        Check.Equal(current, UpdatePackage.Validate(f.Install).Fingerprint, "la préparation ZIP ne remplace aucun binaire");
        Check.Equal(archiveHash, UpdatePackage.Hash(archive), "l’archive choisie reste inchangée");
        Check.Equal(next.Fingerprint, UpdatePackage.Validate(f.Next).Fingerprint, "le dossier source reste inchangé");
        Check.Equal(0, UpdateTransaction.List(f.Install).Count, "aucune transaction n’est autorisée avant confirmation");
    }

    [Test] private static async Task RejectedZipInspectionDiscardsOnlyItsOwnExtraction()
    {
        foreach (var refusal in new[] { "package.channel", "package.hashes", "update.same", "package.layout" })
        {
            using var f = new Fixture(); using var service = f.Service();
            var acceptedArchive = Path.Combine(f.Root, "accepted.zip");
            ZipFile.CreateFromDirectory(f.Next, acceptedArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
            var accepted = service.InspectLocal(acceptedArchive);
            var inspectionRoot = Path.Combine(Directory.GetDirectories(Path.Combine(f.Root, "state", "workspaces")).Single(), "inspections");
            var previousInspection = Directory.GetDirectories(inspectionRoot).Single();
            var previousFingerprint = accepted["fingerprint"]!.GetValue<string>();
            var installationFingerprint = UpdatePackage.Validate(f.Install).Fingerprint;
            if (refusal == "package.channel")
            {
                var manifestPath = Path.Combine(f.Next, UpdatePackage.ManifestPath);
                var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!;
                manifest["channel"] = "DEV";
                File.WriteAllText(manifestPath, manifest.ToJsonString());
                UpdatePackage.Rehash(f.Next);
            }
            else if (refusal == "package.hashes") File.AppendAllText(Path.Combine(f.Next, "wad/web/index.html"), "corrupted");
            var rejectedArchive = Path.Combine(f.Root, "rejected.zip");
            ZipFile.CreateFromDirectory(refusal == "update.same" ? f.Install : f.Next, rejectedArchive, CompressionLevel.NoCompression, includeBaseDirectory: true);
            if (refusal == "package.layout")
            {
                using var zip = ZipFile.Open(rejectedArchive, ZipArchiveMode.Update);
                using var writer = new StreamWriter(zip.CreateEntry("extra.txt").Open()); writer.Write("ambiguous layout");
            }
            var archiveHash = UpdatePackage.Hash(rejectedArchive);
            var sourcePage = File.ReadAllText(Path.Combine(f.Next, "wad/web/index.html"));
            Check.Pesto(() => service.InspectLocal(rejectedArchive), refusal, "ZIP refusé après extraction");
            Check.Equal(1, Directory.GetDirectories(inspectionRoot).Length, "L’extraction refusée est supprimée, pas la précédente");
            Check.True(Directory.Exists(previousInspection), "Le candidat déjà inspecté reste disponible");
            Check.Equal(archiveHash, UpdatePackage.Hash(rejectedArchive), "L’archive sélectionnée reste intacte");
            Check.Equal(sourcePage, File.ReadAllText(Path.Combine(f.Next, "wad/web/index.html")), "Le dossier source reste intact");
            Check.Equal(installationFingerprint, UpdatePackage.Validate(f.Install).Fingerprint, "L’installation n’est pas modifiée");
            Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "La configuration de profil est conservée");
            var prepared = await service.PrepareAsync(accepted["candidateId"]!.GetValue<string>());
            Check.Equal(previousFingerprint, prepared["fingerprint"]!.GetValue<string>(), "Le candidat antérieur peut toujours être préparé");
        }
    }

    [Test] private static void RejectedFolderInspectionNeverRemovesTheSelectedSource()
    {
        using var f = new Fixture(); using var service = f.Service();
        var installationFingerprint = UpdatePackage.Validate(f.Install).Fingerprint;
        File.AppendAllText(Path.Combine(f.Next, "wad/web/index.html"), "corrupted");
        var sourceHash = UpdatePackage.Hash(Path.Combine(f.Next, "wad/web/index.html"));
        Check.Pesto(() => service.InspectLocal(f.Next), "package.hashes", "Le dossier corrompu est refusé sans nettoyage de la source");
        Check.Equal(sourceHash, UpdatePackage.Hash(Path.Combine(f.Next, "wad/web/index.html")), "Le dossier sélectionné n’appartient jamais au nettoyage");
        Check.Equal(installationFingerprint, UpdatePackage.Validate(f.Install).Fingerprint, "L’installation reste intacte");
        Check.False(Directory.Exists(Path.Combine(f.Root, "state", "inspections")), "Aucune extraction temporaire pour un dossier");
    }

    [Test] private static async Task SuccessfulInstallAndExplicitRollbackPreserveUserConfiguration()
    {
        using var f = new Fixture(); var original = UpdatePackage.Validate(f.Install).Fingerprint;
        var request = await f.Prepare();
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy);
        Check.Equal("completed", result.Status, "installation santé confirmée");
        Check.Equal(UpdatePackage.Validate(f.Next).Fingerprint, UpdatePackage.Validate(f.Install).Fingerprint, "nouveau pack installé");
        Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "profil préservé");
        using var service = f.Service();
        Check.True(service.Status()["canRollback"]!.GetValue<bool>(), "retour proposé");
        var rollback = service.RequestRollback(true);
        result = await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, f.Healthy);
        Check.Equal("rolledBack", result.Status, "retour santé confirmé");
        Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "pack initial restauré");
        Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "profil non remplacé par rollback");
    }

    [Test] private static async Task FailedHealthRollsBackAndNeverReportsInstalled()
    {
        using var f = new Fixture(); var original = UpdatePackage.Validate(f.Install).Fingerprint;
        var request = await f.Prepare(); var checks = 0;
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, (root, path, nonce, ct) =>
        {
            checks++;
            return checks == 1 ? Task.FromResult(false) : f.Healthy(root, path, nonce, ct);
        });
        Check.Equal("rolledBack", result.Status, "échec santé rétabli"); Check.Equal(2, checks, "nouveau puis ancien contrôlés");
        Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "ancien pack intact");
    }

    [Test] private static async Task BooleanHealthWithoutMatchingProofIsNeverAccepted()
    {
        using var f = new Fixture(); var request = await f.Prepare(); var checks = 0;
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, async (root, path, nonce, ct) =>
        {
            checks++; await f.Healthy(root, path, checks == 1 ? "stale-nonce" : nonce, ct); return true;
        });
        Check.Equal("rolledBack", result.Status, "preuve périmée refusée malgré bool true");
        Check.Equal(2, checks, "retour contrôlé");
    }

    [Test] private static async Task NegativeHealthProofSurvivesSuccessfulRollbackAsSeparateDurableAttempts()
    {
        using var f = new Fixture(); var request = await f.Prepare(); var calls = 0;
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, async (root, path, nonce, ct) =>
        {
            calls++;
            var started = UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory).Single(a => a["nonce"]!.GetValue<string>() == nonce);
            Check.Equal("started", started["status"]!.GetValue<string>(), "intention durable avant callback");
            Check.True(started["accepted"] is null, "aucun succès anticipé");
            await f.Healthy(root, path, nonce, ct);
            if (calls != 1) return true;
            var proof = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            proof["webViewReady"] = false; proof["success"] = false; proof["closeReturned"] = true;
            proof["failureCode"] = "maintenance.webview"; proof["notInReceipt"] = "never-copy-this-field";
            File.WriteAllText(path, proof.ToJsonString());
            return false;
        });
        Check.Equal("rolledBack", result.Status, "retour effectué après preuve négative");
        var attempts = UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory);
        Check.Equal(2, attempts.Count, "les deux contrôles restent lisibles");
        var candidate = attempts.Single(a => a["target"]!.GetValue<string>() == "candidate");
        var rollback = attempts.Single(a => a["target"]!.GetValue<string>() == "rollback");
        Check.Equal("failed", candidate["status"]!.GetValue<string>(), "candidat refusé durablement");
        Check.False(candidate["reportedSuccess"]!.GetValue<bool>(), "code callback négatif conservé");
        Check.False(candidate["accepted"]!.GetValue<bool>(), "candidat jamais déclaré réussi");
        Check.False(candidate["proof"]!["success"]!.GetValue<bool>(), "preuve négative conservée");
        Check.Equal("maintenance.webview", candidate["proof"]!["failureCode"]!.GetValue<string>(), "diagnostic négatif conservé");
        Check.True(candidate["proof"]!["notInReceipt"] is null, "projection fermée sans champ arbitraire");
        Check.Equal("passed", rollback["status"]!.GetValue<string>(), "ancien pack confirmé séparément");
        Check.True(rollback["accepted"]!.GetValue<bool>(), "preuve de retour validée");
        Check.True(candidate["nonce"]!.GetValue<string>() != rollback["nonce"]!.GetValue<string>(), "nonces distincts");
        Check.Equal(rollback["nonce"]!.GetValue<string>(), JsonNode.Parse(File.ReadAllText(Path.Combine(request.TransactionDirectory, "health.json")))!["nonce"]!.GetValue<string>(),
            "preuve partagée remplacée sans effacer le reçu candidat");
    }

    [Test] private static async Task InterruptedHealthAttemptNeverBecomesPassedAndKeepsItsMatchingProof()
    {
        using var f = new Fixture(); var request = await f.Prepare();
        try
        {
            await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, async (root, path, nonce, ct) =>
            {
                await f.Healthy(root, path, nonce, ct);
                throw new UpdateInterruptionException();
            });
            throw new TestFailureException("interruption santé non injectée");
        }
        catch (UpdateInterruptionException) { }
        var before = UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory);
        Check.Equal(1, before.Count, "une intention subsiste après interruption");
        Check.Equal("started", before[0]["status"]!.GetValue<string>(), "callback non confirmé");
        var recovery = UpdateTransaction.RequestRollback(request.TransactionDirectory, true);
        var result = await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, f.Healthy);
        Check.Equal("rolledBack", result.Status, "reprise réelle du chemin transactionnel");
        var attempts = UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory);
        Check.Equal(2, attempts.Count, "interruption et reprise séparées");
        var interrupted = attempts.Single(a => a["target"]!.GetValue<string>() == "candidate");
        Check.Equal("interrupted", interrupted["status"]!.GetValue<string>(), "intention finalisée en interruption");
        Check.False(interrupted["accepted"]!.GetValue<bool>(), "preuve positive seule ne valide pas un callback interrompu");
        Check.True(interrupted["reportedSuccess"] is null, "résultat callback inconnu");
        Check.True(interrupted["proof"]!["success"]!.GetValue<bool>(), "preuve liée au nonce préservée avant suppression");
        Check.Equal(before[0]["nonce"]!.GetValue<string>(), interrupted["proof"]!["nonce"]!.GetValue<string>(), "preuve de la bonne tentative");
        Check.Equal("passed", attempts.Single(a => a["target"]!.GetValue<string>() == "rollback")["status"]!.GetValue<string>(), "santé du retour confirmée indépendamment");
    }

    [Test] private static async Task DurableHealthReceiptsRejectUnknownFieldsAndWrongTypes()
    {
        using var f = new Fixture(); var request = await f.Prepare();
        await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy);
        var attempt = UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory).Single();
        var file = Path.Combine(request.TransactionDirectory, "health-attempts", attempt["nonce"]!.GetValue<string>() + ".json");
        foreach (var mutate in new Action<JsonObject>[]
        {
            p => p["unknown"] = true,
            p => p["accepted"] = "true",
            p => p["proof"]!["unknown"] = true,
            p => p["proof"]!["success"] = "true"
        })
        {
            var invalid = (JsonObject)attempt.DeepClone(); mutate(invalid); File.WriteAllText(file, invalid.ToJsonString());
            Check.Pesto(() => UpdateTransaction.ReadHealthAttempts(request.TransactionDirectory), "update.healthReceipt", "reçu altéré refusé");
        }
    }

    [Test] private static async Task RecoveryHandlesEveryReplacementInterruptionBoundary()
    {
        foreach (var boundary in new[] { "backingUp", "backupMoved", "backedUp", "installing", "candidateMoved", "installed", "checking" })
        {
            using var f = new Fixture(); var original = UpdatePackage.Validate(f.Install).Fingerprint;
            var request = await f.Prepare();
            try
            {
                await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy, checkpoint: point => { if (point == boundary) throw new UpdateInterruptionException(); });
                throw new TestFailureException("crash non injecté à " + boundary);
            }
            catch (UpdateInterruptionException) { }
            var recovery = UpdateTransaction.RequestRollback(request.TransactionDirectory, true);
            var result = await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, f.Healthy);
            Check.True(result.Status is "rolledBack" or "cancelled", "reprise " + boundary);
            Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "ancien pack relu à " + boundary);
            Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "configuration inchangée à " + boundary);
        }
    }

    [Test] private static async Task RecoverySurvivesInterruptionDuringRollbackItself()
    {
        foreach (var boundary in new[] { "failedCandidateMoved", "backupRestored" })
        {
            using var f = new Fixture(); var original = UpdatePackage.Validate(f.Install).Fingerprint; var request = await f.Prepare();
            try
            {
                await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, (_, _, _, _) => Task.FromResult(false),
                    checkpoint: point => { if (point == boundary) throw new UpdateInterruptionException(); });
                throw new TestFailureException("interruption retour non injectée");
            }
            catch (UpdateInterruptionException) { }
            var recovery = UpdateTransaction.RequestRollback(request.TransactionDirectory, true);
            var result = await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, f.Healthy);
            Check.Equal("rolledBack", result.Status, "reprise retour à " + boundary);
            Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "ancien pack conservé");
        }
    }

    [Test] private static async Task ConcurrentInstallerAndExternalModificationArePreserved()
    {
        using var f = new Fixture(); var request = await f.Prepare();
        var root = Path.GetDirectoryName(request.TransactionDirectory)!;
        using (var locked = new FileStream(Path.Combine(root, "transaction.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await ThrowsAsync(() => UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy), "update.busy");
        File.AppendAllText(Path.Combine(f.Install, "wad/web/index.html"), "concurrent change"); UpdatePackage.Rehash(f.Install);
        await ThrowsAsync(() => UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy), "update.changed");
        Check.Contains("concurrent change", File.ReadAllText(Path.Combine(f.Install, "wad/web/index.html")), "travail concurrent conservé");
    }

    [Test] private static void LightInstallationRefusesFormerFullPacks()
    {
        using var f = new Fixture(); using var service = f.Service();
        var path = Path.Combine(f.Next, UpdatePackage.ManifestPath);
        var manifest = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        manifest["webview2Runtime"] = "fixed"; manifest["webview2Version"] = "156.0.4314.42";
        File.WriteAllText(path, manifest.ToJsonString()); UpdatePackage.Rehash(f.Next);
        Check.Pesto(() => UpdatePackage.Validate(f.Next), "package.edition", "Un ancien pack PROD à WebView2 intégré n’est plus admis");
        Check.Pesto(() => service.InspectLocal(f.Next), "package.edition", "Un ancien pack complet choisi localement ne remplace pas une installation LIGHT");
    }

    [Test] private static async Task AlteredPreparedPackAndTransactionJournalCannotRedirectReplacement()
    {
        using var f = new Fixture(); var request = await f.Prepare(); var original = UpdatePackage.Validate(f.Install).Fingerprint;
        var file = Path.Combine(request.TransactionDirectory, "transaction.json");
        var record = JsonNode.Parse(File.ReadAllText(file))!.AsObject();
        record["installation"] = Path.Combine(f.Root, "profile"); File.WriteAllText(file, record.ToJsonString());
        await ThrowsAsync(() => UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy), "update.journal");
        Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "installation conservée");
        Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "journal détourné ne touche jamais profil");
    }

    [Test] private static async Task PublicExecutionRefusesRunningParentBeforeAnyReplacement()
    {
        using var f = new Fixture(); var request = await f.Prepare(); var fingerprint = UpdatePackage.Validate(f.Install).Fingerprint;
        await ThrowsAsync(() => UpdateTransaction.ExecuteAsync(request.TransactionDirectory, f.Healthy), "update.helper");
        Check.Equal(fingerprint, UpdatePackage.Validate(f.Install).Fingerprint, "aucun remplacement sous parent actif");
    }

    [Test] private static async Task SymlinkedTransactionJournalIsRejectedBeforeReplacement()
    {
        if (OperatingSystem.IsWindows()) return; // Native reparse-point privileges remain a Windows qualification case.
        using var f = new Fixture(); var request = await f.Prepare(); var original = UpdatePackage.Validate(f.Install).Fingerprint;
        var journal = Path.Combine(request.TransactionDirectory, "transaction.json");
        var target = Path.Combine(f.Root, "external-journal.json");
        File.Move(journal, target); File.CreateSymbolicLink(journal, target);
        await ThrowsAsync(() => UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy), "package.link");
        Check.Equal(original, UpdatePackage.Validate(f.Install).Fingerprint, "journal indirect ne peut autoriser le remplacement");
        Check.True(File.Exists(target), "cible externe conservée");
    }

    private static async Task ThrowsAsync(Func<Task> action, string code)
    {
        try { await action(); }
        catch (PestoException error) { Check.Equal(code, error.Code, "code refus"); return; }
        throw new TestFailureException("refus attendu " + code);
    }

    private static IReadOnlyDictionary<string, (long Bytes, string Sha256)> WriteSocleTree(
        string packRoot, (string Rel, byte[] Data)[] files)
    {
        var idx = new Dictionary<string, (long Bytes, string Sha256)>(StringComparer.OrdinalIgnoreCase);
        foreach (var (rel, data) in files)
        {
            var full = Path.Combine(packRoot, "wad/runtime/webview2", rel.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(full)!);
            File.WriteAllBytes(full, data);
            idx["wad/runtime/webview2/" + rel] = (data.Length, Convert.ToHexStringLower(SHA256.HashData(data)));
        }
        return idx;
    }

    private static (string Rel, byte[] Data)[] SocleFiles() =>
    [
        ("msedgewebview2.exe", [0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00]),
        ("core.dll",           [0x4D, 0x5A, 0x90, 0x00, 0x04, 0x00, 0x00, 0x00, 0x01]),
        ("sub/extra.dat",      [0xAA, 0xBB, 0xCC, 0xDD])
    ];

    [Test] private static void SocleExactCopyIsAcceptedOutsideThePackIdentity()
    {
        using var f = new Fixture();
        var baseline = UpdatePackage.Validate(f.Install);
        var files = SocleFiles();
        var index = WriteSocleTree(f.Install, files);
        using var scope = SocleRuntime.OverrideForTests(index);

        var after = UpdatePackage.Validate(f.Install);
        Check.Equal(baseline.Fingerprint, after.Fingerprint, "empreinte inchangée par le Socle");
        Check.Equal(baseline.FileCount, after.FileCount, "FileCount exclut le Socle");
        Check.Equal(baseline.Bytes, after.Bytes, "Bytes exclut le Socle");
        Check.True(after.SoclePresent, "SoclePresent vrai");

        UpdatePackage.Rehash(f.Install);
        var sums = File.ReadAllText(Path.Combine(f.Install, "wad/SHA256SUMS"));
        Check.False(sums.Contains("wad/runtime/webview2", StringComparison.OrdinalIgnoreCase),
            "SHA256SUMS ne contient aucun chemin du Socle");
    }

    [Test] private static void SocleChangedExtraMissingOrEmptyIsRefused()
    {
        using var f = new Fixture();
        var files = SocleFiles();
        var index = WriteSocleTree(f.Install, files);
        using var scope = SocleRuntime.OverrideForTests(index);

        // Octet modifié, même taille
        var exePath = Path.Combine(f.Install, "wad/runtime/webview2/msedgewebview2.exe");
        var bytes = File.ReadAllBytes(exePath); bytes[0] ^= 0xFF; File.WriteAllBytes(exePath, bytes);
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.socle", "octet modifié refusé");
        File.WriteAllBytes(exePath, files[0].Data);

        // Fichier en trop
        var extra = Path.Combine(f.Install, "wad/runtime/webview2/rogue.txt");
        File.WriteAllText(extra, "x");
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.socle", "fichier en trop refusé");
        File.Delete(extra);

        // Fichier manquant
        File.Delete(Path.Combine(f.Install, "wad/runtime/webview2/core.dll"));
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.socle", "fichier manquant refusé");
        File.WriteAllBytes(Path.Combine(f.Install, "wad/runtime/webview2/core.dll"), files[1].Data);

        // Dossier vide
        var socleDir = Path.Combine(f.Install, "wad/runtime/webview2");
        foreach (var entry in Directory.EnumerateFileSystemEntries(socleDir))
        { if (Directory.Exists(entry)) Directory.Delete(entry, true); else File.Delete(entry); }
        Check.Pesto(() => UpdatePackage.Validate(f.Install), "package.socle", "dossier vide refusé");
    }

    [Test] private static async Task InstallCarriesTheSocleAndRollbackKeepsIt()
    {
        using var f = new Fixture();
        var index = WriteSocleTree(f.Install, SocleFiles());
        using var scope = SocleRuntime.OverrideForTests(index);

        var request = await f.Prepare();
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy);
        Check.Equal("completed", result.Status, "installation avec Socle réussie");

        var (state, _) = SocleRuntime.Inspect(f.Install, true);
        Check.Equal(SocleState.Valid, state, "Socle valide après installation");
        Check.Equal("2.0.1", UpdatePackage.Validate(f.Install).Version, "version installée 2.0.1");
        Check.False(Directory.Exists(Path.Combine(f.Next, "wad/runtime/webview2")),
            "le candidat n’a jamais eu de Socle");

        using var service = f.Service();
        Check.True(service.Status()["canRollback"]!.GetValue<bool>(), "retour proposé");
        var rollback = service.RequestRollback(true);
        result = await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, f.Healthy);
        Check.Equal("rolledBack", result.Status, "retour arrière réussi");
        Check.Equal("2.0.0", UpdatePackage.Validate(f.Install).Version, "version restaurée 2.0.0");
        (state, _) = SocleRuntime.Inspect(f.Install, true);
        Check.Equal(SocleState.Valid, state, "Socle encore valide après rollback");
    }

    [Test] private static async Task InstallWithoutSocleNeverCreatesOne()
    {
        using var f = new Fixture();
        var request = await f.Prepare();
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, f.Healthy);
        Check.Equal("completed", result.Status, "installation sans Socle réussie");
        Check.False(Directory.Exists(Path.Combine(f.Install, "wad/runtime/webview2")),
            "aucun Socle créé par l’installation");
    }

    [Test] private static void EmbeddedSocleIndexLoadsTheRealRuntimeInventory()
    {
        var tmp = Path.Combine(Path.GetTempPath(), "pesto-socle-real-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(tmp);
            var (state, _) = SocleRuntime.Inspect(tmp, false);
            Check.Equal(SocleState.Absent, state, "dossier sans Socle vaut Absent");

            var exeDir = Path.Combine(tmp, "wad/runtime/webview2");
            Directory.CreateDirectory(exeDir);
            File.WriteAllBytes(Path.Combine(exeDir, "msedgewebview2.exe"), [0x4D, 0x5A]);
            (state, var problem) = SocleRuntime.Inspect(tmp, false);
            Check.Equal(SocleState.Invalid, state, "Socle partiel vaut Invalid");
            Check.Contains("Fichier manquant", problem, "l’index réel détecte les fichiers absents");
        }
        finally { if (Directory.Exists(tmp)) Directory.Delete(tmp, true); }
    }

    [Test] private static async Task TemporaryUpdateCopiesExpireAndDisposeWithoutTouchingSourcesOrTransactions()
    {
        using var f = new Fixture();
        var clock = new UpdateClock();
        var state = Path.Combine(f.Root, "state");
        using var service = new UpdateService(new(f.Install, state, "PROD", false), clock);
        var archive = Path.Combine(f.Root, "next.zip"); ZipFile.CreateFromDirectory(f.Next, archive);
        var original = UpdatePackage.Hash(archive);
        var candidate = service.InspectLocal(archive)["candidateId"]!.GetValue<string>();
        var ready = await service.PrepareAsync(candidate);
        var work = Directory.GetDirectories(Path.Combine(state, "workspaces")).Single();
        var inspection = Directory.GetDirectories(Path.Combine(work, "inspections")).Single();
        var preparation = Directory.GetDirectories(Path.Combine(work, "prepared")).Single();
        clock.Advance(TimeSpan.FromMinutes(31)); service.Status();
        Check.False(Directory.Exists(inspection), "le candidat ZIP expiré est nettoyé");
        Check.True(Directory.Exists(preparation), "la préparation indépendante reste utilisable deux heures");
        await ThrowsAsync(() => service.PrepareAsync(candidate), "update.stale");
        clock.Advance(TimeSpan.FromHours(2)); service.Status();
        Check.False(Directory.Exists(preparation), "la préparation expirée est nettoyée");
        Check.Pesto(() => service.RequestInstall(ready["preparedId"]!.GetValue<string>(), true), "update.stale", "expiration réellement appliquée");
        candidate = service.InspectLocal(archive)["candidateId"]!.GetValue<string>();
        ready = await service.PrepareAsync(candidate);
        var request = service.RequestInstall(ready["preparedId"]!.GetValue<string>(), true);
        Check.Equal(0, Directory.GetDirectories(Path.Combine(work, "prepared")).Length, "le transfert libère la préparation");
        service.Dispose(); service.Dispose();
        Check.False(Directory.Exists(work), "fermeture idempotente : toutes les copies de cette instance sont supprimées");
        Check.True(File.Exists(request.HelperExecutable), "le helper transactionnel durable reste intact après fermeture");
        UpdateTransaction.ValidateHelperInvocation(request.TransactionDirectory, request.HelperExecutable);
        Check.Equal(original, UpdatePackage.Hash(archive), "le ZIP choisi n'est jamais possédé par le service");
        Check.Equal("2.0.1", UpdatePackage.Validate(f.Next).Version, "le dossier source reste intact");
        Check.Equal("2.0.0", UpdatePackage.Validate(f.Install).Version, "aucune installation exécutée");
        Check.Equal("PRIVATE-USER-SETTINGS", File.ReadAllText(f.UserConfiguration), "profil préservé");
        var refused = false;
        try { service.Status(); } catch (ObjectDisposedException) { refused = true; }
        Check.True(refused, "une instance fermée ne peut créer de nouveaux fichiers");
    }

    [Test] private static void WorkspaceReclaimsOnlyAbandonedMarkedCopiesAndProtectsLiveInstances()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-workspace-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var live = new UpdateWorkspace(root);
            File.WriteAllText(Path.Combine(live.DirectoryPath, "sentinel"), "live");
            var parent = Path.Combine(root, "workspaces");
            var id = Guid.NewGuid().ToString("N"); var abandoned = Path.Combine(parent, id);
            Directory.CreateDirectory(abandoned); File.WriteAllText(Path.Combine(abandoned, "copy"), "orphan");
            File.WriteAllText(Path.Combine(parent, id + ".lease"), "pesto.update-workspace.v1\n" + id + "\n", Encoding.ASCII);
            var unknown = Path.Combine(parent, Guid.NewGuid().ToString("N")); Directory.CreateDirectory(unknown);
            File.WriteAllText(Path.Combine(unknown, "sentinel"), "unknown");
            var legacy = Path.Combine(root, "inspections"); Directory.CreateDirectory(legacy);
            File.WriteAllText(Path.Combine(legacy, "sentinel"), "legacy");
            using (var next = new UpdateWorkspace(root))
            {
                Check.False(Directory.Exists(abandoned), "copie marquée sans détenteur récupérée au prochain usage");
                Check.False(File.Exists(Path.Combine(parent, id + ".lease")), "marqueur récupéré après nettoyage");
                Check.Equal("live", File.ReadAllText(Path.Combine(live.DirectoryPath, "sentinel")), "bail actif conservé");
                Check.Equal("unknown", File.ReadAllText(Path.Combine(unknown, "sentinel")), "répertoire non possédé conservé");
                Check.Equal("legacy", File.ReadAllText(Path.Combine(legacy, "sentinel")), "anciens fichiers sans preuve de propriété conservés");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private sealed class UpdateClock : TimeProvider
    {
        private DateTimeOffset now = new(2026, 11, 9, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => now;
        public void Advance(TimeSpan amount) => now += amount;
    }

    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "pesto-update-tests-" + Guid.NewGuid().ToString("N"));
        public string Install => Path.Combine(Root, "installed");
        public string Next => Path.Combine(Root, "candidate");
        public string UserConfiguration => Path.Combine(Root, "profile", "cfg.json");
        public Fixture()
        {
            MakePack(Install, "2.0.0", 1); MakePack(Next, "2.0.1", 2);
            Directory.CreateDirectory(Path.GetDirectoryName(UserConfiguration)!); File.WriteAllText(UserConfiguration, "PRIVATE-USER-SETTINGS");
        }
        public UpdateService Service() => new(new(Install, Path.Combine(Root, "state"), "PROD", false));
        public async Task<UpdateInstallRequest> Prepare()
        {
            using var service = Service(); var candidate = service.InspectLocal(Next)["candidateId"]!.GetValue<string>();
            var prepared = await service.PrepareAsync(candidate); return service.RequestInstall(prepared["preparedId"]!.GetValue<string>(), true);
        }
        public Task<bool> Healthy(string root, string path, string nonce, CancellationToken cancellationToken)
        {
            var pack = UpdatePackage.Validate(root);
            File.WriteAllText(path, JsonSerializer.Serialize(new { schemaVersion = 1, transactionId = Path.GetFileName(Path.GetDirectoryName(path)), nonce,
                version = pack.Version, executableSha256 = UpdatePackage.Hash(Path.Combine(root, "Pesto.exe")), webViewReady = true, success = true }));
            return Task.FromResult(true);
        }
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }

    private static void MakePack(string root, string version, byte marker)
    {
        Directory.CreateDirectory(Path.Combine(root, "wad/web"));
        var pe = new byte[256]; pe[0] = (byte)'M'; pe[1] = (byte)'Z'; BitConverter.GetBytes(0x80).CopyTo(pe, 0x3c);
        BitConverter.GetBytes(0x4550).CopyTo(pe, 0x80); BitConverter.GetBytes((ushort)0x8664).CopyTo(pe, 0x84);
        BitConverter.GetBytes((ushort)0x20b).CopyTo(pe, 0x98); pe[200] = marker;
        File.WriteAllBytes(Path.Combine(root, "Pesto.exe"), pe);
        ActiveDirectoryTestBundle.CopyToApplication(root);
        File.WriteAllText(Path.Combine(root, "wad/web/index.html"), "<h1>Fixture " + version + "</h1>");
        File.WriteAllText(Path.Combine(root, UpdatePackage.ManifestPath), JsonSerializer.Serialize(new { schemaVersion = 2, packName = "Pesto-v2-portable", version,
            channel = "PROD", entryPoint = "Pesto.exe", layout = "singlefile-wad", repository = "M4D135/pesto", webview2Runtime = "evergreen", distribution = "candidate", official = false }));
        UpdatePackage.Rehash(root);
    }
}
