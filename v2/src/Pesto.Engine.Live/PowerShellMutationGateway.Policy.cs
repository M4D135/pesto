namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationManagedPolicy
{
    private MutationPolicyRequirements ReadPolicyRequirements()
    {
        if (v1InstallationPath is null) throw new IOException("Configuration de politique absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json");
        var info = new FileInfo(path);
        if (!info.Exists || info.Length is < 1 or > 1048576 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Configuration de politique illisible ou liée.");
        return MutationPolicyGuard.ReadRequirements(File.ReadAllText(path));
    }

    private string? ConfiguredPolicyRefusal(MutationRequest request)
    {
        try
        {
            if (v1InstallationPath is null) return "Configuration de politique absente : aucune mutation.";
            var path = Path.Combine(v1InstallationPath, "cfg.json");
            var info = new FileInfo(path);
            if (!info.Exists || info.Length is < 1 or > 1048576 || (info.Attributes & FileAttributes.ReparsePoint) != 0)
                return "Configuration de politique illisible ou liée : aucune mutation.";
            var bytes = File.ReadAllBytes(path);
            if (MutationPolicyGuard.ConfigurationRefusal(bytes, request.ConfigurationSha256) is { } changed) return changed;
            using var stream = new MemoryStream(bytes);
            using var reader = new StreamReader(stream, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            var json = reader.ReadToEnd();
            return MutationPolicyGuard.Refusal(json, request, ReadManagedPolicy()) ?? AutomationAuthorityRefusal(request, bytes, json);
        }
        catch (Exception) { return "La politique de mutation ne peut pas être relue avant envoi : aucune commande lancée."; }
    }

    /// <summary>Windows holds this read handle without write/delete sharing across the complete confirmed mutation.
    /// Another window cannot atomically replace cfg.json while a later phase is about to create a lock or AD account.</summary>
    private FileStream PinConfirmedConfiguration(MutationRequest request) => PinConfirmedConfiguration(request.ConfigurationSha256);

    private FileStream PinConfirmedConfiguration(string? configurationSha256)
    {
        if (v1InstallationPath is null) throw new IOException("Configuration du plan absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json");
        RequireNoReparsePoint(path);
        var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            if (file.Length is < 1 or > 1048576) throw new IOException("Configuration du plan illisible.");
            var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
            if (MutationPolicyGuard.ConfigurationRefusal(bytes, configurationSha256) is { } changed) throw new IOException(changed);
            return file;
        }
        catch { file.Dispose(); throw; }
    }

    public MutationManagedPolicy ReadManagedPolicy() => WindowsManagedPolicyReader.Read();
}
