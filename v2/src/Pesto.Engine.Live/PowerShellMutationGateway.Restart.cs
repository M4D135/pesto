using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationRestart, IReceiptRestartEnvironment
{
    private readonly object restartGate = new();
    private ReceiptRestartCoordinator? restartCoordinator;
    private string? activeRestartConfigurationSha256;

    private ReceiptRestartCoordinator RestartCoordinator => restartCoordinator ??= new(this,
        new ReceiptRestartStore(ReceiptGpRoot(), folder => { if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder); }));

    public RestartPreparation PrepareRestart(string receiptId, string planId, string configurationSha256) =>
        WithRestartMutex(configurationSha256, () => RestartCoordinator.Prepare(receiptId, planId, configurationSha256));
    public RestartResult Restart(RestartAuthorization authorization) =>
        WithRestartMutex(authorization.ConfigurationSha256, () => RestartCoordinator.Execute(authorization));

    private T WithRestartMutex<T>(string configurationSha256, Func<T> action)
    {
        lock (restartGate)
        {
            RequireNativeRestartSession();
            using var mutex = new Mutex(false, PostMutationMutexName); var owned = false;
            try
            {
                try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
                if (!owned) throw ReceiptRestartRules.Refused("Une mutation ou vérification utilise le mutex GP : aucun redémarrage envoyé.");
                // FileShare.Read holds the current authorization configuration against replacement until the request ends.
                // This SHA is deliberately not the historical ConfigurationSha256 stored in the parent business receipt.
                using var configuration = PinConfirmedConfiguration(configurationSha256);
                activeRestartConfigurationSha256 = configurationSha256;
                return action();
            }
            finally { activeRestartConfigurationSha256 = null; if (owned) mutex.ReleaseMutex(); }
        }
    }

    private void RequireNativeRestartSession() => ReceiptRestartAdmission.RequireSession(
        Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1", unavailableReason is null, unavailableReason);

    void IReceiptRestartEnvironment.RequireAdmission(RestartReceiptSnapshot source, string configurationSha256) =>
        RequireNativeRestartAdmission(source, configurationSha256);

    private void RequireNativeRestartAdmission(RestartReceiptSnapshot source, string configurationSha256)
    {
        RequireNativeRestartSession();
        if (v1InstallationPath is null || activeRestartConfigurationSha256 != configurationSha256)
            throw ReceiptRestartRules.Refused("La configuration d’autorisation du redémarrage n’est pas pincée sous le mutex GP.");
        var path = Path.Combine(v1InstallationPath, "cfg.json"); RequireNoReparsePoint(path);
        var bytes = File.ReadAllBytes(path);
        var requirements = ReceiptRestartAdmission.RequireConfiguration(bytes, configurationSha256, source, ReadManagedPolicy());
        if (requirements.ExcludedGroupGuids.Count > 0)
            GroupExclusionGuard.Require(groupExclusionReader, source.Domain, source.Dc, source.ComputerGuid!,
                requirements.ExcludedGroupGuids, source.Receipt.NewName, source.ExpectedAdOu);
        RequireNativeRestartSession();
        _ = ReceiptRestartAdmission.RequireConfiguration(File.ReadAllBytes(path), configurationSha256, source, ReadManagedPolicy());
    }

    RestartReceiptSnapshot IReceiptRestartEnvironment.ReadSource(string receiptId)
    {
        var path = ReceiptPath(receiptId); var bytes = ReadReceiptBytes(path);
        if (HasAppliedAcknowledgement(path, bytes)) throw ReceiptRestartRules.Refused("Ce reçu a été acquitté : aucun redémarrage lié à son ancienne preuve.");
        using var document = JsonDocument.Parse(bytes);
        if (EntraEvidenceAllowsReconciliation(document.RootElement) is { } reason) throw ReceiptRestartRules.Refused(reason);
        return ReceiptRestartRules.ReadSource(path, bytes, DateTimeOffset.UtcNow);
    }

    RestartTargetEvidence IReceiptRestartEnvironment.ReadTarget(RestartReceiptSnapshot source)
    {
        NativeReceiptSnapshot snapshot;
        var module = ResolveAdModulePath();
        if (module is null) snapshot = UnknownWindows("Module AD vérifié indisponible.");
        else if (source.LocalTarget)
            snapshot = PowerShellReceiptEvidence.Read(source.Domain, source.Dc, source.ComputerGuid, true, module,
                (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload());
        else snapshot = ReadBoundWindowsEvidence(source.Domain, source.Dc, source.ComputerGuid!, source.Receipt.Computer,
            source.Receipt.Computer, source.Receipt.NewName, source.Receipt.Id, "restart", source.MachineId, source.Sha256);
        return new(snapshot.ActiveName ?? "", snapshot.ConfiguredName ?? "", snapshot.Domain ?? "", snapshot.PartOfDomain == true,
            snapshot.DomainRole ?? -1, snapshot.MachineId ?? "", snapshot.BootUtc ?? default, snapshot.AdGuid, snapshot.AdName,
            source.LocalTarget, DateTimeOffset.UtcNow, snapshot.Error, snapshot.RemoteProof, snapshot.AdOu, snapshot.AdProtected);
    }

    RestartNativeResult IReceiptRestartEnvironment.Send(RestartCommand command)
    {
        ReceiptRestartRules.ValidateCommand(command);
        if (!OperatingSystem.IsWindows()) return new("refused", "Redémarrage natif indisponible sur ce système.");
        RestartReceiptSnapshot current;
        try
        {
            current = ((IReceiptRestartEnvironment)this).ReadSource(command.ReceiptId);
            if (!RemoteWindowsEvidenceProtocol.Same(current.Sha256, command.ReceiptSha256)
                || !RemoteWindowsEvidenceProtocol.Same(current.MachineId, command.MachineId))
                throw ReceiptRestartRules.Refused("Le reçu historique ne correspond plus à la demande de redémarrage.");
            RequireNativeRestartAdmission(current, command.AuthorizationConfigurationSha256!);
        }
        catch (Exception) { return new("refused", "Configuration, politique ou reçu modifié avant envoi : aucun redémarrage demandé."); }
        void BeforeRequest()
        {
            RequireNativeRestartAdmission(current, command.AuthorizationConfigurationSha256!);
            if (current.PartialRenameMove)
            {
                var module = ResolveAdModulePath() ?? throw ReceiptRestartRules.Refused("Module AD vérifié absent avant redémarrage du parent 89.");
                var observed = PowerShellReceiptEvidence.Read(current.Domain, current.Dc, current.ComputerGuid, false, module,
                    (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload());
                if (observed.Error is not null || observed.DomainController != false
                    || !RemoteWindowsEvidenceProtocol.Same(observed.AdGuid, current.ComputerGuid)
                    || !RemoteWindowsEvidenceProtocol.Same(observed.AdName, current.Receipt.NewName)
                    || !RemoteWindowsEvidenceProtocol.Same(observed.AdOu, current.InitialOu)
                    || observed.AdProtected != current.InitialProtected)
                    throw ReceiptRestartRules.Refused("GUID, nom, OU source ou protection du parent 89 modifiés : aucun redémarrage envoyé.");
                RequireNativeRestartAdmission(current, command.AuthorizationConfigurationSha256!);
            }
        }
        if (command.LocalTarget) return SendLocalRestart(command, BeforeRequest);
        if (fallbackCredentials is not IWindowsCredentialSource source)
            return new("refused", "Le redémarrage distant exige le compte AD explicite déjà utilisé pour sa preuve Windows.");
        try
        {
            using var credential = source.AcquireForDiagnostic();
            if (credential is null) return new("refused", "Compte AD explicite indisponible : aucune tâche de redémarrage créée.");
            var raw = taskTransport as ISystemDiagnosticTaskTransport;
            if (raw is null && taskTransport is not null) return new("refused", "Transport SYSTEM indisponible : aucune tâche créée.");
            raw ??= new TaskSchedulerComTransport();
            using var bounded = new BoundedSystemDiagnosticTransport(raw, taskTransport is null);
            return new RemoteRestartTask(bounded, taskGpRoot ?? ReceiptGpRoot(), protectJournal: folder =>
            { if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder); }, beforeRequest: BeforeRequest).Run(command, credential);
        }
        catch (Exception) { return new("uncertain", "Le transport du redémarrage distant n’a pas confirmé sa réponse : aucun nouvel envoi pour ce boot."); }
    }

    private static RestartNativeResult SendLocalRestart(RestartCommand command, Action beforeRequest)
    {
        var sent = false;
        try
        {
            var start = new ProcessStartInfo(PowerShellPath)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true,
                RedirectStandardOutput = true, RedirectStandardError = true, StandardInputEncoding = new UTF8Encoding(false),
            };
            foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
                Convert.ToBase64String(Encoding.Unicode.GetBytes(ReceiptRestartScript.LocalSource)) }) start.ArgumentList.Add(arg);
            using var process = Process.Start(start);
            if (process is null) return new("refused", "Le processus de redémarrage n’a pas démarré.");
            using var job = OwnedMutationJob.Attach(process); // The constant worker waits for stdin until owned.
            var output = process.StandardOutput.ReadToEndAsync(); var errors = process.StandardError.ReadToEndAsync();
            beforeRequest(); // A process waiting for stdin has not received any authority to restart.
            sent = true; process.StandardInput.Write(JsonSerializer.Serialize(command)); process.StandardInput.Close();
            if (!process.WaitForExit(20000))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return new("uncertain", "Windows n’a pas rendu sa réponse avant fermeture du worker ; le redémarrage peut être engagé. Aucun second envoi pour ce boot.");
            }
            _ = output.GetAwaiter().GetResult(); _ = errors.GetAwaiter().GetResult();
            return process.ExitCode switch
            {
                0 => new("accepted", "Windows a accepté la demande explicite de redémarrage ; son effet reste à vérifier après boot. Le résultat du reçu métier est conservé."),
                96 => new("refused", "Identité ou boot non conforme : le worker n’a pas appelé Restart-Computer."),
                _ => new("uncertain", "Le worker n’a pas confirmé l’acceptation : aucun succès de redémarrage déduit, aucun nouvel envoi pour ce boot."),
            };
        }
        catch (Exception) { return new(sent ? "uncertain" : "refused", sent ? "Réponse de redémarrage perdue après envoi ; aucun second envoi pour ce boot." : "Le worker n’a reçu aucune demande ; aucun redémarrage envoyé."); }
    }
}
