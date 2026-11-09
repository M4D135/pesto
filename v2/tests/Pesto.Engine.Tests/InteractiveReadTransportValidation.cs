using System.Diagnostics;
using System.Diagnostics.Tracing;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Security;
using System.Text;
using System.Text.Json;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

// The actual compiled AD reader, made harmless by a synthetic module containing only two read commands.
internal static class InteractiveReadTransportValidation
{
    private const string Domain = "fixture.invalid", Dc = "dc.fixture.invalid", Ou = "OU=Site,DC=fixture,DC=invalid";

    internal static async Task<int> Run(string? localShell = null)
    {
        if (!OperatingSystem.IsWindows() && (localShell is null || !Path.IsPathFullyQualified(localShell))) return 1;
        var root = Path.Combine(Path.GetTempPath(), "Pesto-warm-read-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var module = Path.Combine(root, "Fixture.psm1");
            var fact = Path.Combine(root, "name.txt");
            var mode = Path.Combine(root, "mode.txt");
            File.WriteAllText(module, Module, new UTF8Encoding(true)); File.WriteAllText(mode, "normal");
            using var fixture = new Session(localShell);
            JsonElement Read(string op, object? credential = null, string pattern = "P111301PR765*")
            {
                var input = JsonSerializer.Serialize(new { Op = op, Server = Dc, Domain, ModulePath = module, Credential = credential,
                    Pattern = pattern, Patterns = new[] { "P111301PR*" }, Explicit = new[] { Ou }, Parents = Array.Empty<string>(), Ou, Max = 100,
                    SelectedSite = op is "siteServices" or "automationNames" ? new SelectedSiteOu(Ou, "Site") : null,
                    Literal = "'; [Environment]::Exit(77); $(throw 'JSON is not code')" });
                var reply = JsonSerializer.Deserialize<JsonElement>(fixture.Execute(input, module));
                Check.True(reply.GetProperty("ok").GetBoolean(), "Réponse du lecteur synthétique : " + reply);
                Check.False(reply.TryGetProperty("timing", out _), "Aucune télémétrie du worker dans une lecture normale");
                return reply.GetProperty("result");
            }
            JsonElement Trace() => JsonSerializer.Deserialize<JsonElement>(File.ReadLines(Path.Combine(root, "trace.jsonl")).Last());
            var clock = Stopwatch.StartNew();
            Check.Equal(1, Read("sites").GetProperty("found").GetArrayLength(), "Lecture froide des sites");
            var coldMs = clock.Elapsed.TotalMilliseconds; var cold = Trace();
            var pid = cold.GetProperty("pid").GetInt32();
            Check.True(!OperatingSystem.IsWindows() || cold.GetProperty("ps").GetString() == "5.1", "Windows utilise réellement PowerShell 5.1");
            using var initialProcess = Process.GetProcessById(pid);
            File.WriteAllText(fact, "P111301PR765001"); clock.Restart();
            var services = Read("siteServices"); var warmMs = clock.Elapsed.TotalMilliseconds;
            Check.Equal("P111301PR765001", services.GetProperty("inOu")[0].GetString(), "Première lecture chaude");
            File.WriteAllText(fact, "P111301PR765002");
            Check.Equal("P111301PR765002", Read("automationNames").GetProperty("names")[0].GetString(), "Les faits modifiés sont relus");
            var nominalCalls = File.ReadAllLines(Path.Combine(root, "trace.jsonl")).Select(row => JsonSerializer.Deserialize<JsonElement>(row)).ToArray();
            Check.True(nominalCalls.Length == 6 && nominalCalls.All(row => row.GetProperty("pid").GetInt32() == pid
                && row.GetProperty("moduleLoads").GetInt32() == 1), "Sites, service et série avec validation des OU : même processus et un seul import");
            using (var listener = new TimingListener())
            {
                listener.EnableEvents(DirectoryReadEvents.Log, EventLevel.Informational);
                var timedRequest = JsonSerializer.Serialize(new { Op = "automationNames", Server = Dc, Domain, ModulePath = module,
                    Pattern = "P111301PR765*", Max = 100, SelectedSite = new SelectedSiteOu(Ou, "Site"), TraceTiming = true });
                var timedReply = fixture.Execute(timedRequest, module);
                var parse = typeof(PowerShellDirectoryGateway).GetMethod("ParseReply", BindingFlags.Static | BindingFlags.NonPublic)!;
                var result = (JsonElement)parse.Invoke(null, [timedReply, "automationNames"])!;
                Check.True(result.GetProperty("names")[0].GetString() == "P111301PR765002" && !result.TryGetProperty("timing", out _),
                    "Les durées restent hors du résultat métier");
                var backend = PestoBackend.CreateLive(null);
                try { await backend.InvokeAsync("names.preview", JsonSerializer.Deserialize<JsonElement>("{}")); }
                catch (PestoException) { /* un refus de configuration conserve son temps total */ }
                Check.True(listener.Events.Select(row => (string)row.Payload![1]!).SequenceEqual(
                    new[] { "ps.moduleImport", "ps.selectedOu", "ps.query", "backend.gateWait", "backend.total" }),
                    "Phases ETW du worker et du moteur, y compris sur refus");
                Check.True(listener.Events.All(row => row.EventId == 1 && row.Payload!.Count == 3 &&
                    row.EventName == "Duration" && row.PayloadNames!.SequenceEqual(new[] { "operation", "phase", "milliseconds" }) &&
                    row.Payload[0] is "automationNames" or "names.preview" && row.Payload[2] is double ms && ms >= 0),
                    "Aucun nom de domaine, poste, identité, DN ou argument dans la trace");
            }
            if (OperatingSystem.IsWindows())
            {
                using var secret = new SecureString(); foreach (var c in "Synthetic-fixture-é") secret.AppendChar(c); secret.MakeReadOnly();
                using var account = WindowsAdCredentialSource.FromSecurePassword(@"EXAMPLE\fixture", secret);
                _ = Read("automationNames", account.CreateProtectedPayload());
                Check.True(Trace().GetProperty("credential").GetBoolean(), "Compte explicite déchiffré pour cette requête");
                _ = Read("automationNames");
                Check.False(Trace().GetProperty("credential").GetBoolean(), "La requête suivante ne reçoit pas le compte précédent");
            }
            var concurrent = await Task.WhenAll(Enumerable.Range(1, 4).Select(i => Task.Run(() =>
            {
                var series = "P111301PR76" + i + "*";
                return Read("automationNames", pattern: series).GetProperty("names")[0].GetString();
            })));
            Check.True(concurrent.SequenceEqual(Enumerable.Range(1,4).Select(i => "P111301PR76" + i + "001")), "Réponses concurrentes corrélées aux demandes");
            File.WriteAllText(mode, "exit");
            Check.Pesto(() => Read("automationNames"), "directory.transient", "Processus perdu : pas de résultat");
            Check.True(initialProcess.WaitForExit(3000), "Le premier processus est terminé");
            File.WriteAllText(mode, "normal"); _ = Read("sites");
            using var resumed = Process.GetProcessById(Trace().GetProperty("pid").GetInt32());
            File.WriteAllText(mode, "corrupt");
            Check.Pesto(() => Read("automationNames"), "directory.unavailable", "Identifiant de trame incorrect : rejet");
            Check.True(resumed.WaitForExit(3000), "Le flux corrompu est fermé");
            File.WriteAllText(mode, "normal"); _ = Read("sites");
            using var timed = Process.GetProcessById(Trace().GetProperty("pid").GetInt32());
            File.WriteAllText(mode, "stall");
            Check.Pesto(() => Read("automationNames"), "directory.transient", "Le délai borné ferme l’ancienne génération");
            Check.True(timed.WaitForExit(3000), "Processus lent terminé");
            File.WriteAllText(mode, "oversize");
            Check.Pesto(() => Read("automationNames"), "directory.unavailable", "Réponse hors borne refusée sans publication partielle");
            File.WriteAllText(mode, "normal"); _ = Read("sites");
            using var last = Process.GetProcessById(Trace().GetProperty("pid").GetInt32());
            Check.Pesto(() => fixture.Execute(new string('x', 1024*1024+1), module), "directory.unavailable", "Requête hors borne refusée");
            fixture.Dispose();
            Check.True(last.WaitForExit(3000), "Le lecteur inactif se ferme avec son propriétaire");
            Check.Pesto(() => Read("sites"), "directory.unavailable", "Aucune recréation après fermeture de l’application");
            var eofExit = await fixture.ProbeEof(localShell);
            Check.Equal(0, eofExit, "Le corps vérifié se termine normalement sur EOF");
            using var closing = new Session(localShell);
            var request = JsonSerializer.Serialize(new { Op = "automationNames", Domain, Server = Dc, Credential = (object?)null,
                ModulePath = module, Pattern = "P111301PR765*", Max = 10 });
            _ = closing.Execute(request, module);
            using var busyProcess = Process.GetProcessById(Trace().GetProperty("pid").GetInt32());
            var marker = Path.Combine(root, "stall.ready"); File.Delete(marker); File.WriteAllText(mode, "stall");
            var pending = Task.Run(() => Check.Pesto(() => closing.Execute(request, module), "directory.unavailable", "Fermeture pendant une lecture"));
            using var waiting = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (!File.Exists(marker)) await Task.Delay(10, waiting.Token);
            clock.Restart(); closing.Dispose();
            await pending.WaitAsync(TimeSpan.FromSeconds(3));
            Check.True(busyProcess.WaitForExit(3000), "Aucun lecteur actif après la fermeture");
            var activeCloseMs = clock.Elapsed.TotalMilliseconds;
            Console.WriteLine(JsonSerializer.Serialize(new { kind="pesto.interactive-read-contract", success=true, powershell=cold.GetProperty("ps").GetString(),
                coldMs, warmMs, firstPid=pid, moduleLoads=1, freshInventory=true, explicitCredentialChecked=OperatingSystem.IsWindows(),
                nominalDirectoryCalls=nominalCalls.Length, correlatedConcurrentReplies=4, lostProcessRecovered=true,
                corruptResponseRefused=true, lateResponseDiscarded=true, eofExitCode=eofExit,
                responseBoundChecked=true, activeCloseMs, optInTimingChecked=true, windowsKillOnCloseJob=OperatingSystem.IsWindows(), adExecuted=false, syntheticCmdlets=true }));
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine("ECHEC transport lecteur : " + error.Message); return 1; }
        finally { Directory.Delete(root, true); }
    }

    private sealed class TimingListener : EventListener
    {
        internal List<EventWrittenEventArgs> Events { get; } = [];
        protected override void OnEventWritten(EventWrittenEventArgs e) { Events.Add(e); }
    }

    private sealed class Session(string? shell) : IDisposable
    {
        private static readonly Type Type = typeof(PowerShellDirectoryGateway).Assembly.GetType("Pesto.Engine.Live.InteractiveReadSession", true)!;
        private readonly object instance = Activator.CreateInstance(Type, BindingFlags.Instance | BindingFlags.NonPublic, null,
            [PowerShellDirectoryGateway.ConstantScript, TimeSpan.FromSeconds(8), shell], null)!;
        public string Execute(string input, string module)
        {
            try { return (string)Type.GetMethod("Execute", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(instance, [input, module])!; }
            catch (TargetInvocationException error) when (error.InnerException is not null) { ExceptionDispatchInfo.Capture(error.InnerException).Throw(); throw; }
        }
        public void Dispose() => ((IDisposable)instance).Dispose();

        internal async Task<int> ProbeEof(string? shell)
        {
            var host = (string)Type.GetField("host", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(instance)!;
            var worker = Type.Assembly.GetType("Pesto.Engine.Live.PowerShellFixedWorker", true)!;
            var info = (ProcessStartInfo)worker.GetMethod("StartInfo")!.Invoke(null, [host])!;
            if (shell is not null) info.FileName = shell;
            using var process = Process.Start(info)!;
            using var job = OperatingSystem.IsWindows() ? (IDisposable)Type.Assembly.GetType("Pesto.Engine.Live.OwnedMutationJob", true)!
                .GetMethod("Attach")!.Invoke(null, [process])! : null;
            await (Task)worker.GetMethod("SendScriptAsync")!.Invoke(null, [process, host])!;
            using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            try
            {
                var ack = new byte[1]; await process.StandardOutput.BaseStream.ReadExactlyAsync(ack, stop.Token);
                Check.Equal((byte)80, ack[0], "Le corps vérifié attend sa première trame");
                process.StandardInput.Close(); await process.WaitForExitAsync(stop.Token); return process.ExitCode;
            }
            finally { if (!process.HasExited) process.Kill(entireProcessTree: true); }
        }
    }
    private const string Module = """
$global:FixtureModuleLoads+=1
$global:PSModuleAutoLoadingPreference='None'
function Trace-Read($params){
  if($params.Server -cne 'dc.fixture.invalid'){throw 'Untrusted fixture server'}
  $row=@{pid=$PID;ps=('{0}.{1}' -f $PSVersionTable.PSVersion.Major,$PSVersionTable.PSVersion.Minor);moduleLoads=$global:FixtureModuleLoads;credential=$params.ContainsKey('Credential')}
  [IO.File]::AppendAllText(([IO.Path]::Combine($PSScriptRoot,'trace.jsonl')),(ConvertTo-Json $row -Compress)+[Environment]::NewLine)
}
function Get-ADOrganizationalUnit {
  [CmdletBinding()]param($Server,$Identity,$SearchBase,$SearchScope,$LDAPFilter,$Filter,$ResultSetSize,$ResultPageSize,$Properties,$Credential)
  Trace-Read $PSBoundParameters
  if($Identity -and $Identity -cne 'OU=Site,DC=fixture,DC=invalid'){throw 'Unexpected fixture site'}
  [pscustomobject]@{Name='Site';DistinguishedName='OU=Site,DC=fixture,DC=invalid';ObjectGUID='1ed4d6db-a22c-4e00-b77b-adccf715a652'}
}
function Get-ADComputer {
  [CmdletBinding()]param($Server,$SearchBase,$SearchScope,$LDAPFilter,$Filter,$ResultSetSize,$ResultPageSize,$Properties,$Credential)
  Trace-Read $PSBoundParameters
  switch([IO.File]::ReadAllText(([IO.Path]::Combine($PSScriptRoot,'mode.txt')))){
    'exit' {[Environment]::Exit(19)}
    'stall' {[IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot,'stall.ready'),'started');Start-Sleep -Seconds 90}
    'corrupt' {[Console]::OpenStandardOutput().WriteByte(255)}
    'oversize' {[pscustomobject]@{Name=('x'*8388608);SamAccountName='';DNSHostName=''};return}
  }
  $name=[IO.File]::ReadAllText(([IO.Path]::Combine($PSScriptRoot,'name.txt')))
  if($LDAPFilter -match 'name=(P111301PR76[1-4])\*'){$name=$Matches[1]+'001'}
  [pscustomobject]@{Name=$name;SamAccountName=$name+'$';DNSHostName=$name+'.fixture.invalid'}
}
Export-ModuleMember -Function Get-ADOrganizationalUnit,Get-ADComputer
""";
}
