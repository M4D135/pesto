using Microsoft.Win32;

namespace Pesto.Engine.Live;

/// <summary>One local-only, closed HKLM reader shared by interactive, CLI and offline-join admission.</summary>
public static class WindowsManagedPolicyReader
{
    public static MutationManagedPolicy Read()
    {
        if (!OperatingSystem.IsWindows()) return new();
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Policies\M4D\Pesto", writable: false);
            if (key is null) return new();
            var names = key.GetValueNames();
            var incident = false; var disableJoin = false; var disableOperations = false;
            int? maxBatch = null;
            foreach (var name in new[] { "IncidentMode", "DisableUnattendedJoin", "DisableUnattendedOperations", "MaxBatch" })
            {
                if (!names.Contains(name, StringComparer.Ordinal)) continue;
                if (key.GetValueKind(name) != RegistryValueKind.DWord
                    || key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) is not int number
                    || (name == "MaxBatch" ? number is < 1 or > 200 : number is not (0 or 1)))
                    return new(Refusal: "Stratégie HKLM Pesto invalide : " + name + ". Aucune mutation tant que cette restriction n'est pas lisible.");
                switch (name)
                {
                    case "IncidentMode": incident = number == 1; break;
                    case "DisableUnattendedJoin": disableJoin = number == 1; break;
                    case "DisableUnattendedOperations": disableOperations = number == 1; break;
                    case "MaxBatch": maxBatch = number; break;
                }
            }
            string? ReadString(string name)
            {
                if (!names.Contains(name, StringComparer.Ordinal)) return null;
                if (key.GetValueKind(name) != RegistryValueKind.String
                    || key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames) is not string value
                    || value.Length > 65536)
                    throw new IOException("Stratégie HKLM illisible : " + name);
                return value;
            }
            return new(incident, maxBatch, ReadString("ScenarioJson"), DisableUnattendedJoin: disableJoin,
                DisableUnattendedOperations: disableOperations, CampaignApprovalJson: ReadString("CampaignApprovalJson"));
        }
        catch (Exception)
        {
            return new(Refusal: "Les restrictions HKLM\\SOFTWARE\\Policies\\M4D\\Pesto ne peuvent pas être lues : aucune mutation, aucune valeur supposée.");
        }
    }
}
