using System.Text;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>The current authorization configuration is independent of the historical business receipt.
/// A restart completes neither the business operation nor its policy; no old policy grants a new side effect.</summary>
public static class ReceiptRestartAdmission
{
    public static void RequireSession(bool readOnly, bool available, string? unavailableReason = null)
    {
        if (readOnly) throw ReceiptRestartRules.Refused("Session de consultation : aucune préparation ni demande de redémarrage autorisée.");
        if (!available) throw ReceiptRestartRules.Refused(unavailableReason ?? "L’adaptateur d’écriture n’est pas disponible : aucun redémarrage autorisé.");
    }

    public static MutationPolicyRequirements RequireConfiguration(ReadOnlyMemory<byte> configuration, string configurationSha256,
        RestartReceiptSnapshot source, MutationManagedPolicy managed)
    {
        if (MutationPolicyGuard.ConfigurationRefusal(configuration.Span, configurationSha256) is { } changed)
            throw ReceiptRestartRules.Refused(changed);
        using var stream = new MemoryStream(configuration.ToArray());
        using var reader = new StreamReader(stream, new UTF8Encoding(false, true), detectEncodingFromByteOrderMarks: true);
        var json = reader.ReadToEnd(); var read = V1Config.ValidateText(json);
        RequireLiveConfiguration(json);
        var policy = read.OperationPolicy.WithManaged(managed);
        RequirePlan(read, policy, source.Receipt.Kind, source.Receipt.Computer, source.Receipt.NewName,
            source.InitialOu, source.Receipt.TargetOU, source.Domain);
        if (policy.ExcludedGroups.Count > 0 && !RemoteWindowsEvidenceProtocol.IsGuid(source.ComputerGuid))
            throw ReceiptRestartRules.Refused("POLICY.ExcludedGroupGuids : le compte AD de ce reçu n’a pas de GUID confirmé ; aucune appartenance supposée autorisée.");
        return new(policy.AuditEventLogEnabled, policy.BlockJoinOnClockSkew, policy.ExcludedGroups);
    }

    public static void RequireLiveConfiguration(string json)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("DEBUG", out var debug) || debug.ValueKind != JsonValueKind.Object) return;
        foreach (var name in new[] { "Simulation", "GUI" })
            if (debug.TryGetProperty(name, out var value) && (value.ValueKind == JsonValueKind.True
                || value.ValueKind == JsonValueKind.String && string.Equals(value.GetString()!.Trim(), "true", StringComparison.OrdinalIgnoreCase)))
                throw ReceiptRestartRules.Refused("DEBUG.Simulation ou DEBUG.GUI : aucun redémarrage réel autorisé par cette configuration.");
    }

    internal static void RequirePlan(V1Config read, V1OperationPolicy policy, string kind, string computer, string newName,
        string? initialOu, string targetOu, string domain)
    {
        if (kind is not ("join" or "rename" or "renameMove") || !RemoteWindowsEvidenceProtocol.Same(read.Domain, domain)
            || !Within(targetOu, read.RootOu) || initialOu is { Length: > 0 } && !Within(initialOu, read.RootOu))
            throw ReceiptRestartRules.Refused("Le domaine ou la portée du reçu ne sont plus autorisés par la configuration actuelle : aucun redémarrage préparé.");
        policy.AssertPlan(kind, computer, newName, initialOu, targetOu, read.BuildConvention());
    }

    private static bool Within(string value, string root)
    {
        if (!V1Config.IsOuPath(value) || !V1Config.IsOuPath(root)) return false;
        static string[] Parts(string dn)
        {
            var parts = new List<string>(); var start = 0;
            for (var index = 0; index < dn.Length; index++)
            {
                if (dn[index] == '\\') { index++; continue; }
                if (dn[index] != ',') continue;
                parts.Add(dn[start..index]); start = index + 1;
            }
            parts.Add(dn[start..]); return parts.ToArray();
        }
        var path = Parts(value); var scope = Parts(root);
        return path.Length >= scope.Length && path.Skip(path.Length - scope.Length).SequenceEqual(scope, StringComparer.OrdinalIgnoreCase);
    }
}
