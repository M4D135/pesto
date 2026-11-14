using System.Runtime.InteropServices;

namespace Pesto.Engine.Live;

/// <summary>
/// Transport réel du repli authentifié V1 : COM <c>Schedule.Service</c> (Task Scheduler), port de
/// <c>New-PestoTaskService</c> et d'<c>Invoke-PestoSchtasks</c> — « Authentification COM en mémoire. Jamais /p, /rp
/// ou secret dans un processus. » Le mot de passe du compte AD saisi ne quitte jamais le processus : il est passé
/// uniquement aux appels COM <c>Connect</c> et <c>RegisterTask</c>, jamais en argument de commande, en log, en XML,
/// en reçu ou en réponse du pont. Les seules opérations admises sont création / lancement / suppression, dans
/// l'espace fermé <c>\Pesto_...</c> ; la suppression n'est confirmée que par relecture d'absence (port V1).
/// Les objets COM sont libérés en finally (port <c>Release-PestoComObject</c>).
/// Ce transport n'est jamais construit ni appelé depuis ce job : il n'est injecté que par l'adaptateur de mutation
/// lui-même injecté par le harnais de qualification explicite (<c>HostWiring</c>), sur le poste Windows de
/// qualification uniquement (docs/QUALIFICATION-WINDOWS.md).
/// </summary>
[System.Runtime.Versioning.SupportedOSPlatform("windows")]
public sealed class TaskSchedulerComTransport : ITaskSchedulerTransport, ISystemDiagnosticTaskTransport, IDisposable
{
    private const uint RegisterUpdate = 2;      // TASK_CREATE; a name collision never overwrites an existing task.
    private const uint LogonPassword = 1;       // TASK_LOGON_PASSWORD
    private const uint LogonServiceAccount = 5; // TASK_LOGON_SERVICE_ACCOUNT

    private readonly TaskSchedulerSession session;
    private string? diagnosticDefinitionHash;

    public string Description { get; }

    public TaskSchedulerComTransport()
    {
        session = new TaskSchedulerSession((computer, principal, password) => Connect(computer, principal, password), Release);
        Description = OperatingSystem.IsWindows()
            ? "Planificateur Windows · COM Schedule.Service · compte AD en mémoire uniquement · non qualifié Windows/AD"
            : "Planificateur Windows indisponible : ce système n’est pas Windows, le repli par tâche est refusé plutôt que simulé";
    }

    public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal)
    {
        RequireWindows();
        RequireTaskName(taskName);
        RequireComputer(computer);
        if (string.IsNullOrEmpty(xml)) throw new InvalidOperationException("Définition de tâche absente : aucune création.");
        dynamic service = session.Bind(computer, taskName, principal, passwordForPrincipal);
        try
        {
            dynamic folder = service.GetFolder("\\");
            try
            {
                if (passwordForPrincipal is null)
                {
                    // Tâche SYSTEM (compte de service) : aucun secret n'existe ni ne circule.
                    object registered = folder.RegisterTask(taskName, xml, RegisterUpdate, "SYSTEM", null, LogonServiceAccount, null);
                    Release(registered);
                }
                else
                {
                    // Port du garde V1 : le principal enregistré est exactement le compte saisi (cred.UserName tel
                    // que saisi, comme en V1) ; le mot de passe voyage en mémoire COM uniquement.
                    object registered = folder.RegisterTask(taskName, xml, RegisterUpdate, principal, passwordForPrincipal, LogonPassword, null);
                    Release(registered);
                }
            }
            finally { Release(folder); }
        }
        finally { /* The operation-scoped session owns this authenticated service. */ }
    }

    public void RegisterSystem(string computer, string taskName, string xml, string connectionPrincipal, string connectionPassword)
    {
        RequireWindows(); RequireTaskName(taskName); RequireComputer(computer);
        if (string.IsNullOrWhiteSpace(connectionPrincipal) || string.IsNullOrEmpty(connectionPassword) || string.IsNullOrEmpty(xml))
            throw new InvalidOperationException("Compte de connexion ou définition du diagnostic absent.");
        // Separate the authenticated COM connection from the diagnostic's SYSTEM principal. The session binds
        // this exact target/task and retains no password; later Run/Probe/Delete never reconnect as local SSO.
        dynamic service = session.Bind(computer, taskName, connectionPrincipal, connectionPassword);
        dynamic folder = service.GetFolder("\\");
        try
        {
            dynamic registered = folder.RegisterTask(taskName, xml, RegisterUpdate, "SYSTEM", null, LogonServiceAccount, null);
            try { diagnosticDefinitionHash = TaskFallback.DefinitionHash((string)registered.Xml); }
            finally { Release(registered); }
        }
        finally { Release(folder); }
    }

    public void Run(string computer, string taskName)
    {
        RequireWindows();
        RequireTaskName(taskName);
        RequireComputer(computer);
        dynamic service = session.ForTask(computer, taskName);
        try
        {
            dynamic folder = service.GetFolder("\\");
            try
            {
                dynamic task = folder.GetTask(taskName);
                try
                {
                    if (diagnosticDefinitionHash is not null && TaskFallback.DefinitionHash((string)task.Xml) != diagnosticDefinitionHash)
                        throw new InvalidOperationException("Définition de diagnostic modifiée : aucun lancement.");
                    task.Run(null);
                }
                finally { Release(task); }
            }
            finally { Release(folder); }
        }
        finally { /* The operation-scoped session owns this authenticated service. */ }
    }

    public TaskProbeResult Probe(string computer, string taskName)
    {
        RequireWindows();
        RequireTaskName(taskName);
        RequireComputer(computer);
        dynamic service = session.ForTask(computer, taskName);
        try
        {
            dynamic folder = service.GetFolder("\\");
            try
            {
                dynamic task = folder.GetTask(taskName);
                try
                {
                    var lastRun = TaskSchedulerComValues.LastRunTime((object?)task.LastRunTime);
                    return new TaskProbeResult((int)task.State, (long)task.LastTaskResult, lastRun, (string)task.Xml);
                }
                finally { Release(task); }
            }
            finally { Release(folder); }
        }
        finally { /* The operation-scoped session owns this authenticated service. */ }
    }

    public void Delete(string computer, string taskName)
    {
        RequireWindows();
        RequireTaskName(taskName);
        RequireComputer(computer);
        dynamic service = session.ForTask(computer, taskName);
        try
        {
            dynamic folder = service.GetFolder("\\");
            try
            {
                dynamic task = folder.GetTask(taskName);
                try
                {
                    if (diagnosticDefinitionHash is not null && TaskFallback.DefinitionHash((string)task.Xml) != diagnosticDefinitionHash)
                        throw new InvalidOperationException("Définition de diagnostic modifiée : aucun nettoyage.");
                    // Port V1 : suppression refusée si la tâche est active ou d'état inconnu (1=Created, 3=Ready autorisés).
                    var state = (int)task.State;
                    if (state is not (1 or 3)) throw new InvalidOperationException("Tâche active ou état inconnu : suppression refusée.");
                }
                finally { Release(task); }
                folder.DeleteTask(taskName, 0);
                // Relecture d'absence obligatoire (port V1 : « La suppression de la tâche n'est pas confirmée par relecture »).
                try
                {
                    dynamic remaining = folder.GetTask(taskName);
                    Release(remaining);
                    throw new InvalidOperationException("La suppression de la tâche n'est pas confirmée par relecture.");
                }
                catch (COMException error) when ((error.HResult & 0xFFFF) == 2)
                {
                    // ERROR_FILE_NOT_FOUND : absence effectivement confirmée.
                }
            }
            finally { Release(folder); }
        }
        finally { /* The operation-scoped session owns this authenticated service. */ }
    }

    /// <summary>Port de <c>Get-PestoRemoteTaskLogTail</c> : lecture UNC en lecture seule du journal cible, jamais un échec bloquant.</summary>
    public string? ReadTaskLogTail(string computer, string localLogPath)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(localLogPath) || localLogPath.Length < 3 || !OperatingSystem.IsWindows()) return null;
            var drive = localLogPath[..1];
            var rest = localLogPath[2..].TrimStart('\\');
            var unc = @"\\" + computer + "\\" + drive + "$\\" + rest;
            if (!File.Exists(unc)) return null;
            var lines = File.ReadLines(unc).Reverse().Take(4).ToArray();
            Array.Reverse(lines);
            var tail = string.Join(" | ", lines.Select(line => new string(line.Where(c => !char.IsControl(c)).ToArray()).Trim()));
            return tail.Length == 0 ? null : tail.Length > 300 ? tail[..300] : tail;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public void Dispose() => session.Dispose();

    private static void RequireWindows()
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("Le repli par tâche planifiée exige Windows : sur tout autre système il est refusé plutôt que simulé.");
    }

    private static void RequireTaskName(string taskName)
    {
        if (!TaskFallback.IsPestoTaskName(taskName))
            throw new ArgumentException("Nom de tâche hors espace Pesto : seule la forme « \\Pesto_... » est manipulable (port V1).", nameof(taskName));
    }

    private static void RequireComputer(string computer)
    {
        if (string.IsNullOrEmpty(computer) || computer.Length > 15 || !System.Text.RegularExpressions.Regex.IsMatch(computer, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$"))
            throw new ArgumentException("Cible de tâche invalide (port Test-PestoComputerName).", nameof(computer));
    }

    /// <summary>Port de <c>New-PestoTaskService</c> : connexion COM en mémoire. Sans compte, connexion à l'identité
    /// du processus uniquement pour une session sans compte explicite ; la même connexion sert ensuite au cycle entier.
    /// Avec compte, DOMAIN\\user ou user@domaine, mot de passe en mémoire.</summary>
    private static dynamic Connect(string computer, string? principal, string? password)
    {
        var type = Type.GetTypeFromProgID("Schedule.Service")
            ?? throw new InvalidOperationException("Le Planificateur de tâches Windows (Schedule.Service) est indisponible : le repli est refusé, aucune tâche n'est simulée.");
        var service = Activator.CreateInstance(type)
            ?? throw new InvalidOperationException("Le Planificateur de tâches Windows n'a pas pu être instancié : le repli est refusé.");
        try
        {
            dynamic com = service;
            if (principal is not null && password is not null)
            {
                var (user, domain) = TaskFallback.SplitAccount(principal, Environment.MachineName);
                com.Connect(computer, user, domain, password);
            }
            else
            {
                com.Connect(computer);
            }
            return com;
        }
        catch
        {
            Release(service);
            throw;
        }
    }

    private static void Release(object? value)
    {
        if (value is null) return;
        try
        {
            if (Marshal.IsComObject(value)) Marshal.FinalReleaseComObject(value);
        }
        catch (Exception)
        {
            // Port de Release-PestoComObject : la libération ne doit jamais masquer le résultat de l'opération.
        }
    }
}
