using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Profil d'hôte décidé par le raccordement explicite (constat 5 de la revue du 24/10).</summary>
public enum HostProfile
{
    /// <summary>Interface normale : adaptateur Windows sélectionné si une installation V1 locale est fournie.</summary>
    Production,
    /// <summary>Profil distinct pour les preuves de qualification ; toutes ses options explicites restent obligatoires.</summary>
    QualificationHarness,
}

/// <summary>
/// Entrées de la décision de raccordement, observées par l'hôte et passées telles quelles. Aucune exécution ici :
/// décision pure, testable sur fixtures hors Windows. Sélectionner un adaptateur ne lance aucune opération.
/// </summary>
public sealed record HostWiringRequest(
    bool Simulation,
    bool QualificationRequested,
    string? MutationAdapterId,
    string? Confirmation,
    bool IsWindows,
    bool HasV1Root);

/// <summary>Décision de raccordement. Les aperçus, confirmations et reçus restent exigés à chaque opération.</summary>
public sealed record HostSelection(HostProfile Profile, string? AdapterId)
{
    public bool IsQualificationHarness => Profile == HostProfile.QualificationHarness;
}

/// <summary>Lancement analysé : mode, installation V1 et décision de raccordement.</summary>
public sealed record HostLaunch(bool Simulation, string? V1Root, HostSelection Wiring, bool ChooseAccount = false, bool SettingsOnly = false);

public enum HostAuthenticationMode { Windows, ExplicitAd, ChooseAccount }

/// <summary>Only a local membership observation decides the initial account flow; no authentication or IO here.</summary>
public static class HostAuthentication
{
    public static HostAuthenticationMode Select(bool domainJoined, bool chooseAccount) => !domainJoined
        ? HostAuthenticationMode.ExplicitAd
        : chooseAccount ? HostAuthenticationMode.ChooseAccount : HostAuthenticationMode.Windows;
}

/// <summary>
/// La production Windows avec --v1-root utilise l'adaptateur réel. Aucune mutation n'est lancée au démarrage :
/// le moteur exige un aperçu, un plan frais, la confirmation exacte et un reçu durable. La simulation et un hôte
/// sans configuration restent sans adaptateur. Le harnais conserve ses options explicites et son profil distinct ;
/// sa sélection ne constitue pas une preuve de qualification AD.
/// </summary>
public static class HostWiring
{
    /// <summary>Seul adaptateur de mutation déclaré à ce jour (transitoire PS 5.1, non qualifié).</summary>
    public const string AdapterPs51 = "ps51";

    /// <summary>Confirmation exacte exigée de l'opérateur pour le harnais de qualification.</summary>
    public const string ConfirmationPhrase = "QUALIFICATION WINDOWS/AD";

    /// <summary>Analyse des arguments de l'hôte puis décision. Refus motivés (PestoException) avant toute construction.</summary>
    public static HostLaunch Parse(IReadOnlyList<string> args)
    {
        var simulation = false;
        string? root = null;
        var harness = false;
        string? adapter = null;
        string? confirmation = null;
        var chooseAccount = false;
        var settingsOnly = false;
        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case "--simulation" when !simulation:
                    simulation = true;
                    break;
                case "--choose-account" when !chooseAccount:
                    chooseAccount = true;
                    break;
                case "--settings" when !settingsOnly:
                    settingsOnly = true;
                    break;
                case "--v1-root" when root is null && i + 1 < args.Count:
                    root = args[++i];
                    // No implicit network share, relative working directory or device path.
                    if (!Path.IsPathFullyQualified(root) || root.StartsWith("\\\\", StringComparison.Ordinal)
                        || root.StartsWith("//", StringComparison.Ordinal))
                    {
                        throw new PestoException("host.args", "--v1-root attend le chemin absolu d’un dossier local Pesto V1.");
                    }
                    root = Path.GetFullPath(root);
                    break;
                case "--qualification-harness" when !harness:
                    harness = true;
                    break;
                case "--mutation-adapter" when adapter is null && i + 1 < args.Count:
                    adapter = args[++i];
                    break;
                case "--confirm-qualification" when confirmation is null && i + 1 < args.Count:
                    confirmation = args[++i];
                    break;
                default:
                    throw new PestoException("host.args",
                        "Options acceptées : --simulation ; --settings ; ou --v1-root <dossier local>, --choose-account ; pour la qualification, le jeu complet "
                        + "--qualification-harness --mutation-adapter " + AdapterPs51 + " --confirm-qualification « " + ConfirmationPhrase + " ».");
            }
        }
        if (simulation && root is not null)
            throw new PestoException("mode_fixed", "La simulation n’utilise pas d’installation V1. Retirez --v1-root.");
        if (simulation && chooseAccount)
            throw new PestoException("mode_fixed", "La démonstration ne demande aucun compte AD. Retirez --choose-account.");
        if (settingsOnly && (simulation || chooseAccount || harness || adapter is not null || confirmation is not null))
            throw new PestoException("mode_fixed", "--settings ouvre uniquement les paramètres locaux, sans compte AD, démonstration ni adaptateur de qualification.");
        if (simulation && harness)
            throw new PestoException("mode_fixed", "L’harnais de qualification ne s’exécute jamais en simulation. Retirez --simulation.");
        if (!harness && (adapter is not null || confirmation is not null))
            throw new PestoException("host.wiring_inconsistent",
                "Un adaptateur de mutation ou sa confirmation exige --qualification-harness : ces options sont réservées au profil de qualification.");
        // Decide mode before any File.Exists/drive access: even a rejected demo invocation must never probe SMB.
        if (root is not null)
        {
            if (OperatingSystem.IsWindows() && new DriveInfo(Path.GetPathRoot(root)!).DriveType == DriveType.Network)
                throw new PestoException("host.args", "La configuration active doit être locale au profil, pas sur un lecteur réseau.");
            root = V1ConfigDirectory.Resolve(root);
        }
        return new HostLaunch(simulation, root, Select(new HostWiringRequest(
            simulation, harness, adapter, confirmation, OperatingSystem.IsWindows(), !settingsOnly && root is not null)), chooseAccount, settingsOnly);
    }

    /// <summary>
    /// Decision pure du raccordement. La production est le profil par défaut et le reste sauf demande explicite complète.
    /// Chaque garde refuse avec un code et une raison exploitables ; la disponibilité des actions est ensuite
    /// déterminée par le moteur et les prérequis du système, indépendamment des preuves de qualification.
    /// </summary>
    public static HostSelection Select(HostWiringRequest request)
    {
        if (!request.QualificationRequested)
        {
            if (request.MutationAdapterId is not null || request.Confirmation is not null)
                throw new PestoException("host.wiring_inconsistent",
                    "Un adaptateur de mutation ou sa confirmation exige --qualification-harness : ces options sont réservées au profil de qualification.");
            return new HostSelection(HostProfile.Production,
                !request.Simulation && request.IsWindows && request.HasV1Root ? AdapterPs51 : null);
        }
        if (request.Simulation)
            throw new PestoException("mode_fixed", "L’harnais de qualification ne s’exécute jamais en simulation.");
        if (!request.HasV1Root)
            throw new PestoException("config.missing",
                "L’harnais de qualification exige --v1-root : sans installation V1 réellement lisible, aucune écriture ne peut être qualifiée.");
        if (string.IsNullOrWhiteSpace(request.MutationAdapterId))
            throw new PestoException("host.adapter_missing",
                "L’harnais exige --mutation-adapter " + AdapterPs51 + " : aucun adaptateur de mutation n’est injecté par défaut, même dans le harnais.");
        if (!string.Equals(request.MutationAdapterId, AdapterPs51, StringComparison.Ordinal))
            throw new PestoException("host.adapter_unknown",
                "Seul l’adaptateur transitoire « " + AdapterPs51 + " » est déclaré : aucun autre code d’écriture n’est admis.");
        if (!request.IsWindows)
            throw new PestoException("host.not_windows",
                "L’harnais de qualification ne s’exécute que sur le poste Windows de qualification : depuis ce système, les écritures restent refusées plutôt que simulées.");
        if (!string.Equals(request.Confirmation, ConfirmationPhrase, StringComparison.Ordinal))
            throw new PestoException("host.confirmation_required",
                "La qualification exige la confirmation exacte « " + ConfirmationPhrase + " » : l’opérateur confirme connaître la checklist docs/QUALIFICATION-WINDOWS.md (section 3).");
        return new HostSelection(HostProfile.QualificationHarness, AdapterPs51);
    }
}
