using Pesto.Core;

namespace Pesto.Engine;

/// <summary>One canonical config directory for the V1 installer root and direct wad/config-directory layouts.</summary>
public static class V1ConfigDirectory
{
    public static string? Resolve(string? root)
    {
        if (string.IsNullOrWhiteSpace(root)) return null;
        var absolute = Path.GetFullPath(root);
        if (File.Exists(Path.Combine(absolute, "cfg.json"))) return absolute;
        var wad = Path.Combine(absolute, "wad");
        if (File.Exists(Path.Combine(wad, "cfg.json"))) return wad;
        throw new PestoException("config.missing", "Aucun cfg.json trouvé dans le dossier choisi ni dans son sous-dossier wad. Choisissez l’installation V1 ou le dossier contenant sa configuration.");
    }
}
