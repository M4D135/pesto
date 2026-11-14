using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>
/// Constat 6 de la revue — écarts transitoires V1 de l'adaptateur de mutations. Les trois comportements sont vérifiés
/// là où ils se décident : lecture de CONF.ClearProtectionOnMove dans le cfg.json (défaut V1 quand absent, « unknown »
/// quand illisible — jamais une levée implicite), gardes portées de V1 dans le script constant (levée temporaire pendant
/// le seul déplacement, restauration puis relecture, 32 si non rétablie, 31 si la configuration l'interdit, 96 si la
/// valeur n'est pas lue), renameMove selon V1 (relecture du nom sous 60 s, 89 « DÉPLACEMENT NON TENTÉ » / « DÉPLACEMENT
/// DIFFÉRÉ », 77, ARRÊT DE SÉCURITÉ 97, demi-succès jamais présenté comme succès), et repli V1 par tâche planifiée sous
/// compte AD — PORTÉ côté adaptateur (TaskFallback/TaskFallbackRunner, voir TaskFallbackTests) et nommé sur chaque refus
/// du script, qui ne doit ni l'improviser ni le masquer en faux écart. Aucune écriture AD, aucune exécution
/// PowerShell depuis ces tests (le script est contrôlé par assertions statiques ; son exécution réelle reste réservée à
/// la qualification Windows/AD, docs/QUALIFICATION-WINDOWS.md).
/// </summary>
internal sealed class TransientAdapterParityTests
{
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";
    private const string ParisOu = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";

    /// <summary>cfg.json de fixture avec (ou sans) la clé ClearProtectionOnMove écrite dans CONF comme le fait V1.</summary>
    private static string RootWithClearProtection(string? fragment)
    {
        var json = LiveTestConfig.NoRandom.Replace(", \"ClearProtectionOnMove\": \"true\"", "");
        if (fragment is not null)
            json = json.Replace("\"EntraPolicy\": \"HybridOnly\"", "\"EntraPolicy\": \"HybridOnly\", " + fragment);
        return LiveTestConfig.Write(json);
    }

    // ---- (a) CONF.ClearProtectionOnMove : port de la lecture V1 ------------------------------

    [Test]
    public void ClearProtectionOnMoveFollowsTheV1Reading()
    {
        // Absent = true : « ClearProtectionOnMove absent = true (valeur appliquée par le moteur) » (Pesto-Configuration V1).
        Check.Equal("true", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection(null)),
            "Clé absente = true, la valeur qu'applique le moteur V1 — jamais un refus plat ni un faux blocage");
        Check.Equal("true", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": \"true\"")),
            "Texte « true » écrit par les paramètres V1 (ToLowerInvariant)");
        Check.Equal("true", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": \"TRUE\"")),
            "Texte accepté sans casse (Convert-Value-TF V1)");
        Check.Equal("true", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": true")),
            "Booléen JSON direct");
        Check.Equal("false", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": \"false\"")),
            "Texte « false » : levée interdite (refus 31 côté script)");
        Check.Equal("false", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": false")),
            "Booléen JSON false");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": \"peut-etre\"")),
            "Valeur invalide : unknown — l'objet protégé sera bloqué, jamais levé par défaut");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(RootWithClearProtection("\"ClearProtectionOnMove\": 1")),
            "Nombre au lieu d'un booléen : unknown, jamais converti en vrai");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(LiveTestConfig.Write("{ pas du JSON ")),
            "cfg.json illisible : unknown, jamais un silence");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(LiveTestConfig.Write("{\"CONF\": []}")),
            "CONF absent ou vide : unknown (le moteur exigerait de toute façon une configuration valide)");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(Path.Combine(Path.GetTempPath(), "pesto-absent-" + Guid.NewGuid().ToString("N"))),
            "Aucun cfg.json : unknown");
        Check.Equal("unknown", PowerShellMutationGateway.ReadClearProtectionOnMove(null),
            "Aucun chemin V1 : unknown");
    }

    [Test]
    public void PayloadCarriesTheReadDecisionAndNeverASecret()
    {
        var request = new Pesto.Engine.MutationRequest("renameMove", Computer, ComputerGuid, "P111301PAINF010",
            ParisOu, "example.local", "dc01.example.local", "plan-1", "receipt-1");
        using var payload = JsonDocument.Parse(PowerShellMutationGateway.BuildPayload(request, "false"));
        var root = payload.RootElement;
        Check.Equal("renameMove", root.GetProperty("Op").GetString(), "Seule l'opération déclarée atteint le script constant");
        Check.Equal("false", root.GetProperty("ClearProtectionOnMove").GetString(), "La décision lue du cfg.json accompagne la demande");
        Check.Equal("dc01.example.local", root.GetProperty("Server").GetString(), "Contrôleur explicite (port -Server V1)");
        Check.Equal(ComputerGuid, root.GetProperty("ComputerGuid").GetString(), "Déplacement uniquement par GUID réellement observé");
        var text = root.ToString();
        foreach (var forbidden in new[] { "password", "mot de passe", "secret", "cmd", "command" })
            Check.True(!text.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Le payload ne contient jamais « " + forbidden + " »");
        using var unknown = JsonDocument.Parse(PowerShellMutationGateway.BuildPayload(request, "peut-etre"));
        Check.Equal("unknown", unknown.RootElement.GetProperty("ClearProtectionOnMove").GetString(),
            "Une décision non lue reste « unknown » : jamais normalisée en true");
    }

    // ---- (a)+(c) gardes portées de V1 dans le script constant --------------------------------

    [Test]
    public void ScriptCarriesTheV1ProtectionGuards()
    {
        var script = PowerShellMutationGateway.ConstantScript;
        Check.Contains("ClearProtectionOnMove", script, "Le script reçoit la décision lue du cfg.json");
        Check.Contains("ProtectedFromAccidentalDeletion:$false", script, "Levée temporaire pendant le seul déplacement (port Set-ADObject V1)");
        Check.Contains("ProtectedFromAccidentalDeletion:$true", script, "La protection d'origine est toujours restaurée (finally V1)");
        Check.Contains("Protection NON RÉTABLIE", script, "Restauration échouée à la relecture : code 32, réparation manuelle, jamais de rejeu");
        Check.Contains("levée temporaire interdite par la configuration", script, "ClearProtectionOnMove lu false : refus 31 motivé de V1, plus un refus plat");
        Check.Contains("ni levée ni admise", script, "Décision non lue : objet protégé bloqué 96, jamais une levée implicite par défaut");
        Check.Contains("origine vérifiée", script, "Succès 30 V1 : déplacement confirmé par GUID ET protection d'origine vérifiée");
        Check.Contains("Properties DistinguishedName,ProtectedFromAccidentalDeletion", script, "La relecture finale contrôle l'OU ET la protection (port V1)");
        var calls = System.Text.RegularExpressions.Regex.Matches(script, @"Invoke-PestoMove \$parsedGuid \$targetOu \$adp \$clearProtection").Count;
        Check.Equal(2, calls, "move seul et renameMove passent tous deux la décision lue au déplacement — aucun chemin de déplacement sans la garde");
    }

    [Test]
    public void ScriptRenameMoveFollowsTheV1DeferredMoveCodes()
    {
        var script = PowerShellMutationGateway.ConstantScript;
        Check.Contains("AddSeconds(60)", script, "Relecture du nouveau nom sur le DC sous 60 s (port Wait-ADComputerVisible)");
        Check.Contains("DÉPLACEMENT NON TENTÉ", script, "Panne AD pendant l'attente : 89 déplacement non tenté, jamais maquillé en délai de réplication (règle V1)");
        Check.Contains("DÉPLACEMENT DIFFÉRÉ", script, "Aucune visibilité sous 60 s : 89 déplacement différé, à reprogrammer seul");
        Check.Contains("ARRÊT DE SÉCURITÉ", script, "Déplacement incertain après renommage accepté : 97 arrêt de sécurité, jamais rejoué");
        Check.Contains("code=77", script, "Renommage + déplacement confirmés (ou déjà en place, 33) : code 77 de V1");
        Check.Contains("DÉPLACEMENT ÉCHOUÉ", script, "Déplacement définitivement refusé après renommage accepté : 89 à reprogrammer — un demi-succès n'est jamais présenté comme un succès");
        Check.Contains("jamais relancé automatiquement", script, "Les issues 89 disent qu'elles ne sont jamais relancées seules");
    }

    // ---- (b) repli V1 par tâche planifiée sous compte AD : porté côté adaptateur, jamais improvisé par le script ----

    [Test]
    public void ScriptHandsTheV1PasswordTaskFallbackToTheAdapterWithoutHidingIt()
    {
        var script = PowerShellMutationGateway.ConstantScript;
        // Le repli authentifié est PORTÉ côté adaptateur (TaskFallback + PestoTaskFallbackRunner + transport COM,
        // TaskFallbackTests) ; le script constant, lui, ne doit JAMAIS l'improviser. Double contrôle d'honnêteté :
        // 1) le script nomme le repli et la politique sur chaque chemin de refus qui, en V1, aurait un repli —
        //    la suppression d'une seule mention doit faire échouer ce test (masquage partiel refusé) ;
        var named = System.Text.RegularExpressions.Regex.Matches(script, "AllowPasswordTaskFallback").Count;
        Check.True(named >= 3, "Le repli V1 par tâche planifiée sous compte AD est nommé sur chaque refus concerné, pas masqué (mentions : " + named + ")");
        // 2) le script ne prétend plus qu'il « n'est pas porté » (le masquage inverse serait un faux écart) :
        Check.True(!script.Contains("n'est pas porté", StringComparison.Ordinal),
            "Aucun chemin ne revendique plus un écart faux : le repli est porté par l'adaptateur, le script ne le masque plus en écart");
        Check.Contains("est décidé par l''adaptateur selon la politique lue du cfg.json", script,
            "Le refus distant nommé dit la vérité : la décision du repli appartient à l'adaptateur, selon la politique lue");
        Check.True(System.Text.RegularExpressions.Regex.Matches(script, "Aucun repli automatique").Count >= 2, "Aucun repli automatique après un refus confirmé (local et distant)");
        var afterUncertain = System.Text.RegularExpressions.Regex.Matches(script, "Aucun repli après un résultat incertain").Count;
        Check.True(afterUncertain >= 2, "Aucun repli après un résultat incertain (règle V1), sur les deux appels de renommage (mentions : " + afterUncertain + ")");
        // Le script ne contient aucune implémentation détournée du repli (le transport est le COM de l'adaptateur, pas une
        // commande improvisée dans le script) ; aucun mot de passe n'y transite jamais.
        // (« AllowPasswordTaskFallback » nomme la politique et contient le mot password : la liste interdite vise les
        // transports et saisies de secret, pas le nom de la politique.)
        foreach (var forbidden in new[] { "schtasks", "Register-ScheduledTask", "ScheduledTask", "Get-Credential", "-Credential", "NetUse", "Invoke-Command", "Enter-PSSession", "ConvertTo-SecureString", "-Password", "/rp" })
            Check.True(!script.Contains(forbidden, StringComparison.OrdinalIgnoreCase),
                "Le repli n'est pas improvisé dans le script ni alimenté par un secret : « " + forbidden + " » absent");
        Check.Contains("ProtectedData]::Unprotect", script, "Le compte explicite vient uniquement de l’enveloppe DPAPI native");
        Check.Contains("DataProtectionScope]::CurrentUser", script, "Le secret reste lié à l’utilisateur Windows du processus");
        Check.Contains("[Array]::Clear($bytes", script, "Les octets déchiffrés sont purgés");
        Check.Contains("$secure.Dispose()", script, "Le SecureString est libéré après l’opération");
        // L'enchaînement après repli accepté existe bien, sans jamais relancer le renommage lui-même (règle V1 « aucun rejeu »).
        Check.Contains("'moveAfterRename'", script, "L'op moveAfterRename enchaîne le déplacement seul après un repli de renommage accepté (port GoRenameAndMove)");
        var renameCalls = System.Text.RegularExpressions.Regex.Matches(script, "Invoke-PestoRename \\$computer \\$newName").Count;
        Check.Equal(2, renameCalls, "Le renommage direct n'est appelé que par rename et renameMove — moveAfterRename ne le relance jamais (aucun rejeu du repli)");
    }

    [Test]
    public void ScriptNeverReachesAForbiddenNativeCommand()
    {
        var script = PowerShellMutationGateway.ConstantScript;
        foreach (var forbidden in new[] { "Remove-ADComputer", "Remove-ADObject", "New-ADObject", "Set-ADComputer", "Restart-Computer", "Stop-Computer", "shutdown", "dsregcmd", "Reboot" })
            Check.True(!script.Contains(forbidden, StringComparison.OrdinalIgnoreCase),
                "Aucun objet supprimé, aucun redémarrage, aucune écriture hors des trois commandes autorisées : « " + forbidden + " » absent");
        Check.Contains("Add-Computer -DomainName", script, "Les seules mutations atteignables restent Add-Computer, Rename-Computer, Move-ADObject (+ Set-ADObject pour la seule garde de protection portée de V1)");
        Check.Contains("Rename-Computer -NewName", script, "Rename-Computer reste l'autorité du renommage");
        Check.Contains("Move-ADObject -Identity $parsedGuid", script, "Move-ADObject uniquement par GUID réellement observé");
    }
}
