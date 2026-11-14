using System.Text;
using System.Text.Json.Nodes;
using System.Xml.Linq;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class EntraDiagnosticTaskTests
{
    private const string Computer = "P111301PAINF009";
    private const string Domain = "example.local";
    private const string Secret = "fixture-entra-password";

    private sealed class Transport : ISystemDiagnosticTaskTransport, IDisposable
    {
        public readonly List<string> Calls = [];
        public string? Xml;
        public string? Principal;
        public string? Password;
        public string? TaskName;
        public long Result;
        public int State = 3;
        public bool MissingRunTime;
        public bool AlreadyRun;
        public bool ThrowRun;
        public bool DeleteFailure;
        public bool TamperBeforeRun;
        public bool TamperAfterRun;
        public bool Disposed;
        public ManualResetEventSlim? RegisterBlock;
        private bool ran;
        public void RegisterSystem(string computer, string taskName, string xml, string connectionPrincipal, string connectionPassword)
        {
            lock (Calls) Calls.Add("register-system");
            RegisterBlock?.Wait();
            Check.Equal(Computer, computer, "Cible exacte");
            Xml = xml; TaskName = taskName; Principal = connectionPrincipal; Password = connectionPassword;
        }
        public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal) => throw new TestFailureException("Le diagnostic ne doit pas enregistrer une tâche sous le compte AD");
        public void Run(string computer, string taskName)
        {
            Calls.Add("run"); ran = true;
            if (ThrowRun) throw new IOException("Réponse RPC perdue après Run");
        }
        public TaskProbeResult Probe(string computer, string taskName)
        {
            Calls.Add("probe");
            var xml = Xml!;
            if ((!ran && TamperBeforeRun) || (ran && TamperAfterRun)) xml = xml.Replace("S-1-5-18", "S-1-5-19", StringComparison.Ordinal);
            var lastRun = (ran && !MissingRunTime) || AlreadyRun ? new DateTimeOffset(2026, 10, 25, 10, 0, 0, TimeSpan.Zero) : (DateTimeOffset?)null;
            return new(ran ? State : 3, Result, lastRun, xml);
        }
        public void Delete(string computer, string taskName)
        { Calls.Add("delete"); if (DeleteFailure) throw new IOException("Absence non confirmée"); }
        public string? ReadTaskLogTail(string computer, string localLogPath) => throw new TestFailureException("Aucune lecture SMB dans ce diagnostic");
        public void Dispose() => Disposed = true;
    }

    private static string Root() => Path.Combine(Path.GetTempPath(), "pesto-entra-" + Guid.NewGuid().ToString("N"));
    private static EntraDiagnosticResult Read(Transport transport, string root)
    {
        using var credential = new PestoAdCredential("EXAMPLE\\operator", Secret);
        return new EntraDiagnosticTask(transport, root, new FixedClock(), timeoutSeconds: 1, pollDelayMilliseconds: 0)
            .Read(Computer, Domain, "receipt-test", credential);
    }

    [Test]
    public void AdOnlyDiagnosticUsesSystemAndAuthenticatedConnectionThenCleansWithEvidence()
    {
        var root = Root(); var transport = new Transport();
        try
        {
            var result = Read(transport, root);
            Check.True(result.AdOnlyConfirmed, "Seul le code terminal 0 confirme AD seul");
            Check.False(result.TaskStateUncertain, "Cycle de tâche terminé et nettoyage confirmé");
            Check.Equal("EXAMPLE\\operator", transport.Principal!, "Le compte AD authentifie la connexion COM");
            Check.Equal(Secret, transport.Password!, "Secret uniquement fourni au transport en mémoire");
            Check.Contains("<UserId>S-1-5-18</UserId>", transport.Xml, "La tâche exécute le lecteur sous SYSTEM");
            Check.False(transport.Xml!.Contains(Secret, StringComparison.Ordinal), "Aucun secret dans le XML");
            Check.False(transport.Xml.Contains("<Triggers>", StringComparison.Ordinal), "Aucun déclencheur donc aucune relance automatique");
            Check.Equal(1, transport.Calls.Count(x => x == "run"), "Un seul lancement");
            Check.Equal("delete", transport.Calls[^1], "Nettoyage après dernière vérification");
            var files = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories);
            Check.Equal(1, files.Length, "Preuve durable unique");
            var text = File.ReadAllText(files[0]);
            var evidence = JsonNode.Parse(text)!;
            Check.Equal("entra-status-evidence", evidence["Kind"]!.GetValue<string>(), "Le diagnostic n’est pas un reçu de renommage");
            Check.Equal(Computer, evidence["Computer"]!.GetValue<string>(), "La preuve permet de retrouver la cible");
            Check.Equal(result.TaskName, evidence["TaskName"]!.GetValue<string>(), "La preuve permet de retrouver la tâche même après interruption");
            Check.Equal("Deleted", evidence["Phases"]!.AsArray()[^1]!["Phase"]!.GetValue<string>(), "Fin durable du nettoyage");
            Check.False(text.Contains(Secret, StringComparison.Ordinal), "Aucun secret dans la preuve");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Test]
    public void HybridAndUnknownNativeResultsNeverAuthorizeRename()
    {
        foreach (var code in new long[] { 43, 44, 97, 1234 })
        {
            var root = Root(); var transport = new Transport { Result = code };
            try
            {
                var result = Read(transport, root);
                Check.False(result.AdOnlyConfirmed, "Aucun succès sur code " + code);
                Check.False(result.TaskStateUncertain, "Le résultat métier inconnu n’invente pas un lancement de tâche incertain quand la fin est prouvée");
                Check.True(transport.Calls.Contains("delete"), "Une lecture terminée est nettoyée");
                if (code == 43) Check.Contains("hybride", result.Message, "Le code43 identifie Entra et non une panne RPC");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }

    [Test]
    public void UncertainTaskStateNeverCleansOrRepeatsAndKeepsDurableEvidence()
    {
        foreach (var transport in new[] { new Transport { ThrowRun = true }, new Transport { State = 4 }, new Transport { Result = 267009 }, new Transport { MissingRunTime = true } })
        {
            var root = Root();
            try
            {
                var result = Read(transport, root);
                Check.False(result.AdOnlyConfirmed, "Aucun renommage sans résultat certain");
                Check.True(result.TaskStateUncertain, "État de tâche inconnu visible");
                Check.Equal(1, transport.Calls.Count(x => x == "run"), "Aucun rejeu");
                Check.False(transport.Calls.Contains("delete"), "Tâche active/inconnue conservée");
                Check.Equal(1, Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Length, "Preuve conservée");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }

    [Test]
    public void ModifiedDefinitionsAndUnconfirmedDeletionBlockTheMutation()
    {
        foreach (var transport in new[] { new Transport { TamperBeforeRun = true }, new Transport { TamperAfterRun = true }, new Transport { DeleteFailure = true }, new Transport { AlreadyRun = true } })
        {
            var root = Root();
            try
            {
                var result = Read(transport, root);
                Check.False(result.AdOnlyConfirmed, "Une définition différente ou un nettoyage incertain ne permet pas le renommage");
                if (transport.TamperBeforeRun || transport.AlreadyRun) Check.False(transport.Calls.Contains("run"), "Une tâche non conforme n’est jamais lancée");
                if (transport.TamperBeforeRun || transport.TamperAfterRun) Check.False(transport.Calls.Contains("delete"), "Une tâche modifiée n’est pas effacée");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }

    [Test]
    public void ScriptContainsOnlyBoundedStatusReadingWithTargetDomainAndSystemChecks()
    {
        var script = EntraDiagnosticTask.StatusScript(Computer, Domain);
        foreach (var forbidden in new[] { "Rename-Computer", "Add-Computer", "Move-ADObject", "Restart-Computer", "/leave", "RegisterTask", "Win32_ComputerSystem.Rename" })
            Check.False(script.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Instruction de mutation absente : " + forbidden);
        foreach (var required in new[] { "'S-1-5-18'", "COMPUTERNAME -ine '" + Computer + "'", "Domain -ine '" + Domain + "'", "DomainRole -notin @(1,3)", "Arguments='/status'", "WaitForExit(60000)", "exit 43", "exit 44", "exit 97" })
            Check.Contains(required, script, "Garde obligatoire du lecteur");
        var regex = System.Text.RegularExpressions.Regex.Match(script, @"\$aad=\[regex\]::Matches\(\$text,'([^']+)'\)").Groups[1].Value;
        Check.True(System.Text.RegularExpressions.Regex.IsMatch(" AzureAdJoined : NO\r\n", regex), "Le vrai motif intégré au script reconnaît le retour dsreg");
        var adapter = new PowerShellMutationGateway();
        Check.Contains("SYSTEM", string.Join(" ", adapter.PreparationNotes("rename", Computer)), "La confirmation révèle la tâche temporaire avant consentement");
        Check.Equal(0, adapter.PreparationNotes("move", Computer).Count, "Le déplacement seul n’invente pas de diagnostic Entra nécessaire");
    }

    [Test]
    public void NormalizedSchedulerXmlIsAcceptedButExecPrincipalAndTriggersCannotChange()
    {
        const string command = "reader.exe", arguments = "--status";
        var xml = TaskFallback.NewRunOnceTaskXml(command, arguments, "S-1-5-18", "ServiceAccount")
            .Replace("PT10M", "PT2M", StringComparison.Ordinal);
        var normalized = XDocument.Parse(xml).ToString();
        EntraDiagnosticTask.ValidateDefinition(normalized, command, arguments);
        foreach (var changed in new[]
        {
            xml.Replace("S-1-5-18", "S-1-5-19", StringComparison.Ordinal), xml.Replace("reader.exe", "writer.exe", StringComparison.Ordinal),
            xml.Replace("PT2M", "PT10M", StringComparison.Ordinal), xml.Replace("<Principals>", "<Triggers><BootTrigger/></Triggers><Principals>", StringComparison.Ordinal),
        })
        {
            var refused = false;
            try { EntraDiagnosticTask.ValidateDefinition(changed, command, arguments); } catch (InvalidOperationException) { refused = true; }
            Check.True(refused, "Définition différente rejetée");
        }
    }

    [Test]
    public void BlockedRpcIsBoundedAndCannotStartAnyLaterDiagnosticOrMutation()
    {
        var root = Root(); using var unblock = new ManualResetEventSlim();
        var transport = new Transport { RegisterBlock = unblock };
        using var credential = new PestoAdCredential("EXAMPLE\\operator", Secret);
        using var bounded = new BoundedSystemDiagnosticTransport(transport, ownsTransport: true, budget: TimeSpan.FromMilliseconds(150), callTimeout: TimeSpan.FromMilliseconds(30));
        try
        {
            var before = System.Diagnostics.Stopwatch.StartNew();
            var result = new EntraDiagnosticTask(bounded, root, timeoutSeconds: 1, pollDelayMilliseconds: 0).Read(Computer, Domain, "receipt-timeout", credential);
            Check.False(result.AdOnlyConfirmed, "Aucune autorisation issue d’un appel RPC bloqué");
            Check.True(result.TaskStateUncertain, "Création non confirmée signalée");
            Check.True(before.Elapsed < TimeSpan.FromSeconds(2), "Le budget borne la réponse à l’hôte");
            // On a loaded runner the timed-out call may not have reached the transport yet (run 41037119110): wait for
            // it, then require that it stays the only one.
            Check.True(SpinWait.SpinUntil(() => { lock (transport.Calls) return transport.Calls.Count >= 1; }, 10000), "L’appel RegisterSystem bloqué a atteint le transport");
            lock (transport.Calls) Check.Equal(1, transport.Calls.Count, "Ni Run, ni Probe, ni Delete après dépassement du délai");
            bounded.Dispose();
            Check.False(transport.Disposed, "La connexion n’est pas détruite pendant l’appel COM encore actif");
        }
        finally
        {
            unblock.Set();
            SpinWait.SpinUntil(() => transport.Disposed, 2000);
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
}
