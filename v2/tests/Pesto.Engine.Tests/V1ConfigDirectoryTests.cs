namespace Pesto.Engine.Tests;

internal sealed class V1ConfigDirectoryTests
{
    [Test]
    public void InstallerRootAndDirectWadFolderReadTheSameConfig()
    {
        var install = Path.Combine(Path.GetTempPath(), "pesto-layout-" + Guid.NewGuid().ToString("N"));
        var wad = Path.Combine(install, "wad");
        Directory.CreateDirectory(wad);
        File.WriteAllText(Path.Combine(wad, "cfg.json"), LiveTestConfig.Valid);
        Check.Equal(wad, V1ConfigDirectory.Resolve(install), "Racine installation résolue vers wad");
        Check.Equal(wad, V1ConfigDirectory.Resolve(wad), "Dossier cfg direct conservé");
        Check.Equal("example.local", Harness.Str(Harness.Call(Harness.Live(install), "settings.get"), "domain"), "Config réelle lue depuis la racine");
        Check.Equal("example.local", Harness.Str(Harness.Call(Harness.Live(wad), "settings.get"), "domain"), "Même config depuis wad");
    }

    [Test]
    public void DirectConfigWinsAndMissingConfigNeverInventsAPath()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.Valid);
        Directory.CreateDirectory(Path.Combine(root, "wad"));
        File.WriteAllText(Path.Combine(root, "wad", "cfg.json"), "{}");
        Check.Equal(root, V1ConfigDirectory.Resolve(root), "Le cfg explicite direct est prioritaire");
        Check.Pesto(() => V1ConfigDirectory.Resolve(Path.Combine(root, "missing")), "config.missing", "Chemin manquant refusé");
        Check.Null(V1ConfigDirectory.Resolve(null), "Aucune installation supposée");
    }
}
