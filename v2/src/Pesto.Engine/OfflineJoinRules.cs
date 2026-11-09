using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>V1 ODJ policy and identity rules. No directory, clock-server or network operation belongs here.</summary>
public static class OfflineJoinRules
{
    public const string MutexName = @"Global\GP_PostMutation_v1";
    public const int MaximumBlobBytes = 1024 * 1024;
    public const int MaximumSecretBytes = 2 * 1024 * 1024;
    public static bool IsHash(string? value) => value is { Length: 64 } && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    public static bool IsGuid(string? value) => Guid.TryParseExact(value, "D", out var guid) && guid != Guid.Empty;
    public static bool IsId(string? value) => value is { Length: > 0 and <= 128 }
        && value.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_');
    public static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public static string Hash(ReadOnlySpan<byte> bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    public static bool Within(string dn, string root) => Same(dn, root) || dn.EndsWith("," + root, StringComparison.OrdinalIgnoreCase);

    public static void Guard(ConfigurationAccessMode mode)
    {
        if (mode != ConfigurationAccessMode.Live) throw Refused("offlineJoin.isolated", "La démonstration, le contrôle de santé et la récupération binaire n’accèdent jamais au service ODJ réel.");
    }

    public static void RequireLocal(OfflineJoinLocalState local, DateTimeOffset now, OfflineJoinBinding? binding = null)
    {
        if (local.Error is not null || !EntraPreparationRules.Name(local.Computer) || !IsGuid(local.MachineId)
            || !Same(local.Computer, local.ActiveName) || !Same(local.Computer, local.ConfiguredName)
            || local.PartOfDomain != false || local.DomainRole is not (0 or 2) || local.Administrator != true
            || local.BootUtc is not { } boot || boot == default || boot.Offset != TimeSpan.Zero || boot > now
            || local.Domain is not { Length: > 0 and <= 253 } || local.Domain.Any(char.IsControl))
            throw Refused("offlineJoin.local", "ODJ exige le poste local élevé, hors domaine, avec identité et démarrage prouvés, sans renommage en attente.");
        if (binding is not null && (!Same(local.Computer, binding.Computer) || !Same(local.MachineId, binding.MachineId)
            || local.DomainRole != binding.InitialDomainRole || !Same(local.Domain, binding.InitialWindowsDomain)
            || local.BootUtc < binding.InitialBootUtc))
            throw Refused("offlineJoin.changed", "Le contexte local a changé depuis l’import ODJ ; aucune application ni renommage implicite.");
    }

    internal static OfflineJoinConfiguration ReadConfiguration(byte[] bytes, MutationManagedPolicy managed)
    {
        if (bytes.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw Refused("offlineJoin.config", "Configuration ODJ absente ou trop volumineuse.");
        var text = new UTF8Encoding(false, true).GetString(bytes).TrimStart('\uFEFF');
        var config = V1Config.ValidateText(text);
        using var document = JsonDocument.Parse(text);
        var root = document.RootElement;
        var allowed = root.TryGetProperty("POLICY", out var policy) && policy.TryGetProperty("AllowOfflineJoin", out var flag)
            && flag.ValueKind == JsonValueKind.True;
        // DEBUG switches are rejected even when their historical values were serialized as true/false text.
        if (root.TryGetProperty("DEBUG", out var debug) && debug.ValueKind == JsonValueKind.Object)
        foreach (var key in new[] { "Simulation", "GUI", "HorsDomaine", "MauvaiseOU", "ForceADM", "BPVerifNomAD" })
            if (debug.TryGetProperty(key, out var value) && (value.ValueKind == JsonValueKind.True
                || value.ValueKind == JsonValueKind.String && Same(value.GetString(), "true")))
                throw Refused("offlineJoin.debug", "Une option DEBUG incompatible avec ODJ est active ; aucun import ni envoi.");
        return new(config, config.OperationPolicy.WithManaged(managed), Hash(bytes), allowed);
    }

    internal static void RequireAdmission(OfflineJoinConfiguration configuration, string computer, string targetOu)
    {
        if (!configuration.Allowed) throw Refused("offlineJoin.disabled", "POLICY.AllowOfflineJoin est désactivée. Activez explicitement ce parcours dans les paramètres du profil.");
        var policy = configuration.Policy;
        policy.RequireSupported("offlineJoin");
        if (policy.CoordinationRoot.Length > 0 || policy.CoordinationRequired || policy.ExcludedGroups.Count > 0)
            throw Refused("offlineJoin.online_policy", "ODJ hors connexion est incompatible avec la coordination partagée ou les exclusions de groupes qui exigent une lecture AD.");
        RequireTarget(configuration.Config, targetOu);
        policy.AssertPlan("offlineJoin", computer, computer, null, targetOu, configuration.Config.BuildConvention());
        // V1 ODJ intentionally does not query a DC clock, reserve a name, create an AD account or rename Windows.
    }

    /// <summary>Native admission uses the same strict configuration and managed-policy rules as the service.</summary>
    public static void RequireConfiguration(byte[] bytes, MutationManagedPolicy managed, OfflineJoinBinding binding)
    {
        ValidateBinding(binding);
        var configuration = ReadConfiguration(bytes, managed);
        if (configuration.Sha256 != binding.ConfigurationSha256 || !Same(configuration.Config.Domain, binding.Domain))
            throw Refused("offlineJoin.changed", "La configuration de l’import ODJ a changé ; aucun envoi.");
        RequireAdmission(configuration, binding.Computer, binding.TargetOu);
    }

    public static void RequireObservationConfiguration(byte[] bytes, MutationManagedPolicy managed, OfflineJoinBinding binding)
    {
        ValidateBinding(binding);
        if (!Same(ReadConfiguration(bytes, managed).Config.Domain, binding.Domain))
            throw Refused("offlineJoin.changed", "Le domaine du reçu ODJ ne correspond pas au profil relu ; aucune observation AD.");
    }

    private static void RequireTarget(V1Config config, string targetOu)
    {
        var domainSuffix = string.Join(',', config.Domain.Split('.').Select(part => "DC=" + part));
        if (targetOu.Length > 2048 || !V1Config.IsOuPath(targetOu) || !targetOu.EndsWith("," + domainSuffix, StringComparison.OrdinalIgnoreCase)
            || !new[] { config.RootOu, config.PreprodOu }.Concat(config.OrganismOus).Where(root => !string.IsNullOrEmpty(root))
                .Any(root => Within(targetOu, root!)))
            throw Refused("offlineJoin.target", "L’OU déclarée doit appartenir au domaine et au périmètre configurés. Son existence sera vérifiée après le boot.");
    }

    public static void ValidateBinding(OfflineJoinBinding value)
    {
        if (!IsHash(value.Id) || !EntraPreparationRules.Name(value.Computer) || !SharedCoordinationProtocol.IsDomainName(value.Domain)
            || !IsGuid(value.ExpectedAdGuid) || !IsGuid(value.MachineId) || !IsHash(value.ConfigurationSha256) || !IsHash(value.ProtectedSha256)
            || value.TargetOu is not { Length: > 0 and <= 2048 } || !V1Config.IsOuPath(value.TargetOu)
            || !value.TargetOu.EndsWith("," + string.Join(',', value.Domain.Split('.').Select(part => "DC=" + part)), StringComparison.OrdinalIgnoreCase)
            || value.ImportedUtc == default || value.ImportedUtc.Offset != TimeSpan.Zero || value.ExpiresUtc.Offset != TimeSpan.Zero
            || value.ExpiresUtc <= value.ImportedUtc || value.ExpiresUtc > value.ImportedUtc.AddHours(24)
            || value.InitialBootUtc == default || value.InitialBootUtc.Offset != TimeSpan.Zero || value.InitialBootUtc > value.ImportedUtc
            || value.InitialWindowsDomain is not { Length: > 0 and <= 253 } || value.InitialWindowsDomain.Any(char.IsControl)
            || value.InitialDomainRole is not (0 or 2)) throw Refused("offlineJoin.evidence", "La portée du journal ODJ est invalide.");
    }

    public static string? LocalObservationRefusal(OfflineJoinBinding binding, OfflineJoinLocalState local, DateTimeOffset now,
        DateTimeOffset? appliedBootUtc = null)
    {
        ValidateBinding(binding);
        if (local.Error is not null || !Same(local.MachineId, binding.MachineId) || !Same(local.Computer, binding.Computer)
            || !Same(local.ActiveName, binding.Computer) || !Same(local.ConfiguredName, binding.Computer)
            || local.PartOfDomain != true || local.DomainRole is not (1 or 3) || !Same(local.Domain, binding.Domain))
            return "L’identité, le nom ou l’appartenance Windows attendus ne sont pas prouvés ensemble.";
        if (local.BootUtc is not { } boot || boot.Offset != TimeSpan.Zero || boot <= (appliedBootUtc ?? binding.InitialBootUtc) || boot > now)
            return "Un nouveau démarrage Windows n’est pas prouvé ; aucun succès avant boot.";
        return null;
    }

    public static string? ObservationRefusal(OfflineJoinBinding binding, OfflineJoinObservation observation, DateTimeOffset now,
        DateTimeOffset? appliedBootUtc = null)
    {
        if (observation.Error is not null || observation.ObservedUtc.Offset != TimeSpan.Zero
            || observation.ObservedUtc < now.AddMinutes(-2) || observation.ObservedUtc > now.AddSeconds(5))
            return "L’observation ODJ est incomplète ou périmée ; aucun résultat validé.";
        if (LocalObservationRefusal(binding, observation.Local, now, appliedBootUtc) is { } local) return local;
        if (!Same(observation.AdGuid, binding.ExpectedAdGuid) || !Same(observation.AdName, binding.Computer)
            || !Same(observation.AdOu, binding.TargetOu) || !Same(observation.AdDomain, binding.Domain)
            || observation.DomainController != false || observation.SecureChannel != true)
            return "Le GUID AD déclaré, le nom, l’OU ou le canal sécurisé ne sont pas tous confirmés. Aucune réparation ni jonction rejouée.";
        return null;
    }

    public static PestoException Refused(string code, string message) => new(code, message);
}

internal sealed record OfflineJoinConfiguration(V1Config Config, V1OperationPolicy Policy, string Sha256, bool Allowed);
