using System.Text.RegularExpressions;

namespace Pesto.Engine;

/// <summary>Pure read-side guard. Pesto V2 never turns a status read into a dsregcmd /leave operation.</summary>
public static class EntraRenameGuard
{
    public static string? Refusal(int exitCode, string output)
    {
        if (exitCode != 0 || output.Length > 65536)
            return "État Entra non vérifié : aucun renommage et aucun retrait Entra automatique.";
        const RegexOptions options = RegexOptions.IgnoreCase | RegexOptions.Multiline | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking;
        var azure = Regex.Matches(output, @"^[ \t]*AzureAdJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$", options);
        var domain = Regex.Matches(output, @"^[ \t]*DomainJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$", options);
        if (azure.Count != 1 || domain.Count != 1 || !domain[0].Groups[1].Value.Equals("YES", StringComparison.OrdinalIgnoreCase))
            return "État Entra ambigu ou appartenance AD non confirmée : aucun renommage et aucun retrait Entra automatique.";
        return azure[0].Groups[1].Value.Equals("NO", StringComparison.OrdinalIgnoreCase) ? null
            : "Poste hybride Entra détecté : le retrait préalable et sa qualification ne sont pas raccordés dans V2. Aucun renommage ni dsregcmd /leave n’est lancé.";
    }
}
