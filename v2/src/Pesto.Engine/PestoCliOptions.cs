using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Closed non-secret command line. Configuration/profile routing belongs exclusively to the native host.</summary>
public sealed record PestoCliOptions(string Action, string? Computer = null, string? NewName = null, string? TargetOu = null,
    string? Type = null, string? SiteCode = null, string? ServiceCode = null, string? PlanPath = null, string? OutPlanPath = null,
    string? IdempotencyKey = null, bool Execute = false, bool CredentialStdin = false, bool EntraLeaveConfirmed = false,
    string? MetadataPath = null, string? ApprovalPath = null, string? ReceiptId = null)
{
    public static PestoCliOptions Parse(IReadOnlyList<string> args)
    {
        if (args.Count is < 2 or > 48 || args[0] != "--cli") throw Invalid("Utilisez --cli suivi d’une action déclarée.");
        var action = args[1] switch
        {
            "inspect" or "diagnose" or "join" or "rename" or "move" or "renameMove" or "verify" => args[1],
            _ => throw Invalid("Action CLI inconnue."),
        };
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var flags = new HashSet<string>(StringComparer.Ordinal);
        string[] valueNames = ["--computer", "--new-name", "--target-ou", "--type", "--site-code", "--service-code", "--plan", "--out-plan", "--idempotency-key", "--metadata", "--approval", "--receipt"];
        string[] flagNames = ["--execute", "--credential-stdin", "--confirm-entra-leave"];
        for (var index = 2; index < args.Count; index++)
        {
            var key = args[index];
            if (flagNames.Contains(key, StringComparer.Ordinal))
            {
                if (!flags.Add(key)) throw Invalid("Option CLI répétée.");
                continue;
            }
            if (!valueNames.Contains(key, StringComparer.Ordinal) || ++index >= args.Count || values.ContainsKey(key))
                throw Invalid("Option CLI inconnue, répétée ou incomplète.");
            var value = args[index];
            if (value.Length is < 1 or > 4096 || value.Any(char.IsControl) || value.StartsWith("--", StringComparison.Ordinal))
                throw Invalid("Valeur CLI vide, invalide ou hors limites.");
            values.Add(key, value);
        }
        string? V(string key) => values.GetValueOrDefault(key);
        var options = new PestoCliOptions(action, V("--computer"), V("--new-name"), V("--target-ou"), V("--type"), V("--site-code"),
            V("--service-code"), V("--plan"), V("--out-plan"), V("--idempotency-key"), flags.Contains("--execute"),
            flags.Contains("--credential-stdin"), flags.Contains("--confirm-entra-leave"), V("--metadata"), V("--approval"), V("--receipt"));
        options.Validate(); return options;
    }

    public void Validate()
    {
        if (Action is not ("inspect" or "diagnose" or "join" or "rename" or "move" or "renameMove" or "verify")) throw Invalid("Action CLI inconnue.");
        if (Action == "verify")
        {
            // Same explicit check as Interventions > Vérifier l’état: one receipt, nothing else, never an operation.
            if (ReceiptId is null || !Regex.IsMatch(ReceiptId, "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking)
                || Computer is not null || NewName is not null || TargetOu is not null || Type is not null || SiteCode is not null || ServiceCode is not null
                || PlanPath is not null || OutPlanPath is not null || IdempotencyKey is not null || Execute || CredentialStdin || EntraLeaveConfirmed
                || MetadataPath is not null || ApprovalPath is not null)
                throw Invalid("Verify accepte uniquement --receipt avec l’identifiant d’un reçu, sans plan, nom, compte ni option d’exécution.");
            return;
        }
        if (ReceiptId is not null) throw Invalid("--receipt est réservé à l’action verify.");
        foreach (var name in new[] { Computer, NewName })
            if (name is not null && !RemoteWindowsEvidenceProtocol.IsName(name)) throw Invalid("Nom d’ordinateur CLI invalide.");
        if (Type is not null && !Regex.IsMatch(Type, "^[PSV]$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking)
            || SiteCode is not null && !Regex.IsMatch(SiteCode, "^[A-Za-z0-9]{1,8}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking)
            || ServiceCode is not null && !Regex.IsMatch(ServiceCode, "^[A-Za-z0-9]{1,8}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking)
            || TargetOu is not null && !V1Config.IsOuPath(TargetOu)) throw Invalid("Facettes ou OU CLI invalides.");
        foreach (var path in new[] { PlanPath, OutPlanPath, MetadataPath, ApprovalPath })
            if (path is not null && (!Path.IsPathFullyQualified(path) || path.Length > 4096 || path.Any(char.IsControl)))
                throw Invalid("Les documents CLI exigent un chemin absolu sans caractère de contrôle.");
        if (IdempotencyKey is not null && !Regex.IsMatch(IdempotencyKey, "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking))
            throw Invalid("Clé idempotente : 1 à 128 caractères ASCII (lettres, chiffres, . _ : / -).");
        if (Action is "inspect" or "diagnose")
        {
            if (Execute || PlanPath is not null || OutPlanPath is not null || IdempotencyKey is not null || NewName is not null
                || TargetOu is not null || Type is not null || SiteCode is not null || ServiceCode is not null || EntraLeaveConfirmed
                || MetadataPath is not null || ApprovalPath is not null)
                throw Invalid("Inspect et Diagnose acceptent uniquement une lecture, sans plan ni option d’exécution.");
        }
        else if (Execute)
        {
            if (PlanPath is null || IdempotencyKey is null || OutPlanPath is not null)
                throw Invalid("--execute exige un plan exporté et --idempotency-key ; séparez la préparation et l’exécution.");
        }
        else if (IdempotencyKey is not null || EntraLeaveConfirmed || ApprovalPath is not null)
            throw Invalid("Clé, accord de campagne et confirmation Entra sont réservés à --execute.");
        if (Action is "move" && EntraLeaveConfirmed) throw Invalid("Un déplacement seul ne peut pas autoriser un retrait Entra.");
    }

    internal static PestoException Invalid(string message) => new("automation.arguments", message);
}
