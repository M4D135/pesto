namespace Pesto.Engine.Live;

/// <summary>
/// Source du compte AD explicite pour le repli authentifié V1, réservée au harnais de qualification sur le poste
/// Windows de qualification (le pont et la production n'en connaissent jamais l'existence). Port du formulaire de
/// connexion V1 (Pesto-Authentication.ps1) : le compte explicitement saisi se distingue du compte de session SSO —
/// sans saisie explicite, le mode reste <see cref="TaskFallbackAccountMode.SessionSso"/> et le repli est refusé avec
/// la raison V1, jamais simulé ni activé implicitement. Le mot de passe reste en mémoire de la session : jamais
/// écho, jamais de log, jamais d'arguments CLI, jamais le pont, jamais un fichier — la préférence V1 analogue
/// (login.json) ne stocke que l'identifiant. L'acquisition a lieu au moment précis du repli, avec confirmation
/// explicite de l'action (saisie de « OUI »), et le credential est purgé par l'adaptateur en finally : durée de
/// conservation bornée à l'opération. Sans console utilisable, aucune saisie n'est possible : mode session SSO.
/// </summary>
public sealed class ConsoleAdCredentialSource : ITaskFallbackCredentialSource
{
    public TaskFallbackAccountMode Mode { get; }

    /// <summary>Identifiant affiché après saisie (jamais le mot de passe), pour les messages et les preuves.</summary>
    public string? DisplayUserName { get; private set; }

    public ConsoleAdCredentialSource() => Mode = ConsoleUsable() ? TaskFallbackAccountMode.ExplicitAccount : TaskFallbackAccountMode.SessionSso;

    private static bool ConsoleUsable()
    {
        try { return Environment.UserInteractive && !Console.IsInputRedirected && !Console.IsOutputRedirected; }
        catch (Exception) { return false; }
    }

    public PestoAdCredential? AcquireForFallback(string computer, string? newName, string operationId)
    {
        if (Mode != TaskFallbackAccountMode.ExplicitAccount) return null;
        var buffer = new List<char>();
        try
        {
            Console.WriteLine();
            Console.WriteLine("Pesto — repli authentifié V1 (tâche élevée sur la cible) : " + computer + " → " + (newName ?? "?") + ".");
            Console.WriteLine("Le compte AD ne sert qu'à cette opération : en mémoire uniquement, jamais journalisé, jamais transmis au pont.");
            Console.Write("Compte AD (DOMAIN\\utilisateur ou utilisateur@domaine), ou Entrée pour refuser : ");
            var user = Console.ReadLine();
            if (string.IsNullOrWhiteSpace(user)) return null;
            Console.Write("Mot de passe (aucun écho) : ");
            while (true)
            {
                var key = Console.ReadKey(intercept: true);
                if (key.Key == ConsoleKey.Enter) break;
                if (key.Key == ConsoleKey.Backspace) { if (buffer.Count > 0) buffer.RemoveAt(buffer.Count - 1); continue; }
                if (key.Key == ConsoleKey.Escape) { buffer.Clear(); break; }
                if (!char.IsControl(key.KeyChar)) buffer.Add(key.KeyChar);
            }
            Console.WriteLine();
            if (buffer.Count == 0) return null;
            Console.Write("Confirmation de l'action — tapez OUI pour exécuter la tâche de repli sur " + computer + " → " + (newName ?? "?") + " sous ce compte : ");
            var confirmation = Console.ReadLine();
            if (!string.Equals(confirmation?.Trim(), "OUI", StringComparison.Ordinal)) return null;
            DisplayUserName = user.Trim();
            return new PestoAdCredential(user.Trim(), new string(buffer.ToArray()));
        }
        catch (Exception)
        {
            // Console interrompue ou indisponible en cours de saisie : refus, jamais un repli implicite.
            return null;
        }
        finally
        {
            buffer.Clear();
        }
    }
}
