using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Text.Json.Serialization;
using Pesto.Engine;

namespace Pesto.Engine.Live;

internal sealed class PowerShellEntraExecution(ITaskFallbackCredentialSource? credentials, ITaskSchedulerTransport? suppliedTransport)
    : IEntraLeaveTransport
{
    public EntraLeaveNativeResult Leave(EntraLeaveCommand command, Action<string, string?, string?, long?> record)
    {
        if (!OperatingSystem.IsWindows()) return new("NotRequested", false, "Retrait Entra indisponible hors Windows.", 44);
        if (command.Request.Computer.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase))
        {
            record("DispatchRequested", null, null, null);
            return RunLocal(command, inspect: false);
        }
        if (credentials is not IWindowsCredentialSource source) return new("NotRequested", false, "Le retrait distant exige le compte AD explicite de cette session.", 44);
        using var credential = source.AcquireForDiagnostic();
        if (credential is null) return new("NotRequested", false, "Compte AD distant indisponible : aucun retrait.", 44);
        var raw = suppliedTransport as ISystemDiagnosticTaskTransport;
        if (raw is null && suppliedTransport is not null) return new("NotRequested", false, "Transport SYSTEM absent : aucun retrait.", 44);
        raw ??= new TaskSchedulerComTransport();
        using var transport = new BoundedEntraTaskTransport(raw, suppliedTransport is null);
        return new EntraLeaveTask(transport).Run(command, PowerShellEntraWorker.Build(command), credential, record);
    }

    public EntraLeaveNativeResult Inspect(EntraLeaveCommand command, EntraLeaveSnapshot snapshot, bool taskAlreadyDeleted, string gpRoot)
    {
        if (!OperatingSystem.IsWindows()) return Unknown("Inspection Entra indisponible hors Windows.");
        if (command.Request.Computer.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase)
            || command.Request.NewName.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase))
            return RunLocal(command, inspect: true);
        if (credentials is not IWindowsCredentialSource source) return Unknown("Compte AD explicite requis pour l’inspection.");
        using var credential = source.AcquireForDiagnostic();
        if (credential is null) return Unknown("Compte de l’inspection indisponible.");
        if (!taskAlreadyDeleted)
        {
            if (snapshot.Event.TaskName is null || snapshot.Event.TaskDefinitionSha256 is null)
                return Unknown("Définition de la tâche initiale non enregistrée ; aucune fin supposée.");
            try
            {
                var probe = ExistingTaskProbe(command.Request.Computer, snapshot.Event.TaskName, credential, command.Request.Domain);
                if (probe.State is not (1 or 3) || probe.LastRunTime is not { Year: >= 2000 }
                    || probe.LastTaskResult is 267008 or 267009 or 267011
                    || !TaskFallback.DefinitionHash(probe.DefinitionXml).Equals(snapshot.Event.TaskDefinitionSha256, StringComparison.OrdinalIgnoreCase))
                    return Unknown("La tâche de retrait peut encore agir ou sa définition a changé.");
            }
            catch (Exception) { return Unknown("Fin de la tâche initiale non prouvée ; aucune conclusion déduite."); }
        }
        // The inspection is a different, read-only task. The original task is never rerun or repaired.
        var raw = new TaskSchedulerComTransport();
        using var bounded = new BoundedEntraTaskTransport(raw, true, TimeSpan.FromSeconds(150));
        return RunInspectionTask(command, credential, bounded, gpRoot);
    }

    private static EntraLeaveNativeResult RunLocal(EntraLeaveCommand command, bool inspect)
    {
        try
        {
            var script = PowerShellEntraWorker.Build(command, inspect);
            var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32",
                "WindowsPowerShell", "v1.0", "powershell.exe");
            var start = PowerShellFixedWorker.StartInfo(script);
            start.FileName = executable;
            if (!EntraLeaveTask.FitsNativeCommand(executable, string.Join(' ', start.ArgumentList)))
                return inspect ? Unknown("Commande d’inspection trop volumineuse ; aucune preuve remplacée.")
                    : new("NotRequested", false, "La commande Entra dépasse la limite native Windows ; aucun retrait lancé.", 44);
            using var process = Process.Start(start);
            if (process is null) return Unknown("Réponse de lancement Entra absente.");
            OwnedMutationJob job;
            try { job = OwnedMutationJob.Attach(process); }
            catch (Exception)
            {
                // The fixed bootstrap is blocked on stdin. No script or /leave has been supplied yet.
                return inspect ? Unknown("Isolation du diagnostic non confirmée.")
                    : new("NotRequested", false, "Le travailleur Entra ne peut pas être rattaché au parent ; aucun retrait envoyé.", 44);
            }
            using var ownedWorker = job;
            var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
            PowerShellFixedWorker.Send(process, script, ""); // Only after the owned JobObject; the script includes its closed request binding.
            if (!process.WaitForExit(inspect ? 90000 : 450000))
            {
                // Closing the owned job stops only this worker and descendants. It is never rollback or no-effect proof.
                return Unknown("Délai Entra dépassé ; l’effet peut être engagé. Aucune répétition ni réussite déduite de l’arrêt du travailleur.");
            }
            var text = output.GetAwaiter().GetResult(); _ = error.GetAwaiter().GetResult();
            if (text.Length is 0 or > 65536) return Unknown("Réponse Entra non exploitable.");
            var result = JsonSerializer.Deserialize<EntraLeaveNativeResult>(text,
                new JsonSerializerOptions { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, RespectRequiredConstructorParameters = true });
            if (result is null || result.NativeCode != process.ExitCode
                || result.Effect is not ("Confirmed" or "Uncertain" or "NotRequested")
                || result.Effect == "Confirmed" && result.NativeCode != 42
                || result.Effect == "NotRequested" && result.NativeCode != 44)
                return Unknown("Réponse Entra non probante.");
            return result;
        }
        catch (Exception) { return Unknown("Exécution ou lecture du résultat Entra interrompue."); }
    }

    private static EntraLeaveNativeResult RunInspectionTask(EntraLeaveCommand command, PestoAdCredential credential,
        ISystemDiagnosticTaskTransport transport, string gpRoot)
    {
        var id = Guid.NewGuid().ToString("N")[..12]; var taskName = "\\Pesto_EntraInspect_" + id;
        const string executable = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
        var arguments = EntraLeaveTask.WorkerArguments(PowerShellEntraWorker.Build(command, inspect: true));
        if (!EntraLeaveTask.FitsNativeCommand(executable, arguments))
            return Unknown("Commande d’inspection trop volumineuse ; aucune tâche créée.");
        var xml = TaskFallback.NewRunOnceTaskXml(executable, arguments, "S-1-5-18", "ServiceAccount", "HighestAvailable", "Pesto - inspection Entra en lecture seule")
            .Replace("<ExecutionTimeLimit>PT10M</ExecutionTimeLimit>", "<ExecutionTimeLimit>PT2M</ExecutionTimeLimit>", StringComparison.Ordinal);
        var evidence = new TaskEvidence(gpRoot, command.ReceiptId, id, kind: "entra-status-evidence", computer: command.Request.Computer, taskName: taskName);
        string? definition = null;
        try
        {
            var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@') ? credential.UserName : credential.UserName + "@" + command.Request.Domain;
            evidence.Record("Registering");
            transport.RegisterSystem(command.Request.Computer, taskName, xml, principal, credential.TakePassword());
            var initial = transport.Probe(command.Request.Computer, taskName);
            EntraDiagnosticTask.ValidateDefinition(initial.DefinitionXml, executable, arguments);
            if (initial.LastRunTime is { Year: >= 2000 }) return Unknown("Diagnostic déjà exécuté.");
            definition = TaskFallback.DefinitionHash(initial.DefinitionXml); evidence.Record("Registered", definition);
            evidence.AssertDefinition(transport.Probe(command.Request.Computer, taskName).DefinitionXml);
            evidence.Record("StartRequested"); transport.Run(command.Request.Computer, taskName); evidence.Record("Started");
            var until = DateTimeOffset.UtcNow.AddSeconds(120);
            while (DateTimeOffset.UtcNow < until)
            {
                var probe = transport.Probe(command.Request.Computer, taskName);
                evidence.AssertDefinition(probe.DefinitionXml);
                if (probe.State == 3 && probe.LastRunTime is { Year: >= 2000 } && probe.LastTaskResult is not (267008 or 267009 or 267011))
                {
                    evidence.Record("Finished", nativeCode: probe.LastTaskResult);
                    var last = transport.Probe(command.Request.Computer, taskName); evidence.AssertDefinition(last.DefinitionXml);
                    if (last.State is not (1 or 3)) return Unknown("Diagnostic redevenu actif.");
                    transport.Delete(command.Request.Computer, taskName); evidence.Record("Deleted");
                    return probe.LastTaskResult switch
                    {
                        42 => new("Confirmed", false, "Retrait et absence de travailleur confirmés par sa preuve cible.", 42),
                        44 => new("NotRequested", false, "Absence de retrait et de travailleur confirmée.", 44),
                        45 => new("Uncertain", false, "Résultat conservé incertain ; absence de travailleur confirmée.", 45),
                        _ => Unknown("Le diagnostic ne prouve pas l’arrêt des effets Entra.")
                    };
                }
                Thread.Sleep(500);
            }
        }
        catch (Exception) { }
        return Unknown("Inspection Entra interrompue ; aucune barrière levée.");
    }

    [SupportedOSPlatform("windows")]
    private static TaskProbeResult ExistingTaskProbe(string computer, string name, PestoAdCredential credential, string domain)
    {
        var pending = Task.Run(() =>
        {
            object? serviceObject = null; object? folderObject = null; object? taskObject = null;
            try
            {
                var type = Type.GetTypeFromProgID("Schedule.Service") ?? throw new InvalidOperationException();
                serviceObject = Activator.CreateInstance(type) ?? throw new InvalidOperationException(); dynamic service = serviceObject;
                var user = credential.UserName; string? userDomain = null;
                var slash = user.IndexOf('\\'); if (slash >= 0) { userDomain = user[..slash]; user = user[(slash + 1)..]; }
                else if (!user.Contains('@')) user += "@" + domain;
                service.Connect(computer, user, userDomain, credential.TakePassword());
                folderObject = service.GetFolder("\\"); dynamic folder = folderObject; taskObject = folder.GetTask(name); dynamic task = taskObject;
                return new TaskProbeResult(Convert.ToInt32(task.State, System.Globalization.CultureInfo.InvariantCulture),
                    Convert.ToInt64(task.LastTaskResult, System.Globalization.CultureInfo.InvariantCulture),
                    TaskSchedulerComValues.LastRunTime((object?)task.LastRunTime), (string)task.Xml);
            }
            finally { foreach (var value in new[] { taskObject, folderObject, serviceObject }) if (value is not null && Marshal.IsComObject(value)) Marshal.FinalReleaseComObject(value); }
        });
        if (!pending.Wait(TimeSpan.FromSeconds(15)))
        {
            _ = pending.ContinueWith(t => { _ = t.Exception; }, TaskScheduler.Default);
            throw new TimeoutException("Lecture de tâche non confirmée.");
        }
        return pending.GetAwaiter().GetResult();
    }

    private static EntraLeaveNativeResult Unknown(string reason) => new("Uncertain", true, reason + " Aucun renommage ni répétition automatique.", 97);
}

/// <summary>A bounded mutative COM session. A timed-out call is never followed by another command or cleanup.</summary>
internal sealed class BoundedEntraTaskTransport(ISystemDiagnosticTaskTransport inner, bool ownsTransport,
    TimeSpan? budget = null) : ISystemDiagnosticTaskTransport, IDisposable
{
    private readonly Stopwatch elapsed = Stopwatch.StartNew();
    private readonly TimeSpan budget = budget ?? TimeSpan.FromSeconds(510);
    private Task? active; private bool faulted; private bool disposed;
    private T Call<T>(Func<T> action)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (faulted || elapsed.Elapsed >= budget) throw new TimeoutException("Session Entra expirée.");
        var pending = Task.Run(action); active = pending;
        try
        {
            var left = budget - elapsed.Elapsed;
            if (!pending.Wait(left < TimeSpan.FromSeconds(15) ? left : TimeSpan.FromSeconds(15)))
            { faulted = true; throw new TimeoutException("Réponse COM Entra perdue ; aucun appel suivant."); }
            return pending.GetAwaiter().GetResult();
        }
        catch (AggregateException error) { throw error.InnerException ?? error; }
        finally { if (pending.IsCompleted) active = null; }
    }
    public void RegisterSystem(string computer, string taskName, string xml, string principal, string password) =>
        Call(() => { inner.RegisterSystem(computer, taskName, xml, principal, password); return true; });
    public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal) => throw new InvalidOperationException("Entra exige SYSTEM explicite.");
    public void Run(string computer, string taskName) => Call(() => { inner.Run(computer, taskName); return true; });
    public TaskProbeResult Probe(string computer, string taskName) => Call(() => inner.Probe(computer, taskName));
    public void Delete(string computer, string taskName) => Call(() => { inner.Delete(computer, taskName); return true; });
    public string? ReadTaskLogTail(string computer, string localLogPath) => throw new InvalidOperationException("Aucune lecture SMB arbitraire.");
    public void Dispose()
    {
        if (disposed) return; disposed = true;
        if (!ownsTransport || inner is not IDisposable owned) return;
        if (active is { IsCompleted: false } pending) _ = pending.ContinueWith(t => { _ = t.Exception; owned.Dispose(); }, TaskScheduler.Default);
        else owned.Dispose();
    }
}
