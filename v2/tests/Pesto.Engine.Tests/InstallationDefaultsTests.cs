using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>
/// Configuration par défaut écrite sur place (2.0.14) : forme locale hors de l’identité du pack, forme scellée des anciens
/// packs personnalisés, bouton « Définir comme configuration par défaut », report à la mise à jour et retour arrière.
/// Les messages attendus sont recopiés de la spécification, jamais lus dans le moteur.
/// </summary>
internal static class InstallationDefaultsTests
{
    private const string DisplayPath = "wad\\defaults\\configuration.json";
    private const string InvalidMessage = "La configuration par défaut de cette installation (wad\\defaults\\configuration.json) est invalide ou illisible : Pesto refuse de l’utiliser. Supprimez ce fichier ou remplacez-le par une configuration exportée valide ; aucun profil n’a été modifié.";
    private const string ConflictMessage = "Le pack choisi apporte une configuration par défaut différente de celle de cette installation. Aucun fichier n’a été remplacé. Retirez wad\\defaults\\configuration.json du pack source ou de cette installation, puis préparez de nouveau la mise à jour.";
    private const string PendingMessage = "Une mise à jour de cette installation est en cours ou interrompue. Traitez-la dans « État et reprise » avant de définir la configuration par défaut. Rien n’a été modifié.";
    private const string SealedMessage = "Cette installation provient d’un ancien pack personnalisé : sa configuration par défaut fait partie de l’inventaire du pack et ne peut pas être remplacée sur place. Installez le pack officiel dans un nouveau dossier, puis définissez-y la configuration par défaut. Rien n’a été modifié.";
    private const string ChangedMessage = "La configuration par défaut de l’installation a changé depuis son affichage. Rien n’a été modifié ; relisez l’état puis recommencez.";
    private const string ReadOnlyMessage = "Le dossier de cette installation n’est pas accessible en écriture : la configuration par défaut n’a pas été enregistrée. Lancez Pesto normalement depuis cette installation (autorisation administrateur), ou exportez la configuration et copiez le fichier sous wad\\defaults\\configuration.json.";
    private static readonly string OtherConfiguration = LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal);
    private const UnixFileMode Writable = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute
        | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute;
    private const UnixFileMode ReadOnly = UnixFileMode.UserRead | UnixFileMode.UserExecute
        | UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute;

    // ---------------------------------------------------------------- UpdatePackage.Validate et Rehash

    [Test] private static void LocalDefaultStaysOutsideThePackIdentity()
    {
        using var b = new Bench();
        var before = UpdatePackage.Validate(b.Install);
        var sums = File.ReadAllBytes(SumsFile(b.Install));
        var bytes = PlaceDefault(b.Install, BundleText("entreprise.1"));
        var after = UpdatePackage.Validate(b.Install);
        Check.Equal(before.Fingerprint, after.Fingerprint, "L’empreinte du pack ne dépend pas du défaut local");
        Check.Equal(before.FileCount, after.FileCount, "FileCount identique avec et sans le défaut local");
        Check.Equal(before.Bytes, after.Bytes, "Bytes identique avec et sans le défaut local");
        Check.Equal("official", after.Distribution, "Un pack officiel reste officiel");
        Check.Null(after.ConfigurationFingerprint, "Aucune empreinte scellée n’est inventée pour un défaut local");
        Check.Null(before.LocalConfigurationVersion, "Sans fichier, aucune version locale");
        Check.Null(before.LocalConfigurationFingerprint, "Sans fichier, aucune empreinte locale");
        Check.Equal("entreprise.1", after.LocalConfigurationVersion, "Version du défaut local renseignée");
        Check.Equal(FingerprintOf(), after.LocalConfigurationFingerprint, "Empreinte de configuration du défaut local renseignée");
        UpdatePackage.Rehash(b.Install);
        Check.True(sums.SequenceEqual(File.ReadAllBytes(SumsFile(b.Install))), "Rehash n’inscrit jamais le défaut local");
        Check.False(Sums(b.Install).Contains("wad/defaults", StringComparison.OrdinalIgnoreCase), "SHA256SUMS ne cite aucun chemin de wad/defaults");
        Check.Equal(before.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Empreinte inchangée après Rehash");
        Check.True(Same(bytes, DefaultBytes(b.Install)), "La validation ne réécrit jamais le fichier");
        // Limite exacte : 1 Mio est admis, un octet de plus est refusé.
        var padded = BundleText("entreprise.1");
        padded += new string(' ', ConfigurationDocument.MaximumBytes - Encoding.UTF8.GetByteCount(padded));
        PlaceDefault(b.Install, padded);
        Check.Equal(before.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Un défaut local de 1 Mio exactement est admis");
        PlaceDefault(b.Install, padded + " ");
        Refused(() => UpdatePackage.Validate(b.Install), "package.defaults", InvalidMessage, "Un octet au-delà de 1 Mio est refusé");
    }

    [Test] private static void InvalidLocalDefaultIsRefusedWithTheExactMessage()
    {
        using var b = new Bench();
        var tampered = JsonNode.Parse(BundleText())!.AsObject(); tampered["fingerprint"] = new string('0', 64);
        var account = JsonNode.Parse(BundleText())!.AsObject(); account["configuration"]!["CONF"]![0]!["ADM"] = "EXAMPLE\\admin-postes";
        var unknown = JsonNode.Parse(BundleText())!.AsObject(); unknown["password"] = "ne-jamais-diffuser";
        var debug = JsonNode.Parse(BundleText())!.AsObject(); debug["configuration"]!["DEBUG"] = new JsonObject { ["Simulation"] = "true" };
        var nested = JsonNode.Parse(BundleText())!.AsObject(); nested["configuration"]!["CONF"]![0]!["Domaine"] = new JsonObject { ["x"] = 1 };
        var cases = new (string Label, byte[] Bytes)[]
        {
            ("JSON cassé", Encoding.UTF8.GetBytes("{\"schema\":1,")),
            ("fichier vide", []),
            ("tableau JSON", Encoding.UTF8.GetBytes("[1,2]")),
            ("empreinte de configuration fausse", Encoding.UTF8.GetBytes(tampered.ToJsonString())),
            ("compte non diffusable", Encoding.UTF8.GetBytes(account.ToJsonString())),
            ("champ inconnu à la racine", Encoding.UTF8.GetBytes(unknown.ToJsonString())),
            ("réglages de débogage non diffusables", Encoding.UTF8.GetBytes(debug.ToJsonString())),
            ("valeur structurée au lieu d’un texte", Encoding.UTF8.GetBytes(nested.ToJsonString())),
            ("profil brut au lieu d’une configuration exportée", Encoding.UTF8.GetBytes(LiveTestConfig.Valid)),
            ("plus de 1 Mio", Encoding.UTF8.GetBytes(BundleText() + new string(' ', ConfigurationDocument.MaximumBytes))),
            ("encodage UTF-8 invalide", [0xc3, 0x28]),
            ("BOM UTF-8 suivi d’un octet invalide", [0xef, 0xbb, 0xbf, 0xff]),
        };
        foreach (var (label, bytes) in cases)
        {
            PlaceDefault(b.Install, bytes);
            Refused(() => UpdatePackage.Validate(b.Install), "package.defaults", InvalidMessage, "Défaut local refusé : " + label);
            Check.Equal("invalid", InstallationDefaults.Inspect(b.Install).State, "Inspect signale invalid sans lever : " + label);
            Check.True(bytes.SequenceEqual(File.ReadAllBytes(InstallationDefaults.PathIn(b.Install))), "Fichier refusé laissé intact : " + label);
        }
        if (!OperatingSystem.IsWindows())
        {
            // Les liens sont refusés avant toute lecture (inventaire fermé).
            var target = Path.Combine(b.Root, "outside.json"); File.WriteAllText(target, BundleText());
            File.Delete(InstallationDefaults.PathIn(b.Install));
            File.CreateSymbolicLink(InstallationDefaults.PathIn(b.Install), target);
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.link", "Un lien à la place du défaut local est refusé");
            File.Delete(InstallationDefaults.PathIn(b.Install));
        }
    }

    [Test] private static void WriterTemporariesAreToleratedUnreadAndNeverHashed()
    {
        using var b = new Bench();
        var before = UpdatePackage.Validate(b.Install);
        var lower = PlaceDebris(b.Install, ".configuration-" + new string('a', 32) + ".tmp", Encoding.UTF8.GetBytes("{ écriture interrompue"));
        PlaceDebris(b.Install, ".configuration-" + new string('B', 32) + ".tmp", [0xc3, 0x28]);
        PlaceDebris(b.Install, null, new byte[ConfigurationDocument.MaximumBytes + 10]);
        var debrisOnly = UpdatePackage.Validate(b.Install);
        Check.Equal(before.Fingerprint, debrisOnly.Fingerprint, "Les débris ne changent pas l’empreinte");
        Check.Equal(before.FileCount, debrisOnly.FileCount, "Les débris ne comptent pas dans FileCount");
        Check.Equal(before.Bytes, debrisOnly.Bytes, "Les débris ne comptent pas dans Bytes");
        Check.Null(debrisOnly.LocalConfigurationFingerprint, "Un débris n’est jamais pris pour un défaut");
        Check.Equal("missing", InstallationDefaults.Inspect(b.Install).State, "Des débris seuls laissent l’état missing");
        PlaceDefault(b.Install, BundleText("entreprise.1"));
        var withDefault = UpdatePackage.Validate(b.Install);
        Check.Equal(before.Fingerprint, withDefault.Fingerprint, "Défaut local et débris restent hors identité");
        Check.Equal(before.FileCount, withDefault.FileCount, "FileCount inchangé avec défaut local et débris");
        Check.Equal(FingerprintOf(), withDefault.LocalConfigurationFingerprint, "Le défaut local reste lu à côté des débris");
        if (!OperatingSystem.IsWindows() && Environment.UserName != "root")
        {
            // Un débris illisible prouve qu’il n’est jamais ouvert, ni par la validation ni par Rehash.
            File.SetUnixFileMode(lower, (UnixFileMode)0);
            try
            {
                Check.Equal(before.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Débris illisible jamais ouvert par Validate");
                Check.Equal("local", InstallationDefaults.Inspect(b.Install).State, "Débris illisible jamais ouvert par Inspect");
                UpdatePackage.Rehash(b.Install);
            }
            finally { File.SetUnixFileMode(lower, UnixFileMode.UserRead | UnixFileMode.UserWrite); }
        }
        else UpdatePackage.Rehash(b.Install);
        Check.False(Sums(b.Install).Contains("wad/defaults", StringComparison.OrdinalIgnoreCase), "Rehash n’inscrit ni débris ni défaut local");
        Check.Equal(before.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Inventaire identique après Rehash");
    }

    [Test] private static void AnyOtherFileUnderDefaultsIsRefused()
    {
        using var b = new Bench();
        PlaceDefault(b.Install, BundleText());
        var hex = new string('a', 32);
        foreach (var relative in new[]
        {
            "wad/defaults/backups/configuration.json.20261112-080000.bak", "wad/defaults/configuration.json.bak",
            "wad/defaults/.configuration-" + new string('a', 31) + ".tmp", "wad/defaults/.configuration-" + new string('a', 33) + ".tmp",
            "wad/defaults/.configuration-" + new string('g', 32) + ".tmp", "wad/defaults/configuration-" + hex + ".tmp",
            "wad/defaults/.configuration-" + hex + ".tmp.bak", "wad/defaults/.configuration-" + hex + ".json",
            "wad/defaults/other.json", "wad/defaults/sub/configuration.json", "wad/.configuration-" + hex + ".tmp", "wad/configuration.json"
        })
        {
            Check.False(InstallationDefaults.IsDebris(relative), "Hors du motif exact du temporaire : " + relative);
            var path = Path.Combine(b.Install, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, BundleText());
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.file", "Fichier refusé : " + relative);
            UpdatePackage.Rehash(b.Install);
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.file", "Refusé même inscrit dans SHA256SUMS : " + relative);
            File.Delete(path); UpdatePackage.Rehash(b.Install);
            Check.Equal("official", UpdatePackage.Validate(b.Install).Distribution, "Pack de nouveau valide après retrait de " + relative);
        }
        Check.True(InstallationDefaults.IsDebris("wad/defaults/.configuration-" + Guid.NewGuid().ToString("N") + ".tmp"), "Temporaire de ConfigurationStore.Write reconnu");
        Check.True(InstallationDefaults.IsDebris("WAD/Defaults/.Configuration-" + new string('F', 32) + ".TMP"), "Motif insensible à la casse comme l’inventaire");
        Check.False(InstallationDefaults.IsDebris("x/wad/defaults/.configuration-" + hex + ".tmp"), "Motif ancré au début");
    }

    [Test] private static void LegacySealedPackStaysValidAndItsSealedFileIsProtected()
    {
        using var b = new Bench();
        var sealedBytes = b.Seal(b.Install, LiveTestConfig.Valid, "entreprise.1");
        var info = UpdatePackage.Validate(b.Install);
        Check.Equal("custom", info.Distribution, "Ancien pack personnalisé toujours valide");
        Check.Equal(FingerprintOf(), info.ConfigurationFingerprint, "Empreinte scellée déclarée par le manifeste");
        Check.Null(info.LocalConfigurationFingerprint, "Un fichier scellé n’est pas un défaut local");
        Check.Null(info.LocalConfigurationVersion, "Aucune version locale pour un fichier scellé");
        Check.Contains("  wad/defaults/configuration.json", Sums(b.Install), "Rehash inscrit le fichier scellé");
        var state = InstallationDefaults.Inspect(b.Install);
        Check.Equal("sealed", state.State, "Inspect reconnaît la forme scellée");
        Check.Equal("entreprise.1", state.Version, "Version scellée");
        Check.Equal(FingerprintOf(), state.Fingerprint, "Empreinte scellée");
        Check.Equal(Sha(sealedBytes), state.Sha256, "SHA-256 du fichier scellé");
        Check.True(state.Present, "Un fichier scellé est présent");
        var debris = PlaceDebris(b.Install);
        UpdatePackage.Rehash(b.Install);
        Check.False(Sums(b.Install).Contains(Path.GetFileName(debris), StringComparison.OrdinalIgnoreCase), "Rehash n’inscrit jamais un débris, même dans un pack scellé");
        Check.Equal(info.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Débris toléré à côté d’un fichier scellé");
        var path = InstallationDefaults.PathIn(b.Install);
        File.AppendAllText(path, "\n");
        Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.hashes", "Fichier scellé modifié d’un octet refusé");
        File.WriteAllText(path, BundleText("entreprise.1", OtherConfiguration));
        Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Autre configuration à la place du fichier scellé refusée");
        File.WriteAllText(path, BundleText("entreprise.2"));
        Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Version différente de celle du manifeste refusée");
        File.Delete(path);
        Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Manifeste déclarant une configuration absente refusé");
        Check.Equal("missing", InstallationDefaults.Inspect(b.Install).State, "Fichier scellé supprimé : missing");
        File.WriteAllBytes(path, sealedBytes);
        Check.Equal(info.Fingerprint, UpdatePackage.Validate(b.Install).Fingerprint, "Le fichier scellé d’origine est de nouveau accepté");
    }

    [Test] private static void LegacyCustomPackBuilderNeverSealsTheLocalDefaultOfItsSource()
    {
        using var b = new Bench();
        var local = PlaceDefault(b.Next, BundleText("diffusion.1", OtherConfiguration));
        PlaceDebris(b.Next);
        var sourceFingerprint = UpdatePackage.Validate(b.Next).Fingerprint;
        var destination = Path.Combine(b.Root, "legacy-custom");
        var built = LegacyCustomPack.Build(b.Next, destination, ConfigurationDocument.Export(LiveTestConfig.Valid, "entreprise.1"), "entreprise.1");
        Check.Equal("custom", built.Distribution, "Pack personnalisé historique fabriqué");
        Check.Equal(FingerprintOf(), built.ConfigurationFingerprint, "La configuration demandée est scellée, pas le défaut local de la source");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(destination)), "Ni débris ni ancien défaut dans le pack scellé");
        Check.Equal("sealed", InstallationDefaults.Inspect(destination).State, "Forme scellée");
        Check.Equal(sourceFingerprint, UpdatePackage.Validate(b.Next).Fingerprint, "Source inchangée");
        Check.True(Same(local, DefaultBytes(b.Next)), "Défaut local de la source conservé");
        Check.Pesto(() => LegacyCustomPack.Build(b.Next, Path.Combine(b.Root, "other-custom"), ConfigurationDocument.Export(LiveTestConfig.Valid, "entreprise.1"), "entreprise.2"),
            "package.defaults", "Version incohérente refusée");
        Check.False(Directory.Exists(Path.Combine(b.Root, "other-custom")), "Aucun pack partiel");
    }

    [Test] private static void MixedDefaultsFormsAreRefused()
    {
        using (var b = new Bench())
        {
            var bytes = PlaceDefault(b.Install, BundleText("entreprise.1"));
            File.AppendAllText(SumsFile(b.Install), Sha(bytes) + "  " + InstallationDefaults.RelativePath + "\n");
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Fichier inscrit dans SHA256SUMS sans manifeste personnalisé refusé");
        }
        using (var b = new Bench())
        {
            EditManifest(b.Install, m => { m["distribution"] = "custom"; m["official"] = false; m["configurationVersion"] = "entreprise.1"; m["configurationFingerprint"] = FingerprintOf(); });
            UpdatePackage.Rehash(b.Install);
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Manifeste déclarant une configuration sans fichier refusé");
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            // Fichier présent mais non listé alors que le manifeste le déclare : refusé (code de couverture de l’inventaire).
            Refused(() => UpdatePackage.Validate(b.Install), ["package.defaults", "package.hashes"], "Manifeste déclarant une empreinte sans fichier listé refusé");
            UpdatePackage.Rehash(b.Install);
            Check.Equal("custom", UpdatePackage.Validate(b.Install).Distribution, "Une fois inscrit, c’est un ancien pack personnalisé valide");
        }
        using (var b = new Bench())
        {
            EditManifest(b.Install, m => m["configurationVersion"] = "entreprise.1");
            UpdatePackage.Rehash(b.Install);
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Version déclarée hors pack personnalisé refusée");
        }
        using (var b = new Bench())
        {
            EditManifest(b.Install, m => { m["distribution"] = "custom"; m["official"] = false; });
            UpdatePackage.Rehash(b.Install);
            var bytes = PlaceDefault(b.Install, BundleText("entreprise.1"));
            File.AppendAllText(SumsFile(b.Install), Sha(bytes) + "  " + InstallationDefaults.RelativePath + "\n");
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Fichier listé dans un pack personnalisé sans empreinte déclarée refusé");
        }
        using (var b = new Bench())
        {
            EditManifest(b.Install, m => { m["configurationVersion"] = "entreprise.1"; m["configurationFingerprint"] = FingerprintOf(); });
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            UpdatePackage.Rehash(b.Install);
            Check.Contains("wad/defaults/configuration.json", Sums(b.Install), "Le manifeste déclarant une configuration la fait inscrire");
            Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.defaults", "Pack officiel déclarant une configuration scellée refusé");
        }
    }

    // ---------------------------------------------------------------- InstallationDefaults.Inspect

    [Test] private static void InspectReportsMissingLocalSealedAndInvalidWithoutHashingThePack()
    {
        using var b = new Bench();
        var missing = InstallationDefaults.Inspect(b.Install);
        Check.Equal("missing", missing.State, "Aucun fichier : missing");
        Check.False(missing.Present, "missing n’est pas présent");
        Check.True(missing.Version is null && missing.Fingerprint is null && missing.Sha256 is null, "missing sans valeurs");
        var json = missing.ToJson();
        Check.Equal(DisplayPath, json["path"]!.GetValue<string>(), "Chemin affiché wad\\defaults\\configuration.json");
        Check.Equal("missing", json["state"]!.GetValue<string>(), "État sérialisé");
        Check.True(json["version"] is null && json["fingerprint"] is null && json["sha256"] is null, "Valeurs nulles sérialisées");
        Check.Equal(5, json.Count, "Exactement state, path, version, fingerprint, sha256");
        var bytes = PlaceDefault(b.Install, BundleText("entreprise.1"));
        var local = InstallationDefaults.Inspect(b.Install);
        Check.Equal("local", local.State, "Défaut local reconnu");
        Check.True(local.Present, "Défaut local présent");
        Check.Equal("entreprise.1", local.Version, "Version du défaut local");
        Check.Equal(FingerprintOf(), local.Fingerprint, "Empreinte de configuration du défaut local");
        Check.Equal(Sha(bytes), local.Sha256, "SHA-256 des octets du fichier");
        Check.Equal(Sha(bytes), local.ToJson()["sha256"]!.GetValue<string>(), "SHA-256 sérialisé");
        // Lecture légère : un pack par ailleurs altéré ne change pas la réponse (aucun hachage complet).
        File.AppendAllText(Path.Combine(b.Install, "wad/web/index.html"), "modifié");
        Check.Pesto(() => UpdatePackage.Validate(b.Install), "package.hashes", "Le pack est bien altéré");
        Check.Equal("local", InstallationDefaults.Inspect(b.Install).State, "Inspect ne hache pas tout le pack");
        PlaceDefault(b.Install, "{ cassé");
        var invalid = InstallationDefaults.Inspect(b.Install);
        Check.Equal("invalid", invalid.State, "Fichier invalide : invalid sans exception");
        Check.False(invalid.Present, "invalid n’est jamais présenté comme utilisable");
        Check.True(invalid.Version is null && invalid.Fingerprint is null && invalid.Sha256 is null, "invalid sans valeurs");
        PlaceDefault(b.Install, BundleText());
        File.WriteAllText(Path.Combine(b.Install, UpdatePackage.ManifestPath), "{ manifeste cassé");
        Check.Equal("invalid", InstallationDefaults.Inspect(b.Install).State, "Manifeste illisible avec un fichier : invalid sans exception");
        Check.Equal("missing", InstallationDefaults.Inspect(Path.Combine(b.Root, "absent")).State, "Dossier absent : missing");
        using var s = new Bench();
        var sealedBytes = s.Seal(s.Install, LiveTestConfig.Valid, "entreprise.2");
        var sealedState = InstallationDefaults.Inspect(s.Install);
        Check.Equal("sealed", sealedState.State, "Ancien pack personnalisé : sealed");
        Check.Equal("entreprise.2", sealedState.Version, "Version scellée");
        Check.Equal(Sha(sealedBytes), sealedState.Sha256, "SHA-256 scellé");
        File.WriteAllText(InstallationDefaults.PathIn(s.Install), "{");
        Check.Equal("invalid", InstallationDefaults.Inspect(s.Install).State, "Fichier scellé illisible : invalid");
    }

    // ---------------------------------------------------------------- ProfileConfigurationService.WriteInstallationDefault

    [Test] private static void WritingTheDefaultLeavesTheProgramFilesAndThePackIdentityUnchanged()
    {
        foreach (var distribution in new[] { "official", "candidate" })
        {
            using var b = new Bench(distribution: distribution);
            var author = b.Profile("author");
            var before = UpdatePackage.Validate(b.Install);
            var sums = File.ReadAllBytes(SumsFile(b.Install));
            var manifest = File.ReadAllBytes(Path.Combine(b.Install, UpdatePackage.ManifestPath));
            var exe = File.ReadAllBytes(Path.Combine(b.Install, "Pesto.exe"));
            var result = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
            var file = InstallationDefaults.PathIn(b.Install);
            var expected = Encoding.UTF8.GetBytes(ConfigurationDocument.Canonical(author.Export("entreprise.1")));
            Check.True(expected.SequenceEqual(File.ReadAllBytes(file)), "Fichier = Canonical(Export(version)) en UTF-8 sans BOM : " + distribution);
            Check.Equal("written", Harness.Str(result, "status"), "Statut written");
            Check.Equal(DisplayPath, Harness.Str(result, "path"), "Chemin affiché");
            Check.Equal(file, Harness.Str(result, "file"), "Chemin complet du fichier");
            Check.Equal("entreprise.1", Harness.Str(result, "version"), "Version écrite");
            Check.Equal(FingerprintOf(), Harness.Str(result, "fingerprint"), "Empreinte de configuration");
            Check.Equal(Sha(expected), Harness.Str(result, "sha256"), "SHA-256 des octets écrits");
            Check.False(Harness.Bool(result, "replaced"), "Aucun fichier remplacé");
            Check.Null(result["previous"], "Pas d’état précédent");
            Check.Null(result["backup"], "Pas de sauvegarde sans ancien fichier");
            Check.Equal(distribution, Harness.Str(result, "distribution"), "Distribution annoncée inchangée");
            Check.Equal(distribution == "official", Harness.Bool(result, "official"), "Provenance officielle inchangée");
            Check.Equal(before.Fingerprint, Harness.Str(result, "packFingerprint"), "Empreinte du pack inchangée annoncée");
            var after = UpdatePackage.Validate(b.Install);
            Check.Equal(before.Fingerprint, after.Fingerprint, "Empreinte du pack inchangée");
            Check.Equal(distribution, after.Distribution, "Distribution inchangée");
            Check.Equal(before.FileCount, after.FileCount, "FileCount inchangé");
            Check.Equal(before.Bytes, after.Bytes, "Bytes inchangé");
            Check.Equal(FingerprintOf(), after.LocalConfigurationFingerprint, "Défaut local reconnu par le validateur");
            Check.Equal("entreprise.1", after.LocalConfigurationVersion, "Version locale reconnue");
            Check.Null(after.ConfigurationFingerprint, "Rien n’est scellé");
            Check.True(sums.SequenceEqual(File.ReadAllBytes(SumsFile(b.Install))), "SHA256SUMS inchangé à l’octet");
            Check.True(manifest.SequenceEqual(File.ReadAllBytes(Path.Combine(b.Install, UpdatePackage.ManifestPath))), "Manifeste inchangé à l’octet");
            Check.True(exe.SequenceEqual(File.ReadAllBytes(Path.Combine(b.Install, "Pesto.exe"))), "Pesto.exe inchangé à l’octet");
            Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Ni temporaire ni sauvegarde dans wad\\defaults");
            Check.False(Directory.Exists(Path.Combine(author.ConfigurationRoot, "backups")), "Aucune sauvegarde dans le profil sans ancien fichier");
            var text = File.ReadAllText(file);
            Check.False(text.Contains("admin-postes", StringComparison.Ordinal) || text.Contains("DEBUG", StringComparison.Ordinal), "Compte et débogage exclus");
            var state = InstallationDefaults.Inspect(b.Install);
            Check.Equal("local", state.State, "Inspect : local");
            Check.Equal(Sha(expected), state.Sha256, "Inspect : même SHA-256");
        }
    }

    [Test] private static void ReplacingTheDefaultBacksUpTheExactPreviousBytesInTheProfile()
    {
        using var b = new Bench();
        var author = b.Profile("author", clock: new FixedClock());
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var previous = File.ReadAllBytes(InstallationDefaults.PathIn(b.Install));
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        var second = author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(first, "sha256"));
        Check.Equal("written", Harness.Str(second, "status"), "Remplacement écrit");
        Check.True(Harness.Bool(second, "replaced"), "replaced vrai");
        Check.Equal("entreprise.2", Harness.Str(second, "version"), "Nouvelle version");
        Check.Equal(FingerprintOf(OtherConfiguration), Harness.Str(second, "fingerprint"), "Nouvelle empreinte");
        var before = second["previous"]!;
        Check.Equal("entreprise.1", Harness.Str(before, "version"), "Version précédente annoncée");
        Check.Equal(FingerprintOf(), Harness.Str(before, "fingerprint"), "Empreinte précédente annoncée");
        Check.Equal(Harness.Str(first, "sha256"), Harness.Str(before, "sha256"), "SHA-256 précédent annoncé");
        var backup = Harness.Str(second, "backup");
        Check.Equal(Path.Combine(author.ConfigurationRoot, "backups"), Path.GetDirectoryName(backup), "Sauvegarde dans le profil, jamais dans le pack");
        Check.True(Regex.IsMatch(Path.GetFileName(backup), "^installation-default\\.20261023-080000\\.[0-9a-f]{32}\\.json$"), "Nom de sauvegarde horodaté : " + Path.GetFileName(backup));
        Check.True(previous.SequenceEqual(File.ReadAllBytes(backup)), "Copie exacte de l’ancien fichier");
        var written = File.ReadAllBytes(InstallationDefaults.PathIn(b.Install));
        Check.True(Encoding.UTF8.GetBytes(ConfigurationDocument.Canonical(author.Export("entreprise.2"))).SequenceEqual(written), "Nouveau contenu exact");
        Check.Equal(Sha(written), Harness.Str(second, "sha256"), "SHA-256 du nouveau fichier");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun débris ni sauvegarde dans wad\\defaults");
        Check.Equal(FingerprintOf(OtherConfiguration), UpdatePackage.Validate(b.Install).LocalConfigurationFingerprint, "Validateur : nouveau défaut local");
    }

    [Test] private static void SameConfigurationIsUnchangedWithoutWriteOrBackup()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var file = InstallationDefaults.PathIn(b.Install);
        var bytes = File.ReadAllBytes(file);
        var old = DateTime.UtcNow.AddHours(-3); File.SetLastWriteTimeUtc(file, old);
        var again = author.WriteInstallationDefault(b.Install, "entreprise.9", Harness.Str(first, "sha256"));
        Check.Equal("unchanged", Harness.Str(again, "status"), "Même configuration : unchanged");
        Check.Equal("entreprise.1", Harness.Str(again, "version"), "La version publiée est conservée");
        Check.Equal(FingerprintOf(), Harness.Str(again, "fingerprint"), "Empreinte identique");
        Check.Equal(Harness.Str(first, "sha256"), Harness.Str(again, "sha256"), "SHA-256 du fichier existant");
        Check.False(Harness.Bool(again, "replaced"), "Rien remplacé");
        Check.Null(again["backup"], "Aucune sauvegarde");
        Check.True(bytes.SequenceEqual(File.ReadAllBytes(file)), "Aucune écriture");
        Check.Equal(old, File.GetLastWriteTimeUtc(file), "Fichier jamais réécrit");
        Check.False(Directory.Exists(Path.Combine(author.ConfigurationRoot, "backups")), "Aucune sauvegarde dans le profil");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun temporaire");
    }

    [Test] private static void ExpectedDigestGuardsAgainstAStaleDisplay()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var shown = new string('a', 64);
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.1", shown), "config.default_changed", ChangedMessage, "Fichier attendu mais absent");
        Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Rien n’est créé après le refus");
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var bytes = DefaultBytes(b.Install);
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", ""), "config.default_changed", ChangedMessage, "Fichier présent alors qu’aucun n’était affiché");
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", shown), "config.default_changed", ChangedMessage, "Empreinte affichée différente");
        Check.True(Same(bytes, DefaultBytes(b.Install)), "Fichier existant intact après les refus");
        Check.False(Directory.Exists(Path.Combine(author.ConfigurationRoot, "backups")), "Aucune sauvegarde après un refus");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun temporaire après un refus");
        Check.Equal("written", Harness.Str(author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(first, "sha256")), "status"), "Empreinte relue : écriture admise");
        var absent = Path.Combine(b.Root, "absent");
        foreach (var malformed in new[] { "ABC", new string('A', 64), new string('a', 63), new string('a', 65), new string('g', 64), " " + new string('a', 63) })
            Check.Pesto(() => author.WriteInstallationDefault(absent, "entreprise.3", malformed), "invalid_arguments", "Empreinte attendue mal formée refusée avant tout accès : « " + malformed + " »");
        Check.False(Directory.Exists(absent), "Aucun chemin créé pour une empreinte mal formée");
    }

    [Test] private static void LegacySealedInstallationRefusesInPlaceDefinition()
    {
        using var b = new Bench();
        var sealedBytes = b.Seal(b.Install, LiveTestConfig.Valid, "entreprise.1");
        var sums = File.ReadAllBytes(SumsFile(b.Install));
        var manifest = File.ReadAllBytes(Path.Combine(b.Install, UpdatePackage.ManifestPath));
        var author = b.Profile("author", OtherConfiguration);
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", ""), "config.default_sealed", SealedMessage, "Ancien pack personnalisé refusé");
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", Sha(sealedBytes)), "config.default_sealed", SealedMessage, "Refusé même avec l’empreinte affichée");
        Refused(() => b.Profile("same").WriteInstallationDefault(b.Install, "entreprise.1", Sha(sealedBytes)), "config.default_sealed", SealedMessage, "Refusé même pour la configuration scellée elle-même");
        Check.True(Same(sealedBytes, DefaultBytes(b.Install)), "Fichier scellé intact");
        Check.True(sums.SequenceEqual(File.ReadAllBytes(SumsFile(b.Install))), "SHA256SUMS intact");
        Check.True(manifest.SequenceEqual(File.ReadAllBytes(Path.Combine(b.Install, UpdatePackage.ManifestPath))), "Manifeste intact");
        Check.Equal("custom", UpdatePackage.Validate(b.Install).Distribution, "Pack personnalisé toujours valide");
        Check.False(Directory.Exists(Path.Combine(author.ConfigurationRoot, "backups")), "Aucune sauvegarde");
    }

    [Test] private static async Task PendingUpdateTransactionRefusesAndACompletedOneAllowsWriting()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var request = await b.Prepare();
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.1", ""), "update.pending", PendingMessage, "Transaction préparée non terminale");
        Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Rien n’est écrit pendant une transaction");
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy);
        Check.Equal("completed", result.Status, "Transaction terminée");
        var written = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        Check.Equal("written", Harness.Str(written, "status"), "Transaction terminée : écriture admise");
        Check.Equal(UpdatePackage.Validate(b.Next).Fingerprint, Harness.Str(written, "packFingerprint"), "Empreinte de la version installée");
        using var interrupted = new Bench();
        var pending = await interrupted.Prepare();
        try
        {
            await UpdateTransaction.ExecuteCoreAsync(pending.TransactionDirectory, interrupted.Healthy, checkpoint: point => { if (point == "checking") throw new UpdateInterruptionException(); });
            throw new TestFailureException("interruption non injectée");
        }
        catch (UpdateInterruptionException) { }
        Refused(() => interrupted.Profile("author").WriteInstallationDefault(interrupted.Install, "entreprise.1", ""), "update.pending", PendingMessage, "Transaction interrompue");
        Check.False(Directory.Exists(DefaultsDirectory(interrupted.Install)), "Rien n’est écrit pendant une reprise en attente");
    }

    [Test] private static void ReadOnlyInstallationFolderIsRefusedWithoutFileOrDebris()
    {
        if (OperatingSystem.IsWindows()) return; // Les droits NTFS et l’UAC sont qualifiés sur Windows.
        using var b = new Bench();
        var author = b.Profile("author");
        var before = UpdatePackage.Validate(b.Install).Fingerprint;
        var wad = Path.Combine(b.Install, "wad");
        File.SetUnixFileMode(wad, ReadOnly);
        try
        {
            if (CanCreate(wad)) return; // Utilisateur root : aucun refus de droits simulable.
            Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.1", ""), "config.default_readonly", ReadOnlyMessage, "wad non inscriptible");
            Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Ni dossier, ni fichier, ni débris créé");
        }
        finally { File.SetUnixFileMode(wad, Writable); }
        Check.Equal(before, UpdatePackage.Validate(b.Install).Fingerprint, "Pack intact après le refus");
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var bytes = DefaultBytes(b.Install);
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        var defaults = DefaultsDirectory(b.Install);
        File.SetUnixFileMode(defaults, ReadOnly);
        try
        {
            if (CanCreate(defaults)) return;
            Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(first, "sha256")), "config.default_readonly", ReadOnlyMessage, "wad\\defaults non inscriptible");
            Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun débris laissé dans wad\\defaults");
            Check.True(Same(bytes, DefaultBytes(b.Install)), "Ancien défaut intact");
            var backups = Path.Combine(author.ConfigurationRoot, "backups");
            Check.False(Directory.Exists(backups) && Directory.EnumerateFileSystemEntries(backups).Any(), "Aucune copie inutile laissée dans le profil après le refus");
        }
        finally { File.SetUnixFileMode(defaults, Writable); }
        Check.Equal(FingerprintOf(), UpdatePackage.Validate(b.Install).LocalConfigurationFingerprint, "L’ancien défaut reste celui de l’installation");
    }

    [Test] private static void AnUnrecordedAuthorDecisionDoesNotTurnAWrittenDefaultIntoARefusal()
    {
        if (OperatingSystem.IsWindows()) return; // Les droits NTFS sont qualifiés sur Windows.
        using var b = new Bench();
        var author = b.Profile("author");
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        Check.True(Harness.Bool(first, "decisionSaved"), "Décision mémorisée quand le profil est inscriptible");
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        var backups = Path.Combine(author.ConfigurationRoot, "backups");
        Directory.CreateDirectory(backups);
        File.SetUnixFileMode(author.ConfigurationRoot, ReadOnly);
        try
        {
            if (CanCreate(author.ConfigurationRoot)) return; // Utilisateur root : aucun refus de droits simulable.
            var written = author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(first, "sha256"));
            Check.Equal("written", Harness.Str(written, "status"), "Fichier écrit et vérifié malgré le profil non inscriptible");
            Check.False(Harness.Bool(written, "decisionSaved"), "decisionSaved=false annoncé");
            Check.Equal("entreprise.2", UpdatePackage.Validate(b.Install).LocalConfigurationVersion, "Le nouveau défaut est celui de l’installation");
            var unchanged = author.WriteInstallationDefault(b.Install, "entreprise.3", Harness.Str(written, "sha256"));
            Check.Equal("unchanged", Harness.Str(unchanged, "status"), "Même empreinte : unchanged");
            Check.False(Harness.Bool(unchanged, "decisionSaved"), "unchanged : decisionSaved=false annoncé");
        }
        finally { File.SetUnixFileMode(author.ConfigurationRoot, Writable); }
    }

    [Test] private static async Task RollbackRequestsTheTransactionAnnouncedByStatus()
    {
        using var b = new Bench("2.0.13", "2.0.14");
        await b.InstallNext();
        var completed = UpdateTransaction.List(b.Install).Single(t => t.Status == "completed");
        Directory.Delete(Path.Combine(completed.TransactionDirectory, "backup"), true);
        using var service = b.Service();
        var status = service.Status();
        Check.False(Harness.Bool(status, "canRollback"), "Sans sauvegarde, aucun retour annoncé");
        Check.Null(status["rollbackVersion"], "Sans sauvegarde, aucune version annoncée");
        Refused(() => service.RequestRollback(true), "update.rollback", "Aucune installation terminée ne dispose d’un retour disponible.",
            "La demande suit le même choix que l’état : aucune transaction sans sauvegarde");
    }

    [Test] private static async Task InterruptedUpdateAnnouncesTheVersionRestoredByRecovery()
    {
        using var b = new Bench("2.0.13", "2.0.14");
        var request = await b.Prepare();
        try
        {
            await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy,
                checkpoint: point => { if (point == "candidateMoved") throw new UpdateInterruptionException(); });
            throw new TestFailureException("interruption non injectée");
        }
        catch (UpdateInterruptionException) { }
        using var service = b.Service();
        var status = service.Status();
        Check.True(Harness.Bool(status, "pendingRecovery"), "Reprise attendue");
        Check.Equal("2.0.13", Harness.Str(status, "recoveryVersion"), "Version rétablie par la reprise : celle qui a préparé la mise à jour");
    }

    [Test] private static void IsolatedModesRefuseInstallationDefaultBeforeAnyAccess()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-defaults-isolated-" + Guid.NewGuid().ToString("N"));
        foreach (var mode in new[] { ConfigurationAccessMode.Demo, ConfigurationAccessMode.HealthCheck, ConfigurationAccessMode.BinaryRecovery })
        {
            var service = new ProfileConfigurationService(Path.Combine(root, "profile"), "S-1-5-21-isolated", mode);
            Check.Pesto(() => service.WriteInstallationDefault(Path.Combine(root, "installation"), "entreprise.1", "pas-une-empreinte"),
                "config.isolated", "Isolement vérifié avant les arguments : " + mode);
            Check.Pesto(() => service.WriteInstallationDefault(@"\\unreachable\pack", "entreprise.1", new string('a', 64)),
                "config.isolated", "Isolement vérifié avant tout chemin : " + mode);
        }
        Check.False(Directory.Exists(root), "Aucun profil, verrou ni dossier d’installation sondé ou créé");
    }

    [Test] private static void InvalidExistingLocalDefaultBlocksWritingUntilRemoved()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var broken = PlaceDefault(b.Install, "{ cassé");
        Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.1", Sha(broken)), "package.defaults", InvalidMessage, "Défaut local invalide : le pack n’est pas valide");
        Check.True(Same(broken, DefaultBytes(b.Install)), "Fichier invalide jamais écrasé");
        Check.False(Directory.Exists(Path.Combine(author.ConfigurationRoot, "backups")), "Aucune sauvegarde");
        File.Delete(InstallationDefaults.PathIn(b.Install));
        Check.Equal("written", Harness.Str(author.WriteInstallationDefault(b.Install, "entreprise.1", ""), "status"), "Après suppression, écriture admise");
    }

    [Test] private static void WritingRemovesOnlyStaleWriterTemporaries()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var stale = PlaceDebris(b.Install); File.SetLastWriteTimeUtc(stale, DateTime.UtcNow.AddMinutes(-11));
        var recent = PlaceDebris(b.Install);
        Check.Equal("written", Harness.Str(author.WriteInstallationDefault(b.Install, "entreprise.1", ""), "status"), "Écriture malgré des débris");
        Check.False(File.Exists(stale), "Débris de plus de 10 minutes supprimé");
        Check.True(File.Exists(recent), "Débris récent conservé (écriture concurrente possible)");
        Check.Equal(2, DefaultsEntries(b.Install).Length, "Seuls le défaut et le débris récent restent");
        Check.Equal(FingerprintOf(), UpdatePackage.Validate(b.Install).LocalConfigurationFingerprint, "Pack valide avec débris récent");
    }

    [Test] private static void WritingRequiresAValidProfileConfigurationAndWritesNothingOtherwise()
    {
        using var b = new Bench();
        var refused = false;
        try { b.Profile("none", null).WriteInstallationDefault(b.Install, "entreprise.1", ""); }
        catch (Exception) { refused = true; }
        Check.True(refused, "Profil sans configuration : refus");
        Check.Pesto(() => b.Profile("broken", "{\"CONF\":").WriteInstallationDefault(b.Install, "entreprise.1", ""), "config.invalid", "Profil invalide : refus");
        Check.Pesto(() => b.Profile("author").WriteInstallationDefault(b.Install, "version invalide !", ""), "config.invalid", "Version invalide : refus");
        Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Rien n’est écrit dans l’installation");
    }

    [Test] private static void WrittenDefaultIsRememberedForItsAuthorAndOfferedToOtherProfiles()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var foreign = Path.Combine(b.Root, "foreign.json"); File.WriteAllText(foreign, BundleText("autre.1", OtherConfiguration));
        Check.True(Harness.Bool(author.Initialize(foreign), "requiresDecision"), "Décision en attente avant l’écriture");
        var configuration = File.ReadAllBytes(author.ConfigurationPath);
        var written = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var status = author.Status();
        Check.False(Harness.Bool(status, "requiresDecision"), "La décision en attente de l’auteur est levée");
        Check.Null(status["pendingDistribution"], "Aucune distribution en attente");
        Check.True(configuration.SequenceEqual(File.ReadAllBytes(author.ConfigurationPath)), "Configuration de l’auteur inchangée");
        var path = InstallationDefaults.PathIn(b.Install);
        // The author then edits their profile before any start: only the remembered authored decision keeps the question away.
        var edit = author.PreviewImport(OtherConfiguration);
        _ = author.ApplyImport(Harness.Str(edit, "planId"), true);
        Check.False(Harness.Bool(b.Profile("author", null).Initialize(path), "requiresDecision"), "Décision de l’auteur mémorisée, même après une modification de son profil et un redémarrage");
        Check.False(Harness.Bool(author.Initialize(path), "requiresDecision"), "L’auteur n’est jamais interrogé sur son propre défaut");
        author = b.Profile("author");
        var fresh = b.Profile("fresh", null);
        var imported = fresh.Initialize(path);
        Check.Equal("imported", Harness.Str(imported, "status"), "Un profil neuf importe le fichier écrit");
        Check.Equal(Harness.Str(written, "fingerprint"), ConfigurationDocument.Fingerprint(JsonNode.Parse(File.ReadAllText(fresh.ConfigurationPath))!), "Configuration importée exacte");
        var other = b.Profile("other", OtherConfiguration);
        var pending = other.Initialize(path);
        Check.True(Harness.Bool(pending, "requiresDecision"), "Un autre profil existant reçoit Remplacer/Conserver");
        var plan = pending["pendingDistribution"]!;
        Check.Equal("entreprise.1", Harness.Str(plan, "version"), "Version proposée");
        Check.Equal("kept", Harness.Str(other.DecideDistribution(Harness.Str(plan, "planId"), false, true), "status"), "Conserver");
        Check.False(Harness.Bool(b.Profile("other", null).Initialize(path), "requiresDecision"), "Conserver est mémorisé");
        var unchanged = author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(written, "sha256"));
        Check.Equal("unchanged", Harness.Str(unchanged, "status"), "Même configuration réécrite : unchanged");
        Check.False(Harness.Bool(b.Profile("other", null).Initialize(path), "requiresDecision"), "Version conservée : aucune nouvelle question");
        var third = b.Profile("third", OtherConfiguration);
        var offer = third.Initialize(path)["pendingDistribution"]!;
        Check.Equal("applied", Harness.Str(third.DecideDistribution(Harness.Str(offer, "planId"), true, true), "status"), "Remplacer");
        Check.Equal(Harness.Str(written, "fingerprint"), ConfigurationDocument.Fingerprint(JsonNode.Parse(File.ReadAllText(third.ConfigurationPath))!), "Remplacer applique le défaut écrit");
        // A second author whose profile already matches: unchanged also remembers the decision, for the published version.
        var coauthor = b.Profile("coauthor");
        Check.Equal("unchanged", Harness.Str(coauthor.WriteInstallationDefault(b.Install, "entreprise.3", Harness.Str(written, "sha256")), "status"), "Second auteur : unchanged");
        var coEdit = coauthor.PreviewImport(OtherConfiguration);
        _ = coauthor.ApplyImport(Harness.Str(coEdit, "planId"), true);
        Check.False(Harness.Bool(b.Profile("coauthor", null).Initialize(path), "requiresDecision"), "unchanged mémorise la décision de l’auteur pour la version publiée");
    }

    // ---------------------------------------------------------------- ApplicationServicesBackend et pont

    [Test] private static async Task BackendStatusAndSetDefaultUseTheInstallationWithoutAnyHostCall()
    {
        using var b = new Bench();
        var author = b.Profile("author");
        var host = new HostSpy();
        using var backend = new ApplicationServicesBackend(new BusinessSpy(), false, author, null, host, b.Install);
        var status = Harness.Call(backend, "configuration.status");
        Check.Equal("valid", Harness.Str(status, "configurationState"), "Statut du profil inchangé");
        var shown = status["installationDefault"]!;
        Check.Equal("missing", Harness.Str(shown, "state"), "installationDefault : missing");
        Check.Equal(DisplayPath, Harness.Str(shown, "path"), "installationDefault : chemin affiché");
        Check.True(shown["version"] is null && shown["fingerprint"] is null && shown["sha256"] is null, "installationDefault : valeurs nulles");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { version = "entreprise.1", expectedSha256 = "" }), "confirmation.required", "Sans confirmed");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { version = "entreprise.1", expectedSha256 = "", confirmed = false }), "confirmation.required", "confirmed faux");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { confirmed = true, destination = b.Root }), "invalid_arguments", "Plus aucune destination de pack");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { expectedSha256 = "ABCDEF", confirmed = true }), "invalid_arguments", "expectedSha256 mal formé");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { expectedSha256 = new string('a', 65), confirmed = true }), "invalid_arguments", "expectedSha256 trop long");
        Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Aucune écriture après les refus");
        var written = Harness.Call(backend, "configuration.setDefault", new { version = "entreprise.1", expectedSha256 = "", confirmed = true });
        Check.Equal("written", Harness.Str(written, "status"), "Écriture sur place");
        Check.Equal(b.Install, Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(Harness.Str(written, "file")))), "Écrit dans l’installation de l’application");
        shown = Harness.Call(backend, "configuration.status")["installationDefault"]!;
        Check.Equal("local", Harness.Str(shown, "state"), "installationDefault : local");
        Check.Equal("entreprise.1", Harness.Str(shown, "version"), "installationDefault : version");
        Check.Equal(Harness.Str(written, "fingerprint"), Harness.Str(shown, "fingerprint"), "installationDefault : empreinte");
        Check.Equal(Harness.Str(written, "sha256"), Harness.Str(shown, "sha256"), "installationDefault : SHA-256");
        Check.Pesto(() => Harness.Call(backend, "configuration.setDefault", new { version = "entreprise.2", expectedSha256 = "", confirmed = true }), "config.default_changed", "expectedSha256 transmis au moteur");
        var again = Harness.Call(backend, "configuration.setDefault", new { version = "entreprise.2", expectedSha256 = Harness.Str(shown, "sha256"), confirmed = true });
        Check.Equal("unchanged", Harness.Str(again, "status"), "Même configuration : unchanged");
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        var generated = Harness.Call(backend, "configuration.setDefault", new { expectedSha256 = Harness.Str(shown, "sha256"), confirmed = true });
        Check.Equal("written", Harness.Str(generated, "status"), "Version facultative");
        Check.True(Regex.IsMatch(Harness.Str(generated, "version"), "^[0-9]{8}-[0-9]{6}$"), "Version horodatée générée");
        var envelope = await Harness.DispatchAsync(backend, "set_default", "configuration.setDefault", new { expectedSha256 = Harness.Str(generated, "sha256"), confirmed = true });
        Check.Equal("result", envelope["kind"]!.GetValue<string>(), "Schéma du pont : version et expectedSha256 facultatifs");
        Check.Equal("unchanged", envelope["data"]!["status"]!.GetValue<string>(), "Résultat transmis par le pont");
        var forged = await Harness.DispatchAsync(backend, "forged_default", "configuration.setDefault", new { confirmed = true, destination = b.Root });
        Check.Equal("arguments.invalid", Harness.ErrorCode(forged), "Le pont refuse un champ destination");
        var unconfirmed = await Harness.DispatchAsync(backend, "unconfirmed_default", "configuration.setDefault", new { expectedSha256 = "" });
        Check.Equal("arguments.invalid", Harness.ErrorCode(unconfirmed), "Le pont exige confirmed");
        Check.Equal(0, host.Calls, "Aucun appel à l’hôte : plus de sélection de destination");
        PlaceDefault(b.Install, "{");
        Check.Equal("invalid", Harness.Str(Harness.Call(backend, "configuration.status")["installationDefault"]!, "state"), "Défaut illisible : invalid, sans exception");
    }

    // ---------------------------------------------------------------- UpdateTransaction et UpdateService

    [Test] private static async Task InstallationLocalDefaultIsCarriedIntoTheStageWithAMarker()
    {
        using var b = new Bench();
        var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
        PlaceDebris(b.Install);
        var next = UpdatePackage.Validate(b.Next);
        var request = await b.Prepare();
        var stage = Path.Combine(request.TransactionDirectory, "stage");
        Check.True(Same(mine, DefaultBytes(stage)), "Octets du défaut de l’installation recopiés dans le stage");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(stage)), "Aucun débris recopié");
        var staged = UpdatePackage.Validate(stage);
        Check.Equal(next.Fingerprint, staged.Fingerprint, "Le stage garde l’empreinte du pack choisi");
        Check.Equal(FingerprintOf(), staged.LocalConfigurationFingerprint, "Le stage porte le défaut local attendu");
        var marker = Marker(request.TransactionDirectory);
        Check.Equal(3, marker.Count, "Marqueur fermé : schemaVersion, sha256 et stageSha256");
        Check.Equal(1, marker["schemaVersion"]!.GetValue<int>(), "Marqueur schemaVersion 1");
        Check.Equal(Sha(mine), marker["sha256"]!.GetValue<string>(), "Marqueur : SHA-256 du défaut de l’installation");
        Check.Equal(Sha(mine), marker["stageSha256"]!.GetValue<string>(), "Marqueur : SHA-256 du défaut posé dans le stage");
        var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy);
        Check.Equal("completed", result.Status, "Installation terminée");
        Check.True(Same(mine, DefaultBytes(b.Install)), "Le défaut de l’installation suit la nouvelle version");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun débris dans la nouvelle version");
        var installed = UpdatePackage.Validate(b.Install);
        Check.Equal(next.Fingerprint, installed.Fingerprint, "Nouvelle version installée à l’identique");
        Check.Equal("2.0.15", installed.Version, "Version installée");
        Check.Null(DefaultBytes(b.Next), "Le dossier source n’est jamais modifié");
    }

    [Test] private static async Task NoDefaultOnEitherSideWritesANullMarkerAndCreatesNothing()
    {
        using var b = new Bench();
        var request = await b.Prepare();
        var marker = Marker(request.TransactionDirectory);
        Check.True(marker.ContainsKey("sha256") && marker["sha256"] is null, "Marqueur sha256 null");
        Check.False(Directory.Exists(DefaultsDirectory(Path.Combine(request.TransactionDirectory, "stage"))), "Aucun dossier wad\\defaults dans le stage");
        Check.Equal("completed", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy)).Status, "Installation terminée");
        Check.False(Directory.Exists(DefaultsDirectory(b.Install)), "Aucun défaut créé par la mise à jour");
    }

    [Test] private static async Task SourceLocalDefaultIsAdoptedWhenTheInstallationHasNone()
    {
        using var b = new Bench();
        var theirs = PlaceDefault(b.Next, BundleText("diffusion.1"));
        var debris = PlaceDebris(b.Next);
        var next = UpdatePackage.Validate(b.Next);
        var request = await b.Prepare();
        Check.Null(Marker(request.TransactionDirectory)["sha256"], "Marqueur : l’installation n’avait aucun défaut");
        Check.Equal(Sha(theirs), Marker(request.TransactionDirectory)["stageSha256"]!.GetValue<string>(), "Marqueur : défaut de la source posé dans le stage");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(Path.Combine(request.TransactionDirectory, "stage"))), "Débris de la source retirés du stage");
        Check.Equal("completed", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy)).Status, "Installation terminée");
        Check.True(Same(theirs, DefaultBytes(b.Install)), "Défaut local du dossier source adopté");
        Check.Equal("configuration.json", string.Join(",", DefaultsEntries(b.Install)), "Aucun débris adopté");
        var installed = UpdatePackage.Validate(b.Install);
        Check.Equal(next.Fingerprint, installed.Fingerprint, "Empreinte du pack choisi");
        Check.Equal("diffusion.1", installed.LocalConfigurationVersion, "Version adoptée");
        Check.True(Same(theirs, DefaultBytes(b.Next)) && File.Exists(debris), "Dossier source intact");
    }

    [Test] private static async Task SameConfigurationKeepsTheInstallationBytesOrTheSealedSourceFile()
    {
        using (var b = new Bench())
        {
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var theirs = PlaceDefault(b.Next, BundleText("entreprise.2"));
            Check.Equal(InstallationDefaults.Inspect(b.Install).Fingerprint, InstallationDefaults.Inspect(b.Next).Fingerprint, "Même configuration, octets différents");
            await b.InstallNext();
            Check.True(Same(mine, DefaultBytes(b.Install)), "Les octets de l’installation remplacent le défaut local du pack choisi");
            Check.True(Same(theirs, DefaultBytes(b.Next)), "Dossier source intact");
        }
        using (var b = new Bench())
        {
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var sealedBytes = b.Seal(b.Next, LiveTestConfig.Valid, "entreprise.2");
            var next = UpdatePackage.Validate(b.Next);
            await b.InstallNext();
            var installed = UpdatePackage.Validate(b.Install);
            Check.Equal(next.Fingerprint, installed.Fingerprint, "Ancien pack personnalisé de même configuration installé à l’identique");
            Check.Equal("custom", installed.Distribution, "Distribution personnalisée conservée");
            Check.True(Same(sealedBytes, DefaultBytes(b.Install)), "Fichier scellé du pack choisi conservé");
            Check.Equal("sealed", InstallationDefaults.Inspect(b.Install).State, "Forme scellée");
            var rollback = await b.Rollback();
            Check.Equal("rolledBack", rollback.Status, "Retour arrière");
            Check.True(Same(mine, DefaultBytes(b.Install)), "Candidat scellé : la sauvegarde garde son défaut local");
            Check.Equal("official", UpdatePackage.Validate(b.Install).Distribution, "Version officielle rétablie");
        }
    }

    [Test] private static async Task DifferentDefaultsAreRefusedAtInspectPrepareAndCreateWithoutReplacement()
    {
        using (var b = new Bench())
        {
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var theirs = PlaceDefault(b.Next, BundleText("entreprise.1", OtherConfiguration));
            using var service = b.Service();
            Refused(() => service.InspectLocal(b.Next), "update.default_conflict", ConflictMessage, "Conflit refusé dès l’inspection");
            Check.True(Same(mine, DefaultBytes(b.Install)) && Same(theirs, DefaultBytes(b.Next)), "Aucun fichier remplacé à l’inspection");
        }
        using (var b = new Bench())
        {
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            b.Seal(b.Next, OtherConfiguration, "entreprise.2");
            using var service = b.Service();
            Refused(() => service.InspectLocal(b.Next), "update.default_conflict", ConflictMessage, "Ancien pack personnalisé d’une autre configuration refusé");
            Check.True(Same(mine, DefaultBytes(b.Install)), "Défaut de l’installation intact");
        }
        using (var b = new Bench())
        {
            var theirs = PlaceDefault(b.Next, BundleText("entreprise.1", OtherConfiguration));
            using var service = b.Service();
            var inspected = service.InspectLocal(b.Next);
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var error = await RefusedAsync(() => service.PrepareAsync(Harness.Str(inspected, "candidateId")), "update.default_conflict", "Conflit refusé à la préparation");
            Check.Equal(ConflictMessage, error.Message, "Message exact à la préparation");
            var prepared = Path.Combine(Directory.GetDirectories(Path.Combine(b.Root, "state", "workspaces")).Single(), "prepared");
            Check.Equal(0, Directory.Exists(prepared) ? Directory.GetDirectories(prepared).Length : 0, "Aucune copie préparée conservée");
            Check.True(Same(mine, DefaultBytes(b.Install)) && Same(theirs, DefaultBytes(b.Next)), "Aucun fichier remplacé à la préparation");
        }
        using (var b = new Bench())
        {
            var theirs = PlaceDefault(b.Next, BundleText("entreprise.1", OtherConfiguration));
            using var service = b.Service();
            var prepared = await service.PrepareAsync(Harness.Str(service.InspectLocal(b.Next), "candidateId"));
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            Refused(() => service.RequestInstall(Harness.Str(prepared, "preparedId"), true), "update.default_conflict", ConflictMessage, "Conflit refusé à la création de la transaction");
            Check.Equal(0, UpdateTransaction.List(b.Install).Count, "Aucune transaction conservée");
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Installation intacte");
            Check.True(Same(mine, DefaultBytes(b.Install)) && Same(theirs, DefaultBytes(b.Next)), "Aucun fichier remplacé à la création");
            Check.Equal("2.0.14", UpdatePackage.Validate(b.Install).Version, "Aucune version installée");
        }
    }

    [Test] private static async Task LegacySealedInstallationDefaultBecomesLocalAndItsSealedBackupIsNeverTouched()
    {
        using var b = new Bench();
        var sealedBytes = b.Seal(b.Install, LiveTestConfig.Valid, "entreprise.1");
        var original = UpdatePackage.Validate(b.Install).Fingerprint;
        var request = await b.Prepare();
        Check.Equal(Sha(sealedBytes), Marker(request.TransactionDirectory)["sha256"]!.GetValue<string>(), "Marqueur : SHA-256 du fichier scellé");
        Check.Equal("completed", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy)).Status, "Installation terminée");
        var installed = UpdatePackage.Validate(b.Install);
        Check.Equal("candidate", installed.Distribution, "Pack non personnalisé installé");
        Check.Null(installed.ConfigurationFingerprint, "Rien de scellé dans la nouvelle version");
        Check.Equal(FingerprintOf(), installed.LocalConfigurationFingerprint, "Défaut recopié comme défaut local");
        Check.Equal("entreprise.1", installed.LocalConfigurationVersion, "Version recopiée");
        Check.True(Same(sealedBytes, DefaultBytes(b.Install)), "Octets du fichier scellé recopiés");
        Check.Equal("local", InstallationDefaults.Inspect(b.Install).State, "Forme locale");
        Check.False(Sums(b.Install).Contains("wad/defaults", StringComparison.OrdinalIgnoreCase), "Hors de l’inventaire de la nouvelle version");
        PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration));
        Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière");
        Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack personnalisé rétabli à l’identique");
        Check.True(Same(sealedBytes, DefaultBytes(b.Install)), "La sauvegarde scellée n’est jamais touchée");
        Check.Equal("sealed", InstallationDefaults.Inspect(b.Install).State, "Forme scellée rétablie");
    }

    [Test] private static async Task DefaultChangedAfterPreparationCancelsBeforeAnyMove()
    {
        foreach (var change in new[] { "modifié", "nouvelle version", "supprimé", "ajouté" })
        {
            using var b = new Bench();
            var prepared = change == "ajouté" ? null : PlaceDefault(b.Install, BundleText("entreprise.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            var request = await b.Prepare();
            byte[]? concurrent = change switch
            {
                "modifié" => PlaceDefault(b.Install, BundleText("entreprise.1", OtherConfiguration)),
                "nouvelle version" => PlaceDefault(b.Install, BundleText("entreprise.9")),
                "ajouté" => PlaceDefault(b.Install, BundleText("entreprise.1")),
                _ => null
            };
            if (change == "supprimé") File.Delete(InstallationDefaults.PathIn(b.Install));
            var result = await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy);
            Check.Equal("cancelled", result.Status, "Transaction annulée : défaut " + change);
            var record = Record(request.TransactionDirectory);
            Check.Equal("cancelled", record["status"]!.GetValue<string>(), "Journal annulé : " + change);
            Check.Equal("update.changed", record["failure"]!.GetValue<string>(), "Cause update.changed : " + change);
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Installation intacte : " + change);
            Check.Equal("2.0.14", UpdatePackage.Validate(b.Install).Version, "Aucune version installée : " + change);
            Check.True(Same(concurrent, DefaultBytes(b.Install)), "Changement concurrent conservé : " + change);
            Check.False(Directory.Exists(Path.Combine(request.TransactionDirectory, "backup")), "Aucune sauvegarde déplacée : " + change);
            Check.False(Directory.Exists(Path.Combine(request.TransactionDirectory, "failed-candidate")), "Aucun candidat déplacé : " + change);
            Check.True(Directory.Exists(Path.Combine(request.TransactionDirectory, "stage")), "Stage laissé en place : " + change);
            Check.True(prepared is null || Same(prepared, DefaultBytes(Path.Combine(request.TransactionDirectory, "stage"))), "Stage intact : " + change);
        }
    }

    [Test] private static async Task RollbackKeepsTheLatestLocalDefaultOrItsDeliberateDeletion()
    {
        using (var b = new Bench())
        {
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            await b.InstallNext();
            var latest = PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration));
            UpdateInstallRequest rollback;
            using (var service = b.Service()) rollback = service.RequestRollback(true);
            Check.False(Directory.Exists(Path.Combine(rollback.TransactionDirectory, "defaults-set-aside")), "Programme 2.0.14 : rien mis de côté");
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy)).Status, "Retour arrière");
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack rétabli");
            Check.Equal("2.0.14", UpdatePackage.Validate(b.Install).Version, "Ancienne version");
            Check.True(Same(latest, DefaultBytes(b.Install)), "Le dernier défaut local, modifié après l’installation, est conservé");
            Check.True(Same(latest, DefaultBytes(Path.Combine(rollback.TransactionDirectory, "failed-candidate"))), "Le candidat écarté garde le même défaut");
            Check.Equal(0, Directory.GetFiles(rollback.TransactionDirectory, "defaults-rollback.*").Length, "Aucun temporaire de recopie laissé");
        }
        using (var b = new Bench())
        {
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            await b.InstallNext();
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière sans modification");
            Check.True(Same(mine, DefaultBytes(b.Install)), "Défaut inchangé conservé");
        }
        using (var b = new Bench())
        {
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            await b.InstallNext();
            File.Delete(InstallationDefaults.PathIn(b.Install));
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière après suppression");
            Check.Null(DefaultBytes(b.Install), "La suppression volontaire est conservée");
            Check.Equal("missing", InstallationDefaults.Inspect(b.Install).State, "Aucun défaut rétabli");
        }
        using (var b = new Bench())
        {
            await b.InstallNext();
            var added = PlaceDefault(b.Install, BundleText("entreprise.1"));
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière après ajout");
            Check.True(Same(added, DefaultBytes(b.Install)), "Le défaut défini après l’installation est conservé");
            Check.Equal("official", UpdatePackage.Validate(b.Install).Distribution, "Pack officiel rétabli, toujours officiel");
        }
    }

    [Test] private static async Task AFailedCarryDuringRollbackLeavesTheInstallationInPlaceAndResumable()
    {
        using var b = new Bench();
        PlaceDefault(b.Install, BundleText("entreprise.1"));
        var original = UpdatePackage.Validate(b.Install).Fingerprint;
        await b.InstallNext();
        var latest = PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration));
        UpdateInstallRequest rollback;
        using (var service = b.Service()) rollback = service.RequestRollback(true);
        var restoredDefaults = DefaultsDirectory(Path.Combine(rollback.TransactionDirectory, "backup"));
        if (OperatingSystem.IsWindows())
        {
            // A read-only attribute, kept by File.Copy, never blocks the carry (MoveFileEx refuses a read-only target).
            var target = InstallationDefaults.PathIn(Path.Combine(rollback.TransactionDirectory, "backup"));
            File.SetAttributes(target, File.GetAttributes(target) | FileAttributes.ReadOnly);
            File.SetAttributes(InstallationDefaults.PathIn(b.Install), File.GetAttributes(InstallationDefaults.PathIn(b.Install)) | FileAttributes.ReadOnly);
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy)).Status, "Attribut lecture seule : retour terminé");
            Check.True(Same(latest, DefaultBytes(b.Install)), "Attribut lecture seule : dernier défaut conservé");
            var left = InstallationDefaults.PathIn(Path.Combine(rollback.TransactionDirectory, "failed-candidate"));
            if (File.Exists(left)) File.SetAttributes(left, FileAttributes.Normal); // Le nettoyage du banc supprime ce dossier.
            return;
        }
        File.SetUnixFileMode(restoredDefaults, ReadOnly);
        try
        {
            if (CanCreate(restoredDefaults)) return; // Utilisateur root : aucun refus de droits simulable.
            var refused = false;
            try { await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { refused = true; }
            Check.True(refused, "Recopie refusée");
            Check.True(Directory.Exists(b.Install), "L’installation reste en place après le refus");
            Check.Equal("2.0.15", UpdatePackage.Validate(b.Install).Version, "Le candidat reste installé et démarrable");
            Check.True(Same(latest, DefaultBytes(b.Install)), "Le dernier défaut reste dans l’installation");
            Check.False(Directory.Exists(Path.Combine(rollback.TransactionDirectory, "failed-candidate")), "Rien n’a été déplacé");
        }
        finally { File.SetUnixFileMode(restoredDefaults, Writable); }
        var recovery = UpdateTransaction.RequestRollback(rollback.TransactionDirectory, true);
        Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, b.Healthy)).Status, "Reprise une fois la cause levée");
        Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack rétabli");
        Check.True(Same(latest, DefaultBytes(b.Install)), "Dernier défaut conservé après la reprise");
    }

    [Test] private static async Task DefaultsBroughtByTheUpdateLeaveWithItOnRollback()
    {
        // Failed installation: the default the source brought never reaches the restored old version.
        using (var b = new Bench())
        {
            PlaceDefault(b.Next, BundleText("diffusion.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            var request = await b.Prepare();
            Func<string, string, string, CancellationToken, Task<bool>> candidateFails = (root, path, nonce, token)
                => UpdatePackage.Validate(root).Version == "2.0.15" ? Task.FromResult(false) : b.Healthy(root, path, nonce, token);
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, candidateFails)).Status, "Installation refusée puis rétablie");
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack rétabli");
            Check.Null(DefaultBytes(b.Install), "Le défaut de la source n’entre pas dans l’ancienne version");
        }
        // Completed installation, then rollback: unchanged since the transaction, it leaves with the update.
        using (var b = new Bench())
        {
            PlaceDefault(b.Next, BundleText("diffusion.1"));
            await b.InstallNext();
            Check.Equal("local", InstallationDefaults.Inspect(b.Install).State, "Défaut de la source adopté");
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière");
            Check.Null(DefaultBytes(b.Install), "Défaut apporté par la mise à jour, inchangé : retiré avec elle");
        }
        // Changed after the installation: the latest state wins.
        using (var b = new Bench())
        {
            PlaceDefault(b.Next, BundleText("diffusion.1"));
            await b.InstallNext();
            var mine = PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration));
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière");
            Check.True(Same(mine, DefaultBytes(b.Install)), "Défaut modifié après l’installation : conservé");
        }
    }

    [Test] private static async Task ADefaultChangedInThePreparedCopyIsRefusedBeforeInstallation()
    {
        foreach (var sourceHasDefault in new[] { false, true })
        {
            var label = sourceHasDefault ? "défaut de la source remplacé" : "défaut ajouté";
            using var b = new Bench();
            if (sourceHasDefault) PlaceDefault(b.Next, BundleText("diffusion.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            using var service = b.Service();
            var prepared = await service.PrepareAsync(Harness.Str(service.InspectLocal(b.Next), "candidateId"));
            var copy = Directory.GetDirectories(Path.Combine(b.Root, "state"), "package", SearchOption.AllDirectories).Single();
            PlaceDefault(copy, BundleText(sourceHasDefault ? "diffusion.2" : "diffusion.1", sourceHasDefault ? OtherConfiguration : null));
            Check.Pesto(() => service.RequestInstall(Harness.Str(prepared, "preparedId"), true), "update.changed", "Copie préparée modifiée : " + label);
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Installation intacte : " + label);
            Check.Equal(0, UpdateTransaction.List(b.Install).Count, "Aucune transaction créée : " + label);
        }
    }

    [Test] private static void InitializeRefusesAnInvalidInstallationDefaultWithTheValidatorMessage()
    {
        using var b = new Bench();
        PlaceDefault(b.Install, "{\"format\":\"pas une configuration\"}");
        var profile = b.Profile("reader");
        Refused(() => profile.Initialize(InstallationDefaults.PathIn(b.Install)), "package.defaults", InstallationDefaults.InvalidMessage,
            "Démarrage sans validation préalable (--settings, élevé) : même message que le validateur");
    }

    [Test] private static void WritingOverAPendingProposalClearsItEvenWhenTheDecisionCannotBeRecorded()
    {
        if (OperatingSystem.IsWindows()) return; // Les droits NTFS sont qualifiés sur Windows.
        using var b = new Bench();
        var theirs = PlaceDefault(b.Install, BundleText("diffusion.1", OtherConfiguration));
        var author = b.Profile("author");
        _ = author.Initialize(InstallationDefaults.PathIn(b.Install));
        Check.True(Harness.Bool(author.Status(), "requiresDecision"), "Proposition du défaut existant en attente");
        Directory.CreateDirectory(Path.Combine(author.ConfigurationRoot, "backups"));
        File.SetUnixFileMode(author.ConfigurationRoot, ReadOnly);
        try
        {
            if (CanCreate(author.ConfigurationRoot)) return; // Utilisateur root.
            var written = author.WriteInstallationDefault(b.Install, "entreprise.1", Sha(theirs));
            Check.Equal("written", Harness.Str(written, "status"), "Défaut écrit");
            Check.False(Harness.Bool(written, "decisionSaved"), "Décision non mémorisée");
            Check.False(Harness.Bool(author.Status(), "requiresDecision"), "La proposition du défaut remplacé n’est plus en attente");
        }
        finally { File.SetUnixFileMode(author.ConfigurationRoot, Writable); }
    }

    [Test] private static void AReadOnlyDefaultFileIsRefusedWithItsOwnAdvice()
    {
        if (!OperatingSystem.IsWindows()) return; // L’attribut lecture seule n’empêche un remplacement que sous Windows.
        using var b = new Bench();
        var author = b.Profile("author");
        var first = author.WriteInstallationDefault(b.Install, "entreprise.1", "");
        var file = InstallationDefaults.PathIn(b.Install);
        var bytes = File.ReadAllBytes(file);
        File.WriteAllText(author.ConfigurationPath, OtherConfiguration);
        File.SetAttributes(file, File.GetAttributes(file) | FileAttributes.ReadOnly);
        try
        {
            Refused(() => author.WriteInstallationDefault(b.Install, "entreprise.2", Harness.Str(first, "sha256")), "config.default_readonly",
                "Le fichier wad\\defaults\\configuration.json de cette installation est en lecture seule : retirez cet attribut (Propriétés du fichier) puis recommencez. Rien n’a été modifié.",
                "Fichier en lecture seule");
            Check.True(Same(bytes, File.ReadAllBytes(file)), "Ancien défaut intact");
            var backups = Path.Combine(author.ConfigurationRoot, "backups");
            Check.False(Directory.Exists(backups) && Directory.EnumerateFileSystemEntries(backups).Any(), "Aucune copie laissée dans le profil");
        }
        finally { File.SetAttributes(file, File.GetAttributes(file) & ~FileAttributes.ReadOnly); }
    }

    [Test] private static async Task StatusAnnouncesExactlyWhatAReturnDoesWithTheDefault()
    {
        async Task<string?> FateAfter(Action<Bench> before, Action<Bench> after, string current = "2.0.14", string next = "2.0.15")
        {
            using var b = new Bench(current, next);
            before(b);
            await b.InstallNext();
            after(b);
            string? announced;
            using (var service = b.Service()) announced = (string?)service.Status()["rollbackDefaults"];
            var installed = DefaultBytes(b.Install);
            var restored = DefaultBytes(Path.Combine(UpdateTransaction.List(b.Install).First(t => t.Status == "completed").TransactionDirectory, "backup"));
            Check.Equal("rolledBack", (await b.Rollback()).Status, "Retour arrière");
            var result = DefaultBytes(b.Install);
            // The announcement matches what the engine then does.
            switch (announced)
            {
                case "kept": Check.True(Same(installed, result), "kept : dernier défaut conservé"); break;
                case "withdrawn": Check.True(Same(restored, result), "withdrawn : état d’avant la mise à jour"); break;
                case "deleted": Check.Null(result, "deleted : suppression conservée"); break;
                case "setAside": Check.Null(result, "setAside : aucun défaut devant l’ancienne version"); break;
                case null: Check.True(Same(restored, result), "rien d’annoncé : la sauvegarde est rétablie telle quelle"); break;
            }
            return announced;
        }
        Check.Equal("kept", await FateAfter(b => PlaceDefault(b.Install, BundleText("entreprise.1")), _ => { }), "Défaut de l’installation inchangé");
        Check.Equal("kept", await FateAfter(b => PlaceDefault(b.Install, BundleText("entreprise.1")),
            b => PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration))), "Défaut modifié après l’installation");
        Check.Equal("withdrawn", await FateAfter(b => PlaceDefault(b.Next, BundleText("diffusion.1")), _ => { }), "Défaut apporté par la mise à jour, inchangé");
        Check.Equal("deleted", await FateAfter(b => PlaceDefault(b.Install, BundleText("entreprise.1")),
            b => File.Delete(InstallationDefaults.PathIn(b.Install))), "Défaut supprimé après l’installation");
        Check.Null(await FateAfter(_ => { }, _ => { }), "Aucun défaut d’un côté ni de l’autre");
        Check.Equal("setAside", await FateAfter(_ => { }, b => PlaceDefault(b.Install, BundleText("entreprise.1")), "2.0.13", "2.0.14"),
            "Retour vers un programme antérieur à 2.0.14");
    }

    [Test] private static async Task InspectionAndPreparationAnnounceWhatInstallingDoesWithTheDefault()
    {
        foreach (var (installation, source, expected) in new[] { (true, false, "kept"), (false, true, "adopted"), (false, false, (string?)null), (true, true, "kept") })
        {
            using var b = new Bench();
            if (installation) PlaceDefault(b.Install, BundleText("entreprise.1"));
            if (source) PlaceDefault(b.Next, BundleText("entreprise.1"));
            using var service = b.Service();
            var inspected = service.InspectLocal(b.Next);
            Check.Equal(expected, (string?)inspected["installDefaults"], $"Inspection ({installation}, {source})");
            var prepared = await service.PrepareAsync(Harness.Str(inspected, "candidateId"));
            Check.Equal(expected, (string?)prepared["installDefaults"], $"Préparation ({installation}, {source})");
        }
        using var s = new Bench();
        s.Seal(s.Next, LiveTestConfig.Valid, "entreprise.1");
        using (var service = s.Service()) Check.Equal("adopted", (string?)service.InspectLocal(s.Next)["installDefaults"], "Ancien pack personnalisé : sa configuration est adoptée");
    }

    [Test] private static async Task RollbackResumesCorrectlyAtEveryBoundaryIncludingDefaultsPreserved()
    {
        foreach (var deleted in new[] { false, true })
        foreach (var boundary in new[] { "rollingBack", "defaultsPreserved", "failedCandidateMoved", "backupRestored", "restored" })
        {
            var label = boundary + (deleted ? " (suppression)" : " (modification)");
            using var b = new Bench();
            PlaceDefault(b.Install, BundleText("entreprise.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            await b.InstallNext();
            byte[]? latest = null;
            if (deleted) File.Delete(InstallationDefaults.PathIn(b.Install));
            else latest = PlaceDefault(b.Install, BundleText("entreprise.2", OtherConfiguration));
            UpdateInstallRequest rollback;
            using (var service = b.Service()) rollback = service.RequestRollback(true);
            var reached = false;
            try
            {
                await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy,
                    checkpoint: point => { if (point == boundary) { reached = true; throw new UpdateInterruptionException(); } });
                throw new TestFailureException("interruption non injectée à " + label);
            }
            catch (UpdateInterruptionException) { }
            Check.True(reached, "Point de reprise atteint : " + label);
            var recovery = UpdateTransaction.RequestRollback(rollback.TransactionDirectory, true);
            var result = await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, b.Healthy);
            Check.Equal("rolledBack", result.Status, "Reprise du retour arrière : " + label);
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack rétabli : " + label);
            Check.True(Same(latest, DefaultBytes(b.Install)), "Dernier état du défaut conservé : " + label);
            Check.Equal(0, Directory.GetFiles(rollback.TransactionDirectory, "defaults-rollback.*").Length, "Aucun temporaire de recopie : " + label);
        }
    }

    [Test] private static async Task ReplacementInterruptionsKeepTheInstallationDefault()
    {
        foreach (var boundary in new[] { "backingUp", "backupMoved", "backedUp", "installing", "candidateMoved", "installed", "checking" })
        {
            using var b = new Bench();
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            var request = await b.Prepare();
            try
            {
                await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy, checkpoint: point => { if (point == boundary) throw new UpdateInterruptionException(); });
                throw new TestFailureException("interruption non injectée à " + boundary);
            }
            catch (UpdateInterruptionException) { }
            var recovery = UpdateTransaction.RequestRollback(request.TransactionDirectory, true);
            Check.False(Directory.Exists(Path.Combine(request.TransactionDirectory, "defaults-set-aside")), "Programme 2.0.14 : rien mis de côté à " + boundary);
            var result = await UpdateTransaction.ExecuteCoreAsync(recovery.TransactionDirectory, b.Healthy);
            Check.True(result.Status is "rolledBack" or "cancelled", "Reprise à " + boundary + " : " + result.Status);
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Ancien pack relu à " + boundary);
            Check.True(Same(mine, DefaultBytes(b.Install)), "Défaut de l’installation intact à " + boundary);
        }
    }

    [Test] private static async Task RollbackToAVersionBeforeLocalDefaultsSetsThemAsideInTheTransaction()
    {
        using (var b = new Bench("2.0.13", "2.0.14"))
        {
            await b.InstallNext();
            var mine = PlaceDefault(b.Install, BundleText("entreprise.1"));
            var debris = PlaceDebris(b.Install);
            var debrisBytes = File.ReadAllBytes(debris);
            UpdateInstallRequest rollback;
            using (var service = b.Service())
            {
                var status = service.Status();
                Check.Equal("2.0.13", Harness.Str(status, "rollbackVersion"), "updates.status : version rétablie");
                var local = status["localConfiguration"]!;
                Check.Equal("local", Harness.Str(local, "state"), "updates.status : défaut local signalé");
                Check.Equal(DisplayPath, Harness.Str(local, "path"), "updates.status : chemin");
                Check.Equal("entreprise.1", Harness.Str(local, "version"), "updates.status : version du défaut");
                Check.Equal(Sha(mine), Harness.Str(local, "sha256"), "updates.status : SHA-256 du défaut");
                rollback = service.RequestRollback(true);
            }
            var aside = Path.Combine(rollback.TransactionDirectory, "defaults-set-aside", "installation");
            Check.True(Same(mine, File.ReadAllBytes(Path.Combine(aside, "configuration.json"))), "Défaut local mis de côté à l’identique");
            Check.True(debrisBytes.SequenceEqual(File.ReadAllBytes(Path.Combine(aside, Path.GetFileName(debris)))), "Débris mis de côté, jamais supprimé");
            Check.Equal(0, DefaultsEntries(b.Install).Length, "Plus rien sous wad\\defaults pour le programme 2.0.13");
            Check.False(Directory.Exists(Path.Combine(rollback.TransactionDirectory, "defaults-set-aside", "failed-candidate")), "Aucun candidat écarté à traiter");
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy)).Status, "Retour arrière");
            Check.Equal("2.0.13", UpdatePackage.Validate(b.Install).Version, "Version 2.0.13 rétablie");
            Check.Null(DefaultBytes(b.Install), "Aucun défaut local devant le programme 2.0.13");
            Check.True(Same(mine, File.ReadAllBytes(Path.Combine(aside, "configuration.json"))), "Défaut mis de côté toujours conservé");
        }
        using (var b = new Bench("2.0.13", "2.0.14"))
        {
            var sealedBytes = b.Seal(b.Next, LiveTestConfig.Valid, "entreprise.1");
            await b.InstallNext();
            Check.Equal("sealed", InstallationDefaults.Inspect(b.Install).State, "Ancien pack personnalisé installé");
            var debris = PlaceDebris(b.Install);
            UpdateInstallRequest rollback;
            using (var service = b.Service()) rollback = service.RequestRollback(true);
            var aside = Path.Combine(rollback.TransactionDirectory, "defaults-set-aside", "installation");
            Check.True(File.Exists(Path.Combine(aside, Path.GetFileName(debris))), "Débris mis de côté à côté d’un fichier scellé");
            Check.False(File.Exists(Path.Combine(aside, "configuration.json")), "Un fichier scellé, connu de 2.0.13, n’est pas mis de côté");
            Check.True(Same(sealedBytes, DefaultBytes(b.Install)), "Fichier scellé laissé en place");
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(rollback.TransactionDirectory, b.Healthy)).Status, "Retour arrière");
            Check.Equal("2.0.13", UpdatePackage.Validate(b.Install).Version, "Version 2.0.13 rétablie");
        }
        using (var b = new Bench("2.0.13", "2.0.14"))
        {
            var original = UpdatePackage.Validate(b.Install).Fingerprint;
            var request = await b.Prepare();
            try
            {
                await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, Bench.Unhealthy,
                    checkpoint: point => { if (point == "failedCandidateMoved") throw new UpdateInterruptionException(); });
                throw new TestFailureException("interruption non injectée");
            }
            catch (UpdateInterruptionException) { }
            var failed = Path.Combine(request.TransactionDirectory, "failed-candidate");
            var planted = PlaceDefault(failed, BundleText("entreprise.1"));
            var debris = PlaceDebris(failed);
            using (var service = b.Service()) _ = service.RequestRecovery(true);
            var aside = Path.Combine(request.TransactionDirectory, "defaults-set-aside", "failed-candidate");
            Check.True(Same(planted, File.ReadAllBytes(Path.Combine(aside, "configuration.json"))), "Défaut local du candidat écarté mis de côté");
            Check.True(File.Exists(Path.Combine(aside, Path.GetFileName(debris))), "Débris du candidat écarté mis de côté");
            Check.Equal(0, DefaultsEntries(failed).Length, "Candidat écarté sans défaut pour le programme 2.0.13");
            Check.Equal("rolledBack", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, b.Healthy)).Status, "Reprise terminée");
            Check.Equal(original, UpdatePackage.Validate(b.Install).Fingerprint, "Version 2.0.13 rétablie à l’identique");
            Check.Null(DefaultBytes(b.Install), "Aucun défaut rétabli");
        }
    }

    [Test] private static async Task StatusAndDescriptionsExposeLocalConfiguration()
    {
        using var b = new Bench();
        using (var service = b.Service())
        {
            var status = service.Status();
            Check.Null(status["rollbackVersion"], "Aucun retour disponible : rollbackVersion null");
            Check.Null(status["recoveryVersion"], "Aucune reprise : recoveryVersion null");
            var local = status["localConfiguration"]!;
            Check.Equal("missing", Harness.Str(local, "state"), "localConfiguration : missing");
            Check.Equal(DisplayPath, Harness.Str(local, "path"), "localConfiguration : chemin");
            var plain = service.InspectLocal(b.Next);
            Check.False(Harness.Bool(plain, "localConfiguration"), "Candidat sans défaut local");
            Check.False(Harness.Bool(plain, "configurationIncluded"), "Candidat non personnalisé");
        }
        var theirs = PlaceDefault(b.Next, BundleText("diffusion.1"));
        using (var service = b.Service())
        {
            var inspected = service.InspectLocal(b.Next);
            Check.True(Harness.Bool(inspected, "localConfiguration"), "Describe : défaut local inclus");
            Check.False(Harness.Bool(inspected, "configurationIncluded"), "Un défaut local n’est pas un pack personnalisé");
            Check.Equal("candidate", Harness.Str(inspected, "distribution"), "Distribution inchangée");
            var prepared = await service.PrepareAsync(Harness.Str(inspected, "candidateId"));
            Check.True(Harness.Bool(prepared, "localConfiguration"), "Préparation : défaut local inclus");
            Check.Equal(Harness.Str(inspected, "fingerprint"), Harness.Str(prepared, "fingerprint"), "Même empreinte de pack");
        }
        await b.InstallNext();
        using (var service = b.Service())
        {
            var status = service.Status();
            Check.True(Harness.Bool(status, "canRollback"), "Retour disponible");
            Check.Equal("2.0.14", Harness.Str(status, "rollbackVersion"), "rollbackVersion : version rétablie");
            var local = status["localConfiguration"]!;
            Check.Equal("local", Harness.Str(local, "state"), "localConfiguration : local");
            Check.Equal("diffusion.1", Harness.Str(local, "version"), "localConfiguration : version");
            Check.Equal(FingerprintOf(), Harness.Str(local, "fingerprint"), "localConfiguration : empreinte");
            Check.Equal(Sha(theirs), Harness.Str(local, "sha256"), "localConfiguration : SHA-256");
        }
        using var s = new Bench();
        s.Seal(s.Next, LiveTestConfig.Valid, "entreprise.1");
        using (var service = s.Service())
        {
            var described = service.InspectLocal(s.Next);
            Check.True(Harness.Bool(described, "configurationIncluded"), "Ancien pack personnalisé : configuration incluse");
            Check.False(Harness.Bool(described, "localConfiguration"), "Ancien pack personnalisé : pas de défaut local");
            Check.Equal("custom", Harness.Str(described, "distribution"), "Distribution personnalisée");
        }
    }

    [Test] private static async Task PreparationIsBoundToTheInspectedLocalDefaultOfTheSource()
    {
        using var b = new Bench();
        using var service = b.Service();
        var candidate = Harness.Str(service.InspectLocal(b.Next), "candidateId");
        PlaceDefault(b.Next, BundleText("diffusion.1"));
        await RefusedAsync(() => service.PrepareAsync(candidate), "update.changed", "Défaut local ajouté à la source après l’inspection");
        var again = Harness.Str(service.InspectLocal(b.Next), "candidateId");
        var prepared = await service.PrepareAsync(again);
        Check.True(Harness.Bool(prepared, "localConfiguration"), "Nouvelle inspection : préparation admise");
        PlaceDefault(b.Next, BundleText("diffusion.2", OtherConfiguration));
        await RefusedAsync(() => service.PrepareAsync(again), "update.changed", "Défaut local de la source changé après l’inspection");
    }

    // ---------------------------------------------------------------- Outils

    private static string BundleText(string version = "2026.11.12", string? configuration = null)
        => ConfigurationDocument.Canonical(ConfigurationDocument.Export(configuration ?? LiveTestConfig.Valid, version));
    private static string FingerprintOf(string? configuration = null)
        => ConfigurationDocument.Export(configuration ?? LiveTestConfig.Valid, "empreinte")["fingerprint"]!.GetValue<string>();
    private static string Sha(byte[] bytes) => Convert.ToHexStringLower(SHA256.HashData(bytes));
    private static string SumsFile(string root) => Path.Combine(root, UpdatePackage.SumsPath);
    private static string Sums(string root) => File.ReadAllText(SumsFile(root));
    private static string DefaultsDirectory(string root) => Path.Combine(root, "wad", "defaults");
    private static byte[] PlaceDefault(string root, string text) => PlaceDefault(root, Encoding.UTF8.GetBytes(text));
    private static byte[] PlaceDefault(string root, byte[] bytes)
    {
        Directory.CreateDirectory(DefaultsDirectory(root));
        File.WriteAllBytes(InstallationDefaults.PathIn(root), bytes);
        return bytes;
    }
    private static string PlaceDebris(string root, string? name = null, byte[]? bytes = null)
    {
        Directory.CreateDirectory(DefaultsDirectory(root));
        var path = Path.Combine(DefaultsDirectory(root), name ?? ".configuration-" + Guid.NewGuid().ToString("N") + ".tmp");
        File.WriteAllBytes(path, bytes ?? [0xff, 0xfe, 0x7b, 0x00, 0xc3]);
        return path;
    }
    private static string[] DefaultsEntries(string root) => Directory.Exists(DefaultsDirectory(root))
        ? Directory.GetFileSystemEntries(DefaultsDirectory(root)).Select(p => Path.GetFileName(p)).Order(StringComparer.Ordinal).ToArray() : [];
    private static byte[]? DefaultBytes(string root) => File.Exists(InstallationDefaults.PathIn(root)) ? File.ReadAllBytes(InstallationDefaults.PathIn(root)) : null;
    private static bool Same(byte[]? expected, byte[]? actual) => expected is null ? actual is null : actual is not null && expected.AsSpan().SequenceEqual(actual);
    private static JsonObject Record(string transaction) => JsonNode.Parse(File.ReadAllText(Path.Combine(transaction, "transaction.json")))!.AsObject();
    private static JsonObject Marker(string transaction) => JsonNode.Parse(File.ReadAllText(Path.Combine(transaction, "installation-default.json")))!.AsObject();
    private static void EditManifest(string root, Action<JsonObject> edit)
    {
        var path = Path.Combine(root, UpdatePackage.ManifestPath);
        var manifest = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        edit(manifest);
        File.WriteAllText(path, manifest.ToJsonString());
    }
    private static bool CanCreate(string directory)
    {
        var probe = Path.Combine(directory, ".probe-" + Guid.NewGuid().ToString("N"));
        try { File.WriteAllText(probe, ""); File.Delete(probe); return true; }
        catch (UnauthorizedAccessException) { return false; }
        catch (IOException) { return false; }
    }
    private static void Refused(Func<object?> action, string code, string message, string label)
        => Check.Equal(message, Check.Pesto(action, code, label).Message, label + " : message exact");
    private static void Refused(Func<object?> action, string[] codes, string label)
    {
        try { action(); }
        catch (PestoException error) { Check.True(codes.Contains(error.Code), label + " (code obtenu " + error.Code + ")"); return; }
        throw new TestFailureException(label + " (aucun refus)");
    }
    private static async Task<PestoException> RefusedAsync(Func<Task> action, string code, string label)
    {
        try { await action(); }
        catch (PestoException error) { Check.Equal(code, error.Code, label); return error; }
        throw new TestFailureException(label + " (aucun refus " + code + ")");
    }

    private static void MakePack(string root, string version, byte marker, string distribution)
    {
        Directory.CreateDirectory(Path.Combine(root, "wad/web"));
        var pe = new byte[256]; pe[0] = (byte)'M'; pe[1] = (byte)'Z'; BitConverter.GetBytes(0x80).CopyTo(pe, 0x3c);
        BitConverter.GetBytes(0x4550).CopyTo(pe, 0x80); BitConverter.GetBytes((ushort)0x8664).CopyTo(pe, 0x84);
        BitConverter.GetBytes((ushort)0x20b).CopyTo(pe, 0x98); pe[200] = marker;
        File.WriteAllBytes(Path.Combine(root, "Pesto.exe"), pe);
        ActiveDirectoryTestBundle.CopyToApplication(root);
        File.WriteAllText(Path.Combine(root, "wad/web/index.html"), "<h1>Fixture " + version + "</h1>");
        File.WriteAllText(Path.Combine(root, UpdatePackage.ManifestPath), JsonSerializer.Serialize(new { schemaVersion = 2, packName = "Pesto-v2-portable", version,
            channel = "PROD", entryPoint = "Pesto.exe", layout = "singlefile-wad", repository = "M4D135/pesto", webview2Runtime = "evergreen",
            distribution, official = distribution == "official" }));
        UpdatePackage.Rehash(root);
    }

    /// <summary>Installation et candidat fictifs sous le dossier temporaire ; versions choisies pour le programme qui exécute la transaction.</summary>
    private sealed class Bench : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "pesto-defaults-tests-" + Guid.NewGuid().ToString("N"));
        public string Install => Path.Combine(Root, "installed");
        public string Next => Path.Combine(Root, "candidate");

        public Bench(string current = "2.0.14", string next = "2.0.15", string distribution = "official")
        {
            MakePack(Install, current, 1, distribution);
            MakePack(Next, next, 2, "candidate");
        }

        /// <summary>Refabrique ce pack en ancien pack personnalisé scellé (format des boutons ≤ 2.0.13) et rend les octets scellés.</summary>
        public byte[] Seal(string pack, string configuration, string version)
        {
            var plain = Path.Combine(Root, "plain-" + Guid.NewGuid().ToString("N"));
            Directory.Move(pack, plain);
            _ = LegacyCustomPack.Build(plain, pack, ConfigurationDocument.Export(configuration, version), version);
            Directory.Delete(plain, true);
            return File.ReadAllBytes(InstallationDefaults.PathIn(pack));
        }

        public ProfileConfigurationService Profile(string name, string? configuration = LiveTestConfig.Valid, FixedClock? clock = null)
        {
            var root = Path.Combine(Root, "profiles", name);
            Directory.CreateDirectory(root);
            if (configuration is not null) File.WriteAllText(Path.Combine(root, "cfg.json"), configuration);
            return new(root, "S-1-5-21-" + name, ConfigurationAccessMode.Live, clock);
        }

        public UpdateService Service() => new(new(Install, Path.Combine(Root, "state"), "PROD", false));

        public async Task<UpdateInstallRequest> Prepare()
        {
            using var service = Service();
            var candidate = service.InspectLocal(Next)["candidateId"]!.GetValue<string>();
            var prepared = await service.PrepareAsync(candidate);
            return service.RequestInstall(prepared["preparedId"]!.GetValue<string>(), true);
        }

        public async Task InstallNext()
        {
            var request = await Prepare();
            Check.Equal("completed", (await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, Healthy)).Status, "Installation de la nouvelle version");
        }

        public async Task<UpdateTransactionResult> Rollback()
        {
            UpdateInstallRequest request;
            using (var service = Service()) request = service.RequestRollback(true);
            return await UpdateTransaction.ExecuteCoreAsync(request.TransactionDirectory, Healthy);
        }

        public Task<bool> Healthy(string root, string path, string nonce, CancellationToken cancellationToken)
        {
            var pack = UpdatePackage.Validate(root);
            File.WriteAllText(path, JsonSerializer.Serialize(new { schemaVersion = 1, transactionId = Path.GetFileName(Path.GetDirectoryName(path)), nonce,
                version = pack.Version, executableSha256 = UpdatePackage.Hash(Path.Combine(root, "Pesto.exe")), webViewReady = true, success = true }));
            return Task.FromResult(true);
        }

        public static Task<bool> Unhealthy(string root, string path, string nonce, CancellationToken cancellationToken) => Task.FromResult(false);

        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }

    private sealed class HostSpy : IPestoHostActions
    {
        public int Calls;
        public Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SaveExportAsync(string name, string text, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<object?> OpenDemoAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(null); }
        public Task<object?> ReconnectAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(null); }
        public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(null); }
    }

    private sealed class BusinessSpy : IPestoBackend
    {
        public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
            => Task.FromResult<object?>(new JsonObject { ["mode"] = "live" });
    }
}
