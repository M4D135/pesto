using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>
/// Repli authentifié V1 par tâche planifiée sous compte AD (SECURE_FALLBACK_REQUIRED.md du 24/10) — port des sources
/// V1 lues en entier (Pesto-Operations.ps1 RenameComputer 1257-1267, Invoke-RenameComputerTaskFallback,
/// New-PestoTaskService, New-PestoRunOnceTaskXml, Get-PestoTaskRunResult, Set-PestoTaskEvidence,
/// Assert-PestoTaskDefinition, Get-PestoTaskDefinitionHash, Pesto-Authentication.ps1, Pesto-Policy.ps1).
/// Tout est vérifié sur fixtures : la décision pure (table exacte du garde V1), la lecture de
/// POLICY.AllowPasswordTaskFallback (défaut faux, jamais activé implicitement), le XML sans déclencheur, l'empreinte
/// de définition, le déroulement complet sur transport factice (succès, incertain avec tâche conservée et AUCUN rejeu,
/// divergence de définition, blocage Entra), les preuves durables et l'hygiène des secrets (le mot de passe n'apparaît
/// que dans l'appel Register en mémoire — jamais dans le XML, les preuves, les messages ni le payload).
/// Ces tests échouent réellement si le repli redevenait un refus nommé ou une valeur constante : la décision « admis »
/// et le résultat « PendingRestart » du runner sont exigés, pas un message. Aucune exécution PowerShell, aucune écriture
/// AD, aucune tâche réelle depuis ces tests — le transport COM réel n'est injecté que par le harnais de qualification.
/// </summary>
internal sealed class TaskFallbackTests
{
    private const string Computer = "P111301PAINF009";
    private const string NewName = "P111301PAINF010";
    private const string Domain = "example.local";
    private const string Secret = "MotDePasse-AD-TRÈS-secret-42!";

    // ---- fixtures ----------------------------------------------------------------------------

    private sealed class FakeTaskTransport : ITaskSchedulerTransport
    {
        public List<string> Calls = [];
        public string? RegisteredXml;
        public string? RegisteredPrincipal;
        public string? RegisteredPassword;
        public string? RegisteredTaskName;
        public int State = 3;
        public long Result = 0;
        public DateTimeOffset? LastRun = new(2026, 10, 24, 8, 0, 0, TimeSpan.Zero);
        public string? TamperXml;
        public bool ThrowOnRegister;
        public bool ThrowOnRun;
        public bool DeleteNotConfirmed;
        public string? Tail = "OK 2026-10-24 renommage WMI confirmé (ReturnValue=0)";

        public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal)
        {
            Calls.Add("register");
            if (!TaskFallback.IsPestoTaskName(taskName)) throw new ArgumentException("Nom de tâche hors espace Pesto (le fake refuse ce le transport réel refuserait).");
            if (string.IsNullOrEmpty(computer)) throw new ArgumentException("Cible vide.");
            RegisteredTaskName = taskName;
            RegisteredXml = xml;
            RegisteredPrincipal = principal;
            RegisteredPassword = passwordForPrincipal;
            if (ThrowOnRegister) throw new InvalidOperationException("Registre COM refusé (fixture).");
        }

        public void Run(string computer, string taskName)
        {
            Calls.Add("run");
            if (!TaskFallback.IsPestoTaskName(taskName)) throw new ArgumentException("Nom de tâche hors espace Pesto.");
            if (ThrowOnRun) throw new InvalidOperationException("Lancement refusé après envoi (fixture).");
        }

        public TaskProbeResult Probe(string computer, string taskName)
        {
            Calls.Add("probe");
            return new TaskProbeResult(State, Result, LastRun, TamperXml ?? RegisteredXml ?? "<Task/>");
        }

        public void Delete(string computer, string taskName)
        {
            Calls.Add("delete");
            if (DeleteNotConfirmed) throw new InvalidOperationException("La suppression de la tâche n'est pas confirmée par relecture (fixture).");
        }

        public string? ReadTaskLogTail(string computer, string localLogPath) => Tail;
    }

    private sealed class FakeCredentialSource : ITaskFallbackCredentialSource
    {
        public TaskFallbackAccountMode Mode { get; set; }
        public int AcquireCount;
        public PestoAdCredential? LastIssued;

        public FakeCredentialSource(TaskFallbackAccountMode mode = TaskFallbackAccountMode.ExplicitAccount) => Mode = mode;
        public string? DisplayUserName => "EXAMPLE\\admin-postes";

        public PestoAdCredential? AcquireForFallback(string computer, string? newName, string operationId)
        {
            AcquireCount++;
            if (Mode != TaskFallbackAccountMode.ExplicitAccount) return null;
            LastIssued = new PestoAdCredential("EXAMPLE\\admin-postes", Secret);
            return LastIssued;
        }
    }

    private static PestoTaskFallbackRunner Runner(FakeTaskTransport transport, string gpRoot) =>
        new(transport, gpRoot, new FixedClock(), probeTimeoutSeconds: 2, pollDelayMilliseconds: 0);

    private static string RootWithPolicy(string policyFragment) =>
        LiveTestConfig.Write("{\"Configured\": true, \"POLICY\": { \"Schema\": 1" + (policyFragment.Length == 0 ? "" : ", " + policyFragment) + " } }");

    // ---- lecture de la politique (port ConvertTo-PestoPolicy) ---------------------------------

    [Test]
    public void PolicyFollowsTheV1ReadingAndIsNeverEnabledImplicitly()
    {
        Check.Equal("false", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(RootWithPolicy("")),
            "POLICY sans la clé = défaut V1 : faux");
        Check.Equal("true", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(RootWithPolicy("\"AllowPasswordTaskFallback\": true")),
            "Seule une valeur booléenne JSON vraie active le repli");
        Check.Equal("false", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(RootWithPolicy("\"AllowPasswordTaskFallback\": false")),
            "Booléen JSON faux : refus nommé");
        Check.Equal("unknown", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(RootWithPolicy("\"AllowPasswordTaskFallback\": \"true\"")),
            "Texte « true » : ConvertTo-PestoPolicy refuserait cette valeur — ici « unknown », JAMAIS retombé sur vrai");
        Check.Equal("unknown", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(RootWithPolicy("\"AllowPasswordTaskFallback\": 1")),
            "Nombre au lieu d'un booléen : unknown, jamais converti en vrai");
        Check.Equal("unknown", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(LiveTestConfig.Write("{ pas du JSON ")),
            "cfg.json illisible : unknown — le repli reste fermé");
        Check.Equal("false", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(null),
            "Aucune installation V1 : défaut V1 faux, jamais une politique inventée");
        Check.Equal("false", TaskFallbackPolicy.ReadAllowPasswordTaskFallback(Path.Combine(Path.GetTempPath(), "pesto-absent-" + Guid.NewGuid().ToString("N"))),
            "cfg.json absent : défaut V1 faux");
    }

    // ---- décision pure : table exacte du garde V1 ---------------------------------------------

    [Test]
    public void DecisionTableIsTheExactV1Guard()
    {
        var ok = new TaskFallbackGate("rename", true, TaskFallbackAccountMode.ExplicitAccount, "true", 5, false);
        Check.True(TaskFallback.Decide(ok).Allowed, "Repli admis exactement quand V1 l'admet : distant + compte explicite + politique vraie + refus 5");
        Check.True(TaskFallback.Decide(ok with { NativeCode = 1314 }).Allowed, "1314 (privilège manquant) ouvre aussi le repli, comme V1");
        Check.False(TaskFallback.Decide(ok with { NativeCode = 1326 }).Allowed, "1326 identifiants incorrects ne déclenche JAMAIS le repli (V1)");
        Check.True(TaskFallback.Decide(ok with { NativeCode = 1326 }).Reason.Contains("1326", StringComparison.Ordinal),
            "Le refus de 1326 est nommé, pas un refus plat");
        Check.False(TaskFallback.Decide(ok with { NativeCode = null }).Allowed, "Sans code natif confirmé, aucune décision d'ouverture");
        Check.False(TaskFallback.Decide(ok with { WasUncertain = true }).Allowed, "Aucun repli après un résultat incertain (règle V1)");
        Check.Contains("incertain", TaskFallback.Decide(ok with { WasUncertain = true }).Reason, "La règle V1 est dite dans la raison");
        Check.False(TaskFallback.Decide(ok with { Kind = "join" }).Allowed, "Le repli V1 est réservé au renommage (port Invoke-RenameComputerTaskFallback)");
        Check.False(TaskFallback.Decide(ok with { Kind = "move" }).Allowed, "Aucun repli pour un déplacement");
        Check.False(TaskFallback.Decide(ok with { IsRemote = false }).Allowed, "Le renommage local garde Rename-Computer comme seule autorité (V1)");
        var sso = TaskFallback.Decide(ok with { AccountMode = TaskFallbackAccountMode.SessionSso });
        Check.False(sso.Allowed, "Mode Compte Windows (SSO) : repli indisponible, comme en V1 où $script:cred est null");
        Check.Contains("Compte Windows", sso.Reason, "La raison V1 « Fallback tâche planifiée indisponible en mode Compte Windows » est rendue");
        var off = TaskFallback.Decide(ok with { PolicyState = "false" });
        Check.False(off.Allowed, "Politique lue false : aucun repli automatique non autorisé");
        Check.Contains("jamais activée implicitement", off.Reason, "La raison dit que la politique n'est jamais activée implicitement");
        var unknown = TaskFallback.Decide(ok with { PolicyState = "unknown" });
        Check.False(unknown.Allowed, "Politique non lue de façon fiable : le repli reste fermé");
        Check.Contains("non lue de façon fiable", unknown.Reason, "Le refus distingue « non lue » de « lu false », jamais un silence");
    }

    // ---- XML et empreinte (port New-PestoRunOnceTaskXml / Get-PestoTaskDefinitionHash) ---------

    [Test]
    public void TaskXmlHasNoTriggerAndCarriesNoSecret()
    {
        var xml = TaskFallback.NewRunOnceTaskXml("powershell.exe", "-NoProfile -EncodedCommand AAA=", "admin@example.local",
            "Password", "HighestAvailable", "Pesto - <fallback> & test");
        Check.True(!xml.Contains("<Triggers", StringComparison.Ordinal) && !xml.Contains("TimeTrigger", StringComparison.Ordinal),
            "Tâche volontairement SANS déclencheur : seul un Run explicite la lance (leçon V1 du déclencheur passé considéré manqué)");
        Check.Contains("<LogonType>Password</LogonType>", xml, "Connexion sous le compte saisi (LogonType Password de V1)");
        Check.Contains("<RunLevel>HighestAvailable</RunLevel>", xml, "Élévation maximale sur la cible, comme V1");
        Check.Contains("<UserId>admin@example.local</UserId>", xml, "Le principal est le compte saisi");
        Check.Contains("&lt;fallback&gt; &amp; test", xml, "Tout est échappé (port SecurityElement.Escape)");
        Check.Contains("<ExecutionTimeLimit>PT10M</ExecutionTimeLimit>", xml, "Borne d'exécution PT10M reprise de V1");
        Check.True(!xml.Contains(Secret, StringComparison.Ordinal), "Le XML ne contient jamais le mot de passe");
        Check.True(!xml.Contains("MotDePasse", StringComparison.OrdinalIgnoreCase), "Aucun secret, même de fixture, n'entre dans la définition");
    }

    [Test]
    public void DefinitionHashFollowsV1()
    {
        var hash = TaskFallback.DefinitionHash("<Task>x</Task>");
        Check.Equal(64, hash.Length, "Empreinte SHA-256 hexadécimale (port Get-PestoTaskDefinitionHash)");
        Check.Equal(hash, TaskFallback.DefinitionHash("<Task>x</Task>"), "Empreinte stable : la relecture compare la même définition");
        Check.True(hash == hash.ToUpperInvariant(), "Hexadécimal majuscule, comme BitConverter de V1");
        Check.True(hash != TaskFallback.DefinitionHash("<Task>y</Task>"), "Deux définitions différentes, deux empreintes : la divergence est détectable");
        Check.Pesto(() => TaskFallback.DefinitionHash(""), "task.definition", "Définition absente refusée, jamais une empreinte de complaisance");
        Check.Pesto(() => TaskFallback.DefinitionHash(new string('x', 131073)), "task.definition", "Définition trop volumineuse refusée (borne V1 128 Ko)");
    }

    [Test]
    public void AccountSplitFollowsNewPestoTaskService()
    {
        Check.Equal(("admin", "EXAMPLE"), TaskFallback.SplitAccount("EXAMPLE\\admin", Domain), "DOMAIN\\user");
        Check.Equal(("admin", "example.local"), TaskFallback.SplitAccount("admin@example.local", Domain), "user@domaine");
        Check.Equal(("admin", Domain), TaskFallback.SplitAccount("admin", Domain), "identifiant court + domaine configuré");
    }

    // ---- déroulement complet sur transport factice ---------------------------------------------

    [Test]
    public void FallbackSuccessRunsTheWholeV1SequenceAndKeepsNoTaskBehind()
    {
        var transport = new FakeTaskTransport();
        var gp = Harness.IsolatedGpRoot();
        var credential = new PestoAdCredential("EXAMPLE\\admin-postes", Secret);
        var outcome = Runner(transport, gp).RunRename(Computer, NewName, credential, Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.PendingRestart, outcome.Status, "Repli réussi = renommage accepté avec redémarrage à planifier (port exit 20 V1) — jamais un refus nommé");
        Check.Equal(20, outcome.Code, "Code 20 de V1 pour le repli de renommage confirmé");
        Check.True(outcome.RestartRequired, "Le redémarrage est annoncé, jamais déclenché par Pesto");
        Check.Contains("tâche élevée", outcome.Message, "Le message dit l'origine réelle (tâche élevée sous compte AD)");
        Check.Contains("log cible", outcome.Message, "Le tail du journal cible est joint (port Get-PestoRemoteTaskLogTail)");
        Check.Equal("register", transport.Calls[0], "Création d'abord");
        Check.Equal("run", transport.Calls[1], "Puis lancement explicite (aucun déclencheur)");
        Check.Contains("probe", string.Join(",", transport.Calls), "Sondage numérique du résultat");
        Check.Equal("delete", transport.Calls[^1], "Tâche supprimée après succès confirmé");
        Check.True(transport.RegisteredTaskName is not null && TaskFallback.IsPestoTaskName(transport.RegisteredTaskName),
            "La tâche créée porte un nom de l'espace fermé \\Pesto_... (rien d'autre n'est manipulable)");
        Check.Contains("\\Pesto_Rename_", transport.RegisteredTaskName, "Préfixe du renommage, comme V1");
        Check.Equal("EXAMPLE\\admin-postes", transport.RegisteredPrincipal, "Le principal enregistré est exactement le compte saisi (garde V1 : « Principal de tâche différent du compte Pesto » refusé)");
        Check.Equal(Secret, transport.RegisteredPassword, "Le mot de passe ne voyage que dans l'appel d'enregistrement, en mémoire");
        Check.True(!transport.RegisteredXml!.Contains(Secret, StringComparison.Ordinal), "Jamais dans le XML");
        var evidence = Directory.GetFiles(Path.Combine(gp, "V2", "tasks"), "*.json");
        Check.Equal(1, evidence.Length, "Preuve durable écrite (port Set-PestoTaskEvidence)");
        var text = File.ReadAllText(evidence[0]);
        foreach (var phase in new[] { "Registering", "Registered", "StartRequested", "Started", "Finished", "Deleted" })
            Check.Contains(phase, text, "Phase de preuve portée de V1 : " + phase);
        Check.True(!text.Contains(Secret, StringComparison.Ordinal), "Aucun secret dans la preuve durable");
        Check.True(!text.Contains("admin-postes", StringComparison.Ordinal), "La preuve ne recopie pas le compte, seulement les phases et l'empreinte");
    }

    [Test]
    public void UncertainResultKeepsTheTaskAndNeverRerunsIt()
    {
        var transport = new FakeTaskTransport { State = 3, Result = 267009 };
        var outcome = Runner(transport, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Uncertain, outcome.Status, "267009 = exécution non confirmée : incertain, comme la sonde V1");
        Check.Contains("INDÉTERMINÉ", outcome.Message, "Le message V1 « ÉTAT INDÉTERMINÉ » est rendu");
        Check.Contains("conservée", outcome.Message, "La tâche est conservée pour diagnostic");
        Check.Contains("jamais relancée", outcome.Message, "Aucun rejeu automatique, jamais");
        Check.Equal(1, transport.Calls.Count(c => c == "run"), "Le lancement n'est demandé qu'une seule fois : aucun rejeu");
        Check.False(transport.Calls.Contains("delete"), "Aucune suppression quand le résultat est incertain");
    }

    [Test]
    public void RunFailureAfterSendIsUncertainAndKeepsTheTask()
    {
        var transport = new FakeTaskTransport { ThrowOnRun = true };
        var outcome = Runner(transport, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Uncertain, outcome.Status, "Une exception après la demande de lancement ne prouve pas que la tâche n'a pas démarré (règle V1)");
        Check.False(transport.Calls.Contains("delete"), "Tâche conservée après un doute sur le lancement");
        Check.Equal(1, transport.Calls.Count(c => c == "run"), "Jamais relancée automatiquement");
    }

    [Test]
    public void CreateFailureIsAProuvenRefusalBeforeAnySend()
    {
        var transport = new FakeTaskTransport { ThrowOnRegister = true };
        var outcome = Runner(transport, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Failed, outcome.Status, "La création n'a jamais abouti : refus prouvé, rien n'a quitté le poste");
        Check.False(transport.Calls.Contains("run"), "Aucun lancement après une création refusée");
    }

    [Test]
    public void DefinitionDivergenceStopsEverythingWithoutCleanup()
    {
        var transport = new FakeTaskTransport { TamperXml = "<Task>tamponnée</Task>" };
        var outcome = Runner(transport, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Uncertain, outcome.Status, "Port Assert-PestoTaskDefinition : définition divergente = stop");
        Check.Contains("ne correspond pas au reçu", outcome.Message, "La raison V1 est rendue mot pour mot");
        Check.False(transport.Calls.Contains("delete"), "Aucun nettoyage automatique sur une définition douteuse");
    }

    [Test]
    public void EntraBlockAndUnknownCodesAreNamedAsInV1()
    {
        var entra = Runner(new FakeTaskTransport { Result = 43 }, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Failed, entra.Status, "43 = blocage Entra confirmé : refus nommé, pas un échec plat");
        Check.Contains("Entra", entra.Message, "La cause Entra/Azure AD est nommée (port du code 43 V1)");
        var other = Runner(new FakeTaskTransport { Result = 5 }, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Failed, other.Status, "Code inattendu rendu par la tâche = erreur terminée, lue numériquement");
        Check.Contains("terminé en erreur", other.Message, "Le code brut est cité, jamais maquillé en succès");
    }

    [Test]
    public void UnwritableEvidenceBlocksTheTaskBeforeAnyCreation()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-evidence-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "V2"), "obstacle"); // « V2 » est un fichier : le dossier de preuves est inscriptible nulle part
        var transport = new FakeTaskTransport();
        var outcome = Runner(transport, root)
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.Failed, outcome.Status, "Sans preuve durable inscriptible, aucune tâche n'est créée (port « reçu avant la commande native »)");
        Check.Contains("preuve", outcome.Message, "Le refus dit que la preuve durable est obligatoire");
        Check.False(transport.Calls.Contains("register"), "Aucune création de tâche sans preuve");
    }

    [Test]
    public void DeleteNotConfirmedNeverInvertsTheObservedResult()
    {
        var transport = new FakeTaskTransport { DeleteNotConfirmed = true };
        var outcome = Runner(transport, Harness.IsolatedGpRoot())
            .RunRename(Computer, NewName, new PestoAdCredential("EXAMPLE\\admin-postes", Secret), Domain, "plan-1", "receipt-1");
        Check.Equal(MutationStatus.PendingRestart, outcome.Status, "Le nettoyage ne transforme jamais un renommage observé en échec (port V1)");
        Check.True(transport.Calls.Contains("delete"), "La suppression a bien été tentée");
    }

    // ---- hygiène des secrets --------------------------------------------------------------------

    [Test]
    public void CredentialIsMemoryOnlyMaskedAndPurged()
    {
        var credential = new PestoAdCredential("EXAMPLE\\admin-postes", Secret);
        Check.Equal(Secret, credential.TakePassword(), "Le transport lit le secret tant qu'il est disponible");
        credential.Clear();
        Check.False(credential.IsAvailable, "Purgé, le secret n'est plus disponible");
        var refused = false;
        try { credential.TakePassword(); }
        catch (InvalidOperationException) { refused = true; }
        Check.True(refused, "Après purge, aucune relecture du secret n'est possible (durée de conservation bornée à l'opération)");
        credential.Dispose(); // idempotent
    }

    [Test]
    public void CredentialToStringNeverLeaksThePassword()
    {
        var credential = new PestoAdCredential("EXAMPLE\\admin-postes", Secret);
        Check.True(!credential.ToString().Contains(Secret, StringComparison.Ordinal), "ToString ne rend jamais le mot de passe");
        Check.Contains("masqué", credential.ToString(), "ToString nomme explicitement le masquage");
        var json = JsonSerializer.Serialize(new { credential });
        Check.True(!json.Contains(Secret, StringComparison.Ordinal), "Une sérialisation naïve ne divulgue pas le secret (le champ est privé)");
    }

    [Test]
    public void AdapterDisclosesTheFallbackStateItActuallyRead()
    {
        var onRoot = RootWithPolicy("\"AllowPasswordTaskFallback\": true");
        var on = new PowerShellMutationGateway(onRoot, new FakeCredentialSource());
        Check.Contains("politique lue « true »", on.Description, "L'adaptateur déclare la politique réellement lue (le tableau de bord la montre)");
        Check.Contains("compte « explicite »", on.Description, "Il déclare que le compte explicite est disponible pour le repli");
        Check.Equal("true", on.FallbackPolicyState, "État lu exposé tel quel");
        var off = new PowerShellMutationGateway(RootWithPolicy(""));
        Check.Contains("politique lue « false »", off.Description, "Sans politique lue vraie, l'adaptateur déclare le repli fermé");
        Check.Contains("session SSO", off.Description, "Sans source de compte, le mode déclaré est la session SSO — repli refusé comme en V1");
        Check.Equal("false", off.FallbackPolicyState, "Défaut V1 exposé");
    }

    [Test]
    public void RenameTaskScriptIsTheV1PortWithoutAnySecret()
    {
        var script = PestoTaskFallbackRunner.RenameTaskScript(NewName, "C:\\ProgramData\\Pesto\\rename_abc.log");
        Check.Contains("Win32_ComputerSystem", script, "Le repli exécute Win32_ComputerSystem.Rename, comme la tâche V1");
        Check.Contains("$cs.Rename($new,$null,$null)", script, "Rename(NULL,NULL) : le compte est celui de la tâche, aucun secret réinjecté");
        Check.Contains("ENTRA_RENAME_BLOCK", script, "La détection du blocage Entra est portée (exit 43)");
        Check.Contains("exit 97", script, "Le résultat WMI non confirmé sort en 97 (incertain), comme V1");
        Check.True(!script.Contains(Secret, StringComparison.Ordinal) && !script.Contains("password", StringComparison.OrdinalIgnoreCase),
            "Aucun secret dans le script interne de la tâche");
        Check.Equal("''", PestoTaskFallbackRunner.PowerShellLiteral(null), "Littéral PowerShell nul = chaîne vide échappée");
        Check.Equal("'d''artagnan'", PestoTaskFallbackRunner.PowerShellLiteral("d'artagnan"), "Quote doublée (port ConvertTo-PestoPowerShellLiteral)");
    }
}
