using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>File-only fixtures: the real pinned payload is copied but never imported or executed.</summary>
internal static class ActiveDirectoryTestBundle
{
    public static string SourceDirectory()
    {
        for (DirectoryInfo? ancestor = new DirectoryInfo(AppContext.BaseDirectory); ancestor is not null; ancestor = ancestor.Parent)
            foreach (var candidate in new[]
            {
                Path.Combine(ancestor.FullName, "DEV", "wad"),
                Path.Combine(ancestor.FullName, ActiveDirectoryBundle.RelativeDirectory),
                Path.Combine(ancestor.FullName, "runtime", "activedirectory")
            })
                if (ActiveDirectoryBundle.Sha256.Keys.All(name => File.Exists(Path.Combine(candidate, name)))) return candidate;
        throw new TestFailureException("Les six fichiers Microsoft versionnés sont requis pour ce contrôle de fichiers ; aucun module factice ni téléchargement implicite.");
    }

    public static string CopyToApplication(string applicationRoot)
    {
        var directory = Path.Combine(applicationRoot, ActiveDirectoryBundle.RelativeDirectory);
        CopyToDirectory(directory);
        return directory;
    }

    public static void CopyToDirectory(string directory)
    {
        var source = SourceDirectory();
        foreach (var name in ActiveDirectoryBundle.Sha256.Keys)
        {
            var destination = Path.Combine(directory, name);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(Path.Combine(source, name), destination, overwrite: true);
        }
    }
}

internal sealed class ActiveDirectoryBundleTests
{
    [Test]
    public void ApplicationBundleWorksWithAFreshProfileAndPrecedesLegacyConfiguration()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-ad-module-" + Guid.NewGuid().ToString("N"));
        try
        {
            var application = Path.Combine(root, "application");
            var bundle = ActiveDirectoryTestBundle.CopyToApplication(application);
            var expected = Path.Combine(bundle, ActiveDirectoryBundle.ManifestName);
            var freshProfile = Path.Combine(root, "AppData", "Pesto", "profile");
            Check.Equal(expected, TrustedActiveDirectoryModule.Resolve(freshProfile, application)!, "Le module est disponible sans bundle ni configuration dans le profil neuf");
            Check.False(Directory.Exists(freshProfile), "Résoudre le module ne crée ni ne modifie le profil");
            Directory.CreateDirectory(freshProfile);
            File.WriteAllText(Path.Combine(freshProfile, "cfg.json"), "profile-sentinel");
            File.WriteAllText(Path.Combine(freshProfile, ActiveDirectoryBundle.ManifestName), "# unrelated legacy module");
            Check.Equal(expected, TrustedActiveDirectoryModule.Resolve(freshProfile, application)!, "Le bundle de l’exécutable reste prioritaire à l’ancien emplacement");
            Check.Equal("profile-sentinel", File.ReadAllText(Path.Combine(freshProfile, "cfg.json")), "La configuration n’est ni copiée ni lue comme dépendance exécutable");
            Check.Equal(6, Directory.GetFiles(bundle, "*", SearchOption.AllDirectories).Length, "Exactement les six fichiers Microsoft existants");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Test]
    public void EveryBundledFileIsPinnedAndMissingOrAlteredContentCannotFallBack()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-ad-integrity-" + Guid.NewGuid().ToString("N"));
        try
        {
            var application = Path.Combine(root, "application");
            var bundle = ActiveDirectoryTestBundle.CopyToApplication(application);
            var legacy = Path.Combine(root, "legacy"); ActiveDirectoryTestBundle.CopyToDirectory(legacy);
            File.WriteAllText(Path.Combine(legacy, "cfg.json"), LiveTestConfig.NoRandom);
            foreach (var name in ActiveDirectoryBundle.Sha256.Keys)
            {
                var path = Path.Combine(bundle, name);
                var original = File.ReadAllBytes(path);
                File.AppendAllText(path, "tampered");
                Check.Pesto(() => TrustedActiveDirectoryModule.Resolve(legacy, application), "directory.module_untrusted", "Altération refusée sans repli V1/système : " + name);
                File.Delete(path);
                Check.Pesto(() => TrustedActiveDirectoryModule.Resolve(legacy, application), "directory.module_untrusted", "Fichier manquant refusé sans repli V1/système : " + name);
                File.WriteAllBytes(path, original);
            }
            Check.Equal(Path.Combine(bundle, ActiveDirectoryBundle.ManifestName), TrustedActiveDirectoryModule.Resolve(legacy, application)!, "Le bundle original reste résoluble après restauration de la fixture");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
