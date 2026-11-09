using System.Text;
using System.Text.Json.Nodes;
using System.Xml.Linq;

namespace Pesto.Engine.Tests;

internal sealed class RemoteRestartTaskTests
{
    private const string Computer = "P111301PAINF009", Secret = "fixture-restart-secret-never-persisted";
    private static RestartCommand Command(bool local = false) => new("restart-1234567890abcdef1234567890abcdef", "receipt-restart-task",
        new string('a', 64), "plan-restart", Computer, "P111301PAINF010", "example.local",
        "11111111-1111-1111-1111-111111111111", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        new FixedClock().GetUtcNow().AddHours(-1), local, new FixedClock().GetUtcNow(), "rename", AuthorizationConfigurationSha256: new string('b', 64));

    private sealed class Transport(string root) : ISystemDiagnosticTaskTransport
    {
        public string Xml = ""; public int Registers, Runs, Deletes;
        public bool LostRunReply, TamperBeforeRun, TamperAfterRun, NoRunTime, Active, AlreadyRun, CleanupFailure;
        public long Code;
        private bool ran;
        public void RegisterSystem(string computer, string taskName, string xml, string principal, string password)
        {
            Check.Equal("Registering", LastPhase(root), "Intention durable avant création de tâche");
            Check.Equal(Computer, computer, "Cible exacte");
            Check.Equal(RemoteRestartTask.TaskName(Command()), taskName, "Nom possédé et unique");
            Check.Equal("EXAMPLE\\operator", principal, "Connexion avec le compte explicite");
            Check.Equal(Secret, password, "Secret uniquement dans le transport en mémoire");
            Registers++; Xml = xml;
        }
        public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal) =>
            throw new TestFailureException("Le redémarrage distant doit utiliser une tâche SYSTEM.");
        public void Run(string computer, string taskName)
        {
            Check.Equal("StartRequested", LastPhase(root), "Demande durable avant Run");
            Runs++; ran = true;
            if (LostRunReply) throw new IOException("Réponse perdue après lancement.");
        }
        public TaskProbeResult Probe(string computer, string taskName) => new(ran && Active ? 4 : 3, Code,
            AlreadyRun || ran && !NoRunTime ? new FixedClock().GetUtcNow() : null,
            !ran && TamperBeforeRun || ran && TamperAfterRun ? Xml.Replace("S-1-5-18", "S-1-5-19", StringComparison.Ordinal) : Xml);
        public void Delete(string computer, string taskName)
        {
            Check.Equal(Runs == 0 ? "Registered" : "Finished", LastPhase(root), "Tâche jamais lancée ou fin prouvée avant suppression");
            Deletes++;
            if (CleanupFailure) throw new IOException("Suppression non confirmée.");
        }
        public string? ReadTaskLogTail(string computer, string localLogPath) => throw new TestFailureException("Aucun chemin SMB libre pour le redémarrage.");
    }

    private static string Root() => Path.Combine(Path.GetTempPath(), "pesto-restart-task-" + Guid.NewGuid().ToString("N"));
    private static JsonNode Evidence(string root) => JsonNode.Parse(File.ReadAllText(Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Single()))!;
    private static string LastPhase(string root) => Evidence(root)["Phases"]!.AsArray()[^1]!["Phase"]!.GetValue<string>();
    private static RestartNativeResult Run(Transport transport, string root, bool local = false)
    {
        using var credential = new PestoAdCredential("EXAMPLE\\operator", Secret);
        return new RemoteRestartTask(transport, root, new FixedClock(), 1, 0).Run(Command(local), credential);
    }
    private static void Cleanup(string root) { if (Directory.Exists(root)) Directory.Delete(root, true); else if (File.Exists(root)) File.Delete(root); }

    [Test]
    public void SystemTaskIsOneShotDurableAndAcceptanceDoesNotClaimCompletedBoot()
    {
        var root = Root(); var transport = new Transport(root);
        try
        {
            var result = Run(transport, root);
            Check.Equal("accepted", result.Status, "Commande acceptée seulement");
            Check.Contains("reste inchangé", result.Message, "Le résultat métier demeure en attente sans résolution supposée");
            Check.Equal(1, transport.Registers, "Une seule création"); Check.Equal(1, transport.Runs, "Un seul Run");
            Check.Equal(1, transport.Deletes, "Nettoyage après fin prouvée");
            var evidence = Evidence(root);
            Check.Equal("restart-request-evidence", evidence["Kind"]!.GetValue<string>(), "Preuve distincte du reçu métier");
            Check.Equal("Deleted", LastPhase(root), "Nettoyage durable");
            Check.Contains("<UserId>S-1-5-18</UserId>", transport.Xml, "SYSTEM explicite");
            Check.False(transport.Xml.Contains("<Triggers>", StringComparison.Ordinal), "Aucune répétition par déclencheur");
            var xml = XDocument.Parse(transport.Xml); var ns = xml.Root!.Name.Namespace;
            var arguments = xml.Descendants(ns + "Arguments").Single().Value;
            var source = Encoding.Unicode.GetString(Convert.FromBase64String(arguments.Split("-EncodedCommand ", StringSplitOptions.None)[1]));
            Check.Equal(ReceiptRestartScript.RemoteSource(Command()), source, "Script effectivement remis à la tâche");
            Check.Contains("Restart-Computer -ErrorAction Stop", source, "Commande sans forçage");
            Check.False(source.Contains(" -Force", StringComparison.OrdinalIgnoreCase), "Aucun Force");
            Check.False(transport.Xml.Contains(Secret, StringComparison.Ordinal) || evidence.ToJsonString().Contains(Secret, StringComparison.Ordinal), "Aucun secret dans XML ou preuve");
        }
        finally { Cleanup(root); }
    }

    [Test]
    public void LostRunReplyIsUncertainWithoutDeletionOrSecondRequest()
    {
        var root = Root(); var transport = new Transport(root) { LostRunReply = true };
        try
        {
            Check.Equal("uncertain", Run(transport, root).Status, "Le poste peut redémarrer malgré une réponse perdue");
            Check.Equal(1, transport.Runs, "Pas de rejeu"); Check.Equal(0, transport.Deletes, "Tâche possiblement active conservée");
            Check.Equal("StartRequested", LastPhase(root), "Frontière atteinte conservée");
        }
        finally { Cleanup(root); }
    }

    [Test]
    public void ChangedOrPreviouslyRunTasksAreNeverLaunchedOrRemovedAsOwned()
    {
        for (var variant = 0; variant < 3; variant++)
        {
            var root = Root(); var transport = new Transport(root)
            { TamperBeforeRun = variant == 0, TamperAfterRun = variant == 1, AlreadyRun = variant == 2 };
            try
            {
                Check.Equal("uncertain", Run(transport, root).Status, "Définition ou antériorité contradictoire");
                Check.Equal(variant == 1 ? 1 : 0, transport.Runs, "Aucun nouveau lancement sur tâche non conforme");
                Check.Equal(0, transport.Deletes, "Une tâche non prouvée n’est pas supprimée");
            }
            finally { Cleanup(root); }
        }
    }

    [Test]
    public void OnlyClosedTerminalCodesCanReportAcceptance()
    {
        foreach (var (code, expected) in new (long, string)[] { (0, "accepted"), (96, "refused"), (97, "uncertain"), (1234, "uncertain") })
        {
            var root = Root(); var transport = new Transport(root) { Code = code };
            try
            {
                Check.Equal(expected, Run(transport, root).Status, "Code terminal " + code);
                Check.Equal(1, transport.Runs, "Toujours un seul envoi"); Check.Equal("Deleted", LastPhase(root), "Fin de tâche et nettoyage indépendants du succès métier");
            }
            finally { Cleanup(root); }
        }
    }

    [Test]
    public void MissingCompletionOrCleanupProofCannotBecomeAccepted()
    {
        for (var variant = 0; variant < 3; variant++)
        {
            var root = Root(); var transport = new Transport(root)
            { Active = variant == 0, NoRunTime = variant == 1, CleanupFailure = variant == 2 };
            try
            {
                Check.Equal("uncertain", Run(transport, root).Status, "État ou nettoyage non prouvé");
                Check.Equal(1, transport.Runs, "Aucune seconde demande");
                Check.Equal(variant == 2 ? 1 : 0, transport.Deletes, "Aucune suppression tant que la fin reste inconnue");
                Check.Equal(variant == 2 ? "DeleteFailed" : "Started", LastPhase(root), "Dernière frontière durable exacte");
            }
            finally { Cleanup(root); }
        }
    }

    [Test]
    public void LocalTargetAndUnrecordableIntentRefuseBeforeTransport()
    {
        foreach (var local in new[] { true, false })
        {
            var root = Root(); if (!local) File.WriteAllText(root, "fixture-no-directory");
            var transport = new Transport(root);
            try
            {
                Check.Equal("refused", Run(transport, root, local).Status, "Refus avant envoi");
                Check.Equal(0, transport.Registers, "Aucune tâche"); Check.Equal(0, transport.Runs, "Aucun Run");
            }
            finally { Cleanup(root); }
        }
    }

    [Test]
    public void PolicyRevokedDuringComWaitPreventsRunAndKeepsExactCleanupProof()
    {
        var root = Root(); var transport = new Transport(root); var admissions = 0;
        try
        {
            using var credential = new PestoAdCredential("EXAMPLE\\operator", Secret);
            var result = new RemoteRestartTask(transport, root, new FixedClock(), 1, 0, beforeRequest: () =>
            {
                admissions++;
                if (admissions == 2) throw ReceiptRestartRules.Refused("Fixture IncidentMode enabled after registration");
            }).Run(Command(), credential);
            Check.Equal("refused", result.Status, "A known zero-run policy refusal stays refused only after exact cleanup");
            Check.Equal(1, transport.Registers, "One inert task registered before policy changed");
            Check.Equal(0, transport.Runs, "No remote Run after policy revocation");
            Check.Equal(1, transport.Deletes, "Owned stopped definition cleaned exactly");
            Check.Equal("Deleted", LastPhase(root), "Durable cleanup proof remains available");
        }
        finally { Cleanup(root); }
    }
}
