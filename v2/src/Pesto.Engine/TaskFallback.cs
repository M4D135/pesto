using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pesto.Engine;

/// <summary>
/// Repli authentifié V1 par tâche planifiée sous compte AD explicitement saisi — port de la source V1 lue en entier
/// (Pesto-Operations.ps1 <c>RenameComputer</c> lignes 1257-1267, <c>Invoke-RenameComputerTaskFallback</c>,
/// <c>Invoke-PestoSchtasks</c>/<c>New-PestoTaskService</c>, <c>New-PestoRunOnceTaskXml</c>, <c>Get-PestoTaskRunResult</c>,
/// <c>Set-PestoTaskEvidence</c>/<c>Assert-PestoTaskDefinition</c>/<c>Get-PestoTaskDefinitionHash</c>,
/// Pesto-Authentication.ps1 pour la distinction session SSO / compte explicite, Pesto-Policy.ps1 pour
/// <c>ConvertTo-PestoPolicy</c>). Règles V1 portées sans adoucissement :
/// - le repli n'existe QUE pour le renommage distant refusé d'un refus Windows confirmé 5 ou 1314, avec un compte AD
///   explicitement saisi (jamais le jeton de session SSO) et <c>POLICY.AllowPasswordTaskFallback</c> lu vrai du
///   cfg.json — jamais activé implicitement (défaut V1 : faux ; 1326 « identifiants incorrects » ne déclenche jamais
///   le repli, un résultat incertain non plus) ;
/// - le mot de passe ne voyage JAMAIS en argument de commande, en log, en reçu, en XML de tâche ni en réponse du pont :
///   seul le transport (COM Planificateur en mémoire) le reçoit, et le credential est purgé dès l'opération terminée
///   (durée de conservation limitée aux besoins de l'opération, port du nettoyage V1) ;
/// - tâche hors espace « \Pesto_... » refusée ; XML sans déclencheur (seul un Run explicite la lance) ; principal de
///   tâche obligatoirement égal au compte saisi ; définition suivie par empreinte SHA-256 et revérifiée avant
///   lancement et suppression ; suppression seulement après relecture confirmant l'absence ;
/// - résultat lu numériquement (indépendant de la langue) : 0 = renommage accepté avec redémarrage à planifier,
///   43 = blocage Entra nommé, 97 ou code 267008/267009/267011 = incertain — la tâche est alors CONSERVÉE pour
///   diagnostic et jamais relancée automatiquement.
/// Ce fichier ne décide ni n'exécute rien seul : l'adaptateur transitoire l'appelle après son propre envoi, le
/// transport réel n'est injecté que par le harnais de qualification (HostWiring) et aucune exécution n'est possible
/// depuis ce job (docs/PARITY.md, docs/QUALIFICATION-WINDOWS.md).
/// </summary>
public enum TaskFallbackAccountMode
{
    /// <summary>Session Windows intégrée (port V1 « mode Compte Windows », <c>$script:cred = $null</c>) : le repli est indisponible.</summary>
    SessionSso,
    /// <summary>Compte AD explicitement saisi (port V1 <c>$script:cred</c> issu du formulaire de connexion) : seul mode où le repli est envisageable.</summary>
    ExplicitAccount,
}

/// <summary>
/// Compte AD explicitement saisi, en mémoire seulement (port du <c>PSCredential</c> de V1, jamais sérialisé).
/// Le mot de passe n'est exposé qu'à <see cref="TakePassword"/>, une seule fois par opération, puis purgé par
/// <see cref="Clear"/> ; <see cref="ToString"/> ne rend jamais le secret.
/// </summary>
public sealed class PestoAdCredential : IDisposable
{
    private char[]? password;

    public PestoAdCredential(string userName, string password)
    {
        if (string.IsNullOrWhiteSpace(userName)) throw new ArgumentException("Identifiant de compte AD requis.", nameof(userName));
        UserName = userName.Trim();
        this.password = password?.ToCharArray() ?? [];
    }

    /// <summary>Identifiant tel que saisi (DOMAIN\user ou user@domaine) — seul élément non secret, comparable au login.json V1 qui ne stocke que ça.</summary>
    public string UserName { get; }

    public bool IsAvailable => password is { Length: > 0 };

    /// <summary>Rendu au transport (COM en mémoire) uniquement. Après purge, aucun secret ne peut plus être lu.</summary>
    public string TakePassword()
    {
        if (password is not { Length: > 0 })
            throw new InvalidOperationException("Le secret du compte AD a déjà été purgé : aucune nouvelle utilisation.");
        return new string(password);
    }

    public void Clear()
    {
        if (password is { } buffer) Array.Clear(buffer, 0, buffer.Length);
        password = null;
    }

    public void Dispose() => Clear();

    public override string ToString() => "PestoAdCredential(" + UserName + ", mot de passe masqué)";
}

/// <summary>
/// Source du compte AD explicite pour le repli (port du formulaire de connexion V1 : Pesto-Authentication.ps1 —
/// la liste blanche des préférences ne stocke QUE l'identifiant, jamais un mot de passe ; le mot de passe reste en
/// mémoire de la session et n'emprunte jamais le pont). Le mode <see cref="TaskFallbackAccountMode.SessionSso"/>
/// correspond au jeton Windows intégré : le repli y est refusé, comme en V1.
/// </summary>
public interface ITaskFallbackCredentialSource
{
    TaskFallbackAccountMode Mode { get; }

    /// <summary>Identifiant affiché (jamais le mot de passe), pour les messages et les preuves.</summary>
    string? DisplayUserName { get; }

    /// <summary>
    /// Acquis au moment précis du repli, pour la seule opération en cours (durée de conservation limitée aux besoins
    /// de l'opération). <c>null</c> = refus de l'opérateur ou compte indisponible : le repli n'a pas lieu.
    /// L'appelant doit purger le credential en finally.
    /// </summary>
    PestoAdCredential? AcquireForFallback(string computer, string? newName, string operationId);
}

/// <summary>Transport du Planificateur de tâches, scellé pour être testable sur fixtures. Le transport réel
/// (COM <c>Schedule.Service</c>, Pesto.Engine.Live) ne reçoit le mot de passe qu'en mémoire, jamais en argument de
/// commande ; le transport de fixture n'écrit rien. Port du contrat historique schtasks remplacé en V1 par
/// <c>Invoke-PestoSchtasks</c> : seules création/lancement/suppression sont admises.</summary>
public interface ITaskSchedulerTransport
{
    /// <summary>Enregistre (ou remplace) la tâche dont la définition XML est exactement <paramref name="xml"/>.
    /// <paramref name="passwordForPrincipal"/> n'est jamais écrit dans le XML ni en log ; <c>null</c> = tâche SYSTEM
    /// (compte de service, sans secret). Le principal doit être le compte saisi (refus V1 « Principal de tâche
    /// différent du compte Pesto »).</summary>
    void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal);

    /// <summary>Demande le lancement explicite (aucun déclencheur dans le XML). Une exception après envoi = résultat
    /// incertain : l'appelant conserve la tâche et ne relance jamais.</summary>
    void Run(string computer, string taskName);

    /// <summary>Lecture numérique de l'état et de la définition courante (contrôle d'empreinte avant toute décision).</summary>
    TaskProbeResult Probe(string computer, string taskName);

    /// <summary>Supprime et RELIT : doit lever si l'absence n'est pas confirmée par relecture (port V1).</summary>
    void Delete(string computer, string taskName);

    /// <summary>Fin de journal cible en lecture seule (port <c>Get-PestoRemoteTaskLogTail</c>), ou <c>null</c> si indisponible.</summary>
    string? ReadTaskLogTail(string computer, string localLogPath);
}

/// <summary>Lecture brute d'une tâche par le transport (port des propriétés COM State/LastTaskResult/LastRunTime/Xml).</summary>
public sealed record TaskProbeResult(int State, long LastTaskResult, DateTimeOffset? LastRunTime, string DefinitionXml);

/// <summary>État de la politique lue : « unknown » (cfg.json absent, illisible, valeur non booléenne) ne vaut JAMAIS vrai.</summary>
public static class TaskFallbackPolicy
{
    public const string True = "true";
    public const string False = "false";
    public const string Unknown = "unknown";

    /// <summary>
    /// Port de <c>ConvertTo-PestoPolicy</c> (Pesto-Policy.ps1) pour la seule clé <c>AllowPasswordTaskFallback</c> :
    /// défaut V1 = faux ; seule une valeur booléenne JSON vrai active ; une valeur non booléenne ou un cfg.json
    /// absent/illisible rend « unknown » — jamais retombé sur vrai, jamais activé implicitement.
    /// </summary>
    public static string ReadAllowPasswordTaskFallback(string? v1InstallationPath)
    {
        try
        {
            var path = V1Config.ConfigPathOf(v1InstallationPath);
            if (path is null || !File.Exists(path)) return False; // pas de politique lue = défaut V1 : faux
            using var document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
            if (document.RootElement.ValueKind != JsonValueKind.Object) return Unknown;
            if (!document.RootElement.TryGetProperty("POLICY", out var policy)) return False;
            if (policy.ValueKind != JsonValueKind.Object) return Unknown;
            if (!policy.TryGetProperty("AllowPasswordTaskFallback", out var flag)) return False;
            if (flag.ValueKind == JsonValueKind.True) return True;
            if (flag.ValueKind == JsonValueKind.False) return False;
            return Unknown; // ConvertTo-PestoPolicy refuserait cette valeur : ici elle ne vaut jamais vrai
        }
        catch (Pesto.Core.PestoException error) when (error.Code == "config.missing")
        {
            return False;
        }
        catch (Exception)
        {
            return Unknown;
        }
    }
}

/// <summary>Entrées de la décision du repli, toutes observées avant l'appel : décision pure, testable hors Windows.</summary>
public sealed record TaskFallbackGate(
    string Kind,
    bool IsRemote,
    TaskFallbackAccountMode AccountMode,
    string PolicyState,
    int? NativeCode,
    bool WasUncertain);

/// <summary>Décision du repli : autorisation + raison rendue à l'opérateur (les raisons V1 sont reprises mot pour mot).</summary>
public sealed record TaskFallbackDecision(bool Allowed, int Code, string Reason);

/// <summary>
/// Décision pure du repli (port exact du garde V1 de <c>RenameComputer</c> :
/// <c>if(-not $local -and $script:cred -and $script:AllowPasswordTaskFallback -and $nativeFailure -in @(5,1314))</c>).
/// Aucun état, aucune entrée système : ce que les fixtures vérifient, c'est cette table.
/// </summary>
public static class TaskFallback
{
    /// <summary>Seuls ces deux codes de refus confirmé ouvrent le repli (V1). 1326 = identifiants incorrects : jamais.</summary>
    public static readonly int[] FallbackEligibleCodes = [5, 1314];

    /// <summary>Refus confirmés que le script de l'adaptateur rend en « refused » avec le code natif (port V1 5/1314/1326).</summary>
    public static bool IsDefiniteRefusalCode(int? code) => code is 5 or 1314 or 1326;

    public static TaskFallbackDecision Decide(TaskFallbackGate gate)
    {
        if (gate.WasUncertain)
            return new(false, 97, "Aucun repli après un résultat incertain (règle V1) : vérifier avant toute reprise.");
        if (gate.Kind is not ("rename" or "renameMove"))
            return new(false, 21, "Le repli V1 par tâche planifiée est réservé au renommage (port Invoke-RenameComputerTaskFallback) : aucune autre mutation n'emprunte ce chemin.");
        if (!gate.IsRemote)
            return new(false, 21, "Le repli V1 par tâche planifiée est réservé au renommage distant : le renommage local garde Rename-Computer comme seule autorité (port V1).");
        if (gate.AccountMode != TaskFallbackAccountMode.ExplicitAccount)
            return new(false, 21, "Fallback tâche planifiée indisponible en mode Compte Windows sans élévation suffisante : le repli exige un compte AD explicitement saisi (port V1 de $script:cred).");
        if (gate.PolicyState != TaskFallbackPolicy.True)
        {
            var read = gate.PolicyState == TaskFallbackPolicy.Unknown
                ? "POLICY.AllowPasswordTaskFallback non lue de façon fiable dans le cfg.json"
                : "POLICY.AllowPasswordTaskFallback lu « false » (défaut V1)";
            return new(false, 21, "Refus Windows confirmé (" + gate.NativeCode + ") : " + read + " — aucun repli automatique non autorisé ; la politique n'est jamais activée implicitement.");
        }
        if (gate.NativeCode is not int code || !FallbackEligibleCodes.Contains(code))
            return new(false, 21, "Refus Windows confirmé (" + gate.NativeCode + ") : hors des deux refus ouvrant le repli (5 accès refusé, 1314 privilège manquant) — aucun repli automatique non autorisé (port V1 ; 1326 identifiants incorrects ne déclenche jamais le repli).");
        return new(true, 0, "Repli V1 admis : renommage distant, refus confirmé " + code + ", compte AD explicite, politique lue vraie.");
    }

    /// <summary>Port de <c>New-PestoTaskService</c> : DOMAIN\\user, user@domaine ou identifiant court + domaine par défaut.</summary>
    public static (string User, string Domain) SplitAccount(string userName, string defaultDomain)
    {
        var name = (userName ?? "").Trim();
        var backslash = name.IndexOf('\\');
        if (backslash > 0 && backslash < name.Length - 1)
            return (name[(backslash + 1)..], name[..backslash]);
        var at = name.IndexOf('@');
        if (at > 0 && at < name.Length - 1)
            return (name[..at], name[(at + 1)..]);
        return (name, defaultDomain);
    }

    /// <summary>Port de <c>New-PestoRunOnceTaskXml</c> : tâche volontairement SANS déclencheur — seul un Run COM
    /// explicite la lance (un déclencheur passé pouvait être considéré manqué et relancer la tâche tout seul).
    /// Le XML ne contient jamais le mot de passe ; tout est échappé.</summary>
    public static string NewRunOnceTaskXml(string command, string arguments, string userId, string logonType = "Password",
        string runLevel = "HighestAvailable", string description = "Pesto - tâche à la demande")
    {
        if (string.IsNullOrWhiteSpace(command)) throw new ArgumentException("Commande de tâche requise.", nameof(command));
        if (string.IsNullOrWhiteSpace(userId)) throw new ArgumentException("Principal de tâche requis.", nameof(userId));
        if (logonType is not ("Password" or "ServiceAccount")) throw new ArgumentException("Type de connexion hors liste fermée.", nameof(logonType));
        if (runLevel is not ("HighestAvailable" or "Limited")) throw new ArgumentException("Niveau d'exécution hors liste fermée.", nameof(runLevel));
        var cmdX = Escape(command);
        var argX = Escape(arguments);
        var usrX = Escape(userId);
        var descX = Escape(description);
        var logonBlock = logonType == "ServiceAccount" ? "" : "      <LogonType>" + logonType + "</LogonType>\r\n";
        return "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n"
            + "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n"
            + "  <RegistrationInfo>\r\n"
            + "    <Description>" + descX + "</Description>\r\n"
            + "    <Author>Pesto</Author>\r\n"
            + "  </RegistrationInfo>\r\n"
            + "  <Principals>\r\n"
            + "    <Principal id=\"Author\">\r\n"
            + "      <UserId>" + usrX + "</UserId>\r\n"
            + logonBlock + "      <RunLevel>" + runLevel + "</RunLevel>\r\n"
            + "    </Principal>\r\n"
            + "  </Principals>\r\n"
            + "  <Settings>\r\n"
            + "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\r\n"
            + "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\r\n"
            + "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\r\n"
            + "    <AllowHardTerminate>true</AllowHardTerminate>\r\n"
            + "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\r\n"
            + "    <AllowStartOnDemand>true</AllowStartOnDemand>\r\n"
            + "    <Enabled>true</Enabled>\r\n"
            + "    <Hidden>true</Hidden>\r\n"
            + "    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>\r\n"
            + "    <Priority>5</Priority>\r\n"
            + "  </Settings>\r\n"
            + "  <Actions Context=\"Author\">\r\n"
            + "    <Exec>\r\n"
            + "      <Command>" + cmdX + "</Command>\r\n"
            + "      <Arguments>" + argX + "</Arguments>\r\n"
            + "    </Exec>\r\n"
            + "  </Actions>\r\n"
            + "</Task>";
    }

    private static string Escape(string value) => System.Security.SecurityElement.Escape(value) ?? "";

    /// <summary>Port de <c>Get-PestoTaskDefinitionHash</c> : SHA-256 hexadécimal majuscule de la définition UTF-8,
    /// bornée à 128 Ko ; définition absente ou énorme = refus (jamais une empreinte de complaisance).</summary>
    public static string DefinitionHash(string xml)
    {
        if (string.IsNullOrEmpty(xml) || xml.Length > 131072)
            throw new Pesto.Core.PestoException("task.definition", "Définition de tâche absente ou trop volumineuse.");
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(xml)));
    }

    /// <summary>Port du garde d'espace de tâches : <c>^\\Pesto_[A-Za-z0-9_]+$</c>, rien d'autre n'est manipulable.</summary>
    public static bool IsPestoTaskName(string? taskName) =>
        taskName is not null && Regex.IsMatch(taskName, @"^\\Pesto_[A-Za-z0-9_]+$");
}

/// <summary>
/// Preuve durable d'une tâche de repli (port de <c>Set-PestoTaskEvidence</c> : phases Registering → Registered →
/// StartRequested → Started → Finished → Deleted, empreinte de définition, code natif). Écrite sous le dossier GP
/// de l'adaptateur, atomiquement, sans jamais traverser un lien ; l'impossibilité d'écrire une preuve bloque le
/// repli avant la moindre création de tâche.
/// </summary>
public sealed class TaskEvidence
{
    private readonly string root;
    private readonly TimeProvider clock;
    private readonly List<Dictionary<string, object?>> phases = [];
    private string definitionHash = "";
    private long? nativeCode;
    private readonly string kind;
    private readonly string? computer;
    private readonly string? taskName;

    public TaskEvidence(string gpRoot, string receiptId, string taskId, TimeProvider? clock = null,
        string kind = "task-fallback-evidence", string? computer = null, string? taskName = null)
    {
        if (string.IsNullOrWhiteSpace(gpRoot)) throw new ArgumentException("Dossier de preuves requis.", nameof(gpRoot));
        if (!Regex.IsMatch(receiptId, @"^[A-Za-z0-9._-]{1,128}$") || !Regex.IsMatch(taskId, @"^[a-f0-9]{12}$"))
            throw new Pesto.Core.PestoException("task.evidence", "Identifiants de preuve invalides.");
        this.clock = clock ?? TimeProvider.System;
        if (kind is not ("task-fallback-evidence" or "entra-status-evidence" or "windows-proof-evidence" or "restart-request-evidence")) throw new ArgumentException("Type de preuve invalide.");
        this.kind = kind;
        this.computer = computer;
        this.taskName = taskName;
        root = System.IO.Path.Combine(gpRoot, "V2", "tasks");
        FilePath = System.IO.Path.Combine(root, receiptId + "." + taskId + ".json");
        RequireNoReparsePoint(FilePath);
    }

    public string FilePath { get; }

    /// <summary>Port de <c>Set-PestoTaskEvidence</c> : phase inconnue refusée, écriture atomique obligatoire.</summary>
    public void Record(string phase, string? definitionHash = null, long? nativeCode = null)
    {
        if (phase is not ("Registering" or "Registered" or "StartRequested" or "Started" or "Finished" or "ResultSaved" or "ResultDeleted" or "Deleted" or "DeleteFailed"))
            throw new Pesto.Core.PestoException("task.evidence", "Phase de tâche hors liste fermée : " + phase);
        if (definitionHash is not null) this.definitionHash = definitionHash;
        if (nativeCode is not null) this.nativeCode = nativeCode;
        phases.Add(new Dictionary<string, object?>
        {
            ["Phase"] = phase,
            ["Utc"] = clock.GetUtcNow().ToString("o"),
            ["Hash"] = this.definitionHash,
            ["NativeCode"] = this.nativeCode,
        });
        var json = JsonSerializer.Serialize(new Dictionary<string, object?>
        {
            ["Schema"] = 1,
            ["Version"] = "2.0",
            ["Kind"] = kind,
            ["Computer"] = computer,
            ["TaskName"] = taskName,
            ["Phases"] = phases,
        });
        WriteAtomic(FilePath, json);
    }

    /// <summary>Port d'<c>Assert-PestoTaskDefinition</c> : la définition courante doit correspondre à l'empreinte du reçu.</summary>
    public void AssertDefinition(string currentXml)
    {
        if (definitionHash.Length == 0 || TaskFallback.DefinitionHash(currentXml) != definitionHash)
            throw new Pesto.Core.PestoException("task.definition", "La définition de la tâche ne correspond pas au reçu. Aucun lancement ni nettoyage automatique.");
    }

    private static void WriteAtomic(string path, string json)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        RequireNoReparsePoint(path);
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        {
            output.Write(Encoding.UTF8.GetBytes(json));
            output.Flush(flushToDisk: true);
        }
        File.Move(temp, path, overwrite: true);
    }

    private static void RequireNoReparsePoint(string path)
    {
        for (var ancestor = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(path)); ancestor is not null;)
        {
            if (Directory.Exists(ancestor) && (new DirectoryInfo(ancestor).Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Le stockage des preuves de tâche ne peut pas traverser un lien ou une jonction.");
            var next = System.IO.Path.GetDirectoryName(ancestor);
            if (next == ancestor) break;
            ancestor = next;
        }
    }
}

/// <summary>
/// Déroulement complet du repli de renommage (port d'<c>Invoke-RenameComputerTaskFallback</c> +
/// <c>Get-PestoTaskRunResult</c> + <c>New-PestoRenameTaskScript</c>) sur le transport injecté. Aucune dépendance à
/// Windows : le transport réel est fourni par l'adaptateur qualifié, les fixtures injectent le leur. Le credential
/// est acquis par l'appelant, transmis uniquement à <see cref="ITaskSchedulerTransport.Register"/> en mémoire, et
/// doit être purgé par l'appelant en finally.
/// </summary>
public sealed class PestoTaskFallbackRunner
{
    private static readonly long[] UnconfirmedResults = [267008, 267009, 267011];
    private const int MaximumProbeAttempts = 400;

    private readonly ITaskSchedulerTransport transport;
    private readonly string gpRoot;
    private readonly TimeProvider clock;
    private readonly int probeTimeoutSeconds;
    private readonly int pollDelayMilliseconds;

    public PestoTaskFallbackRunner(ITaskSchedulerTransport transport, string gpRoot, TimeProvider? clock = null,
        int probeTimeoutSeconds = 35, int pollDelayMilliseconds = 500)
    {
        this.transport = transport;
        this.gpRoot = gpRoot;
        this.clock = clock ?? TimeProvider.System;
        this.probeTimeoutSeconds = probeTimeoutSeconds;
        this.pollDelayMilliseconds = pollDelayMilliseconds;
    }

    /// <summary>Script interne de la tâche (port de <c>New-PestoRenameTaskScript</c>) : Win32_ComputerSystem.Rename
    /// sous le compte déjà enregistré dans la tâche — aucun secret réinjecté dans le script ; journal cible en lecture
    /// seule pour le diagnostic ; codes de sortie 0/97/43/1 repris de V1.</summary>
    public static string RenameTaskScript(string newName, string localLogPath)
    {
        var newLiteral = PowerShellLiteral(newName);
        var logLiteral = PowerShellLiteral(localLogPath);
        return "$ErrorActionPreference='Stop'\r\n"
            + "$new=" + newLiteral + "\r\n"
            + "$log=" + logLiteral + "\r\n"
            + "try {\r\n"
            + "  New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($log)) -Force | Out-Null\r\n"
            + "  (\"START {0} {1} -> {2}\" -f (Get-Date).ToString('o'),$env:COMPUTERNAME,$new) | Set-Content -LiteralPath $log -Encoding UTF8\r\n"
            + "  # La tâche tourne déjà sous le compte AD saisi dans Pesto avec RunLevel=Highest.\r\n"
            + "  # Pour un appel LOCAL, Win32_ComputerSystem.Rename(NULL,NULL) utilise le contexte\r\n"
            + "  # de l'appelant : aucun secret n'est réinjecté dans ce script.\r\n"
            + "  $cs=Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop\r\n"
            + "  if($null -eq $cs){ throw 'Win32_ComputerSystem introuvable.' }\r\n"
            + "  $ret=$cs.Rename($new,$null,$null)\r\n"
            + "  $rv=if($ret -and $ret.PSObject.Properties['ReturnValue']){[uint32]$ret.ReturnValue}else{[uint32]4294967295}\r\n"
            + "  if($rv -eq [uint32]4294967295){ exit 97 }\r\n"
            + "  if($rv -ne 0){\r\n"
            + "    $rvText=try{(New-Object ComponentModel.Win32Exception([int]$rv)).Message}catch{'erreur Windows/WMI non traduite'}\r\n"
            + "    throw \"Win32_ComputerSystem.Rename a renvoyé le code $rv ($rvText).\"\r\n"
            + "  }\r\n"
            + "  (\"OK {0} renommage WMI confirmé (ReturnValue=0) ; redémarrage requis.\" -f (Get-Date).ToString('o')) | Add-Content -LiteralPath $log -Encoding UTF8\r\n"
            + "  exit 0\r\n"
            + "} catch {\r\n"
            + "  $m=[string]$_.Exception.Message\r\n"
            + "  (\"ERROR {0} {1}: {2}\" -f (Get-Date).ToString('o'),$_.Exception.GetType().FullName,$m) | Add-Content -LiteralPath $log -Encoding UTF8\r\n"
            + "  if($m -match '(?i)(Azure\\s*AD|Microsoft\\s*Entra|nom d.?h[oô]te.*Azure|hostname.*Azure|update.*host.*Entra)'){\r\n"
            + "    \"ENTRA_RENAME_BLOCK\" | Add-Content -LiteralPath $log -Encoding UTF8\r\n"
            + "    exit 43\r\n"
            + "  }\r\n"
            + "  if($m -match '(?i)(RPC|0x800706ba|timed?\\s*out|d.lai|transport)'){exit 97}\r\n"
            + "  exit 1\r\n"
            + "}\r\n";
    }

    /// <summary>Port de <c>ConvertTo-PestoPowerShellLiteral</c>.</summary>
    public static string PowerShellLiteral(string? value) => value is null ? "''" : "'" + value.Replace("'", "''") + "'";

    /// <summary>Déroule le repli complet et rend le résultat brut (le moteur recoupe toujours par relecture annuaire).
    /// Ne relance JAMAIS une tâche déjà lancée : tout doute après envoi est incertain, tâche conservée.</summary>
    public MutationOutcome RunRename(string computer, string newName, PestoAdCredential credential, string domain,
        string planId, string receiptId)
    {
        var taskId = Guid.NewGuid().ToString("N")[..12];
        var taskName = "\\Pesto_Rename_" + taskId;
        if (!TaskFallback.IsPestoTaskName(taskName))
            return new MutationOutcome(MutationStatus.Failed, 21, "Nom de tâche hors espace Pesto : aucune tâche créée.", false);
        // Le principal est le compte tel que saisi (garde V1 : le XML et l'enregistrement portent exactement
        // cred.UserName ; c'est le transport qui décompose DOMAIN\\user ou user@domaine pour la connexion COM).
        // Un identifiant court est qualifié du domaine configuré, comme le fait déjà la connexion V1
        // (Start-PestoLoginAttempt : « seul un identifiant court reçoit le suffixe DNS du domaine cible »).
        var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@')
            ? credential.UserName
            : credential.UserName + "@" + domain;
        var localLogPath = "C:\\ProgramData\\Pesto\\rename_" + taskId + ".log";
        TaskEvidence evidence;
        try
        {
            // Port de la règle « reçu durable avant la commande native » : sans preuve inscriptible, pas de tâche.
            evidence = new TaskEvidence(gpRoot, receiptId, taskId, clock);
            evidence.Record("Registering");
        }
        catch (Exception error)
        {
            return new MutationOutcome(MutationStatus.Failed, 96,
                Short("La preuve de tâche n'a pas pu être enregistrée : aucune tâche créée. " + error.Message), false);
        }
        var inner = RenameTaskScript(newName, localLogPath);
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(inner));
        var xml = TaskFallback.NewRunOnceTaskXml(
            "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + encoded,
            principal,
            "Password", "HighestAvailable", "Pesto - fallback RenameComputer");
        var hash = TaskFallback.DefinitionHash(xml);
        var keepTask = false;
        var runRequested = false;
        try
        {
            try
            {
                transport.Register(computer, taskName, xml, principal, credential.TakePassword());
            }
            catch (Exception error)
            {
                return new MutationOutcome(MutationStatus.Failed, 21,
                    Short("Fallback tâche planifiée : création KO : " + error.Message), false);
            }
            evidence.Record("Registered", hash);
            try
            {
                evidence.Record("StartRequested");
                runRequested = true;
                transport.Run(computer, taskName);
                evidence.Record("Started");
            }
            catch (Exception error)
            {
                if (runRequested)
                {
                    keepTask = true;
                    return new MutationOutcome(MutationStatus.Uncertain, 97,
                        Short("Résultat de la tâche inconnu après lancement : " + error.Message + " La tâche est conservée pour diagnostic, jamais relancée automatiquement."), false);
                }
                return new MutationOutcome(MutationStatus.Failed, 21, Short("Fallback tâche planifiée : " + error.Message), false);
            }
            var probe = WaitUntilFinished(computer, taskName, evidence, out var probeFailure);
            if (probeFailure is not null)
            {
                // Port V1 : résultat non confirmé = ÉTAT INDÉTERMINÉ, la tâche est CONSERVÉE pour diagnostic.
                keepTask = true;
                return probeFailure;
            }
            var tail = SafeTail(computer, localLogPath);
            var tailMessage = string.IsNullOrEmpty(tail) ? "" : " | log cible : " + tail;
            var result = probe!.LastTaskResult;
            if (result == 0)
                return new MutationOutcome(MutationStatus.PendingRestart, 20,
                    Short("\"" + computer + "\" renommé en \"" + newName + "\" via tâche élevée" + tailMessage + " Redémarrage à planifier par l'opérateur ; Pesto ne redémarre rien."), true);
            if (result == 97)
                return new MutationOutcome(MutationStatus.Uncertain, 97,
                    "La tâche ne peut pas confirmer le résultat WMI : à vérifier avant toute reprise, jamais relancée automatiquement.", false);
            if (result == 43)
                return new MutationOutcome(MutationStatus.Failed, 21,
                    Short("Microsoft Entra/Azure AD bloque la mise à jour du nom d'hôte pendant le renommage élevé." + tailMessage), false);
            return new MutationOutcome(MutationStatus.Failed, 21,
                Short("Fallback tâche planifiée terminé en erreur : " + result + tailMessage), false);
        }
        catch (Pesto.Core.PestoException error) when (error.Code == "task.definition")
        {
            // Port d'Assert-PestoTaskDefinition : définition divergente = aucun lancement ni nettoyage automatique.
            keepTask = true;
            return new MutationOutcome(MutationStatus.Uncertain, 97,
                "La définition de la tâche ne correspond pas au reçu. Aucun lancement ni nettoyage automatique. La tâche est conservée pour diagnostic.", false);
        }
        finally
        {
            if (!keepTask)
            {
                try
                {
                    transport.Delete(computer, taskName);
                    try { evidence.Record("Deleted"); } catch (Exception) { /* la suppression est confirmée ; la preuve finale n'inverse pas le résultat */ }
                }
                catch (Exception error)
                {
                    // La suppression échoue (absence non confirmée) : la tâche reste, le résultat observé est conservé,
                    // et l'événement est tracé dans la preuve (port V1 : le nettoyage ne transforme jamais un résultat).
                    try { evidence.Record("DeleteFailed"); } catch (Exception) { }
                    System.Diagnostics.Debug.WriteLine("Échec de nettoyage de tâche de repli : " + error.Message);
                }
            }
        }
    }

    private TaskProbeResult? WaitUntilFinished(string computer, string taskName, TaskEvidence evidence, out MutationOutcome? failure)
    {
        failure = null;
        var deadline = clock.GetUtcNow().AddSeconds(probeTimeoutSeconds);
        // Garde d'itérations en plus de l'horloge : une horloge qui n'avance pas (harnais de test) ne doit jamais
        // boucler sans fin ; la sonde rend alors l'incertain, exactement comme l'expiration du délai V1.
        for (var attempt = 0; attempt < MaximumProbeAttempts; attempt++)
        {
            try
            {
                var probe = transport.Probe(computer, taskName);
                evidence.AssertDefinition(probe.DefinitionXml);
                if (probe.State == 3 && probe.LastRunTime is { } lastRun && lastRun.Year >= 2000 && !UnconfirmedResults.Contains(probe.LastTaskResult))
                {
                    evidence.Record("Finished", nativeCode: probe.LastTaskResult);
                    return probe;
                }
            }
            catch (Pesto.Core.PestoException error) when (error.Code == "task.definition")
            {
                throw; // remonte au bloc definition de RunRename : tâche conservée, jamais nettoyée
            }
            catch (Exception)
            {
                // Port V1 : « Résultat de tâche momentanément inaccessible » — on continue à sonder jusqu'au délai.
            }
            if (clock.GetUtcNow() >= deadline) break;
            if (pollDelayMilliseconds > 0) Thread.Sleep(pollDelayMilliseconds);
        }
        failure = new MutationOutcome(MutationStatus.Uncertain, 97,
            "ÉTAT INDÉTERMINÉ : la tâche de renommage n'est pas confirmée terminée sous " + probeTimeoutSeconds
            + " s. La file doit être arrêtée avant toute autre mutation ; la tâche est conservée pour diagnostic, jamais relancée automatiquement.", false);
        return null;
    }

    private string? SafeTail(string computer, string localLogPath)
    {
        try { return transport.ReadTaskLogTail(computer, localLogPath); }
        catch (Exception) { return null; }
    }

    private static string Short(string? text)
    {
        var trimmed = new string((text ?? "").Where(c => !char.IsControl(c)).ToArray()).Trim();
        if (trimmed.Length == 0) return "Aucun détail fourni.";
        return trimmed.Length > 300 ? trimmed[..300] : trimmed;
    }
}
