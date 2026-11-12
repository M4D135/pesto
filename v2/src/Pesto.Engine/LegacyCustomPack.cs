using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Builds a custom pack in the format produced by the button up to 2.0.13: complete copy, sealed
/// <c>wad/defaults/configuration.json</c>, manifest <c>distribution=custom</c> and recalculated inventory. The interface no
/// longer builds packs; qualification benches and tests use this to prove such packs stay valid and installable.
/// </summary>
public static class LegacyCustomPack
{
    public static UpdatePackageInfo Build(string sourcePack, string destination, JsonObject bundle, string version)
    {
        _ = ConfigurationDocument.ValidateBundle(bundle.ToJsonString());
        if (ConfigurationDocument.String(bundle, "version") != version)
            throw new PestoException("package.defaults", "La version de la configuration ne correspond pas au pack personnalisé demandé.");
        var sourceFingerprint = UpdatePackage.Validate(sourcePack).Fingerprint;
        destination = Path.GetFullPath(destination);
        var sourcePath = Path.GetFullPath(sourcePack).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if ((destination + Path.DirectorySeparatorChar).StartsWith(sourcePath, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new PestoException("package.destination", "Préparez le pack personnalisé dans un dossier extérieur au pack source.");
        if (Directory.Exists(destination) || File.Exists(destination)) throw new PestoException("package.destination", "Le dossier de destination existe déjà.");
        var stage = Path.Combine(Path.GetDirectoryName(destination)!, ".pesto-personnalisation-" + Guid.NewGuid().ToString("N"));
        try
        {
            UpdatePackage.CopyToNew(sourcePack, stage, sourceFingerprint);
            // A local default of the source is not part of its identity and never enters the sealed pack.
            foreach (var file in new[] { InstallationDefaults.PathIn(stage) }.Where(File.Exists)) File.Delete(file);
            InstallationDefaults.RemoveDebris(stage);
            var defaults = Path.Combine(stage, "wad", "defaults");
            Directory.CreateDirectory(defaults);
            File.WriteAllText(Path.Combine(defaults, "configuration.json"), ConfigurationDocument.Canonical(bundle));
            var manifestPath = Path.Combine(stage, "wad", "Pesto.package.json");
            var manifest = ConfigurationDocument.ParseObject(File.ReadAllText(manifestPath));
            manifest["distribution"] = "custom";
            manifest["official"] = false;
            manifest["configurationVersion"] = version;
            manifest["configurationFingerprint"] = bundle["fingerprint"]!.DeepClone();
            File.WriteAllText(manifestPath, manifest.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            UpdatePackage.Rehash(stage);
            _ = UpdatePackage.Validate(stage);
            Directory.Move(stage, destination);
        }
        finally { if (Directory.Exists(stage)) Directory.Delete(stage, recursive: true); }
        return UpdatePackage.Validate(destination);
    }
}
