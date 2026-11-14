using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationPreparationDisclosure, IMutationEntraPreparation
{
    private readonly object entraGate = new();
    private readonly Dictionary<string, (EntraRenameAuthorization Authorization, string? ReceiptId)> entraAuthorizations = [];

    public IReadOnlyList<string> PreparationNotes(string kind, string computer) => kind is not ("rename" or "renameMove") ? []
        : ["L’état Entra est observé avant confirmation puis relu. Un retrait exige un poste hybride, EntraPolicy=HybridOnly et l’accord explicite du plan.",
           "La réinscription hybride reste à vérifier séparément ; aucun redémarrage ni second retrait implicite.",
           computer.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase) ? "Diagnostic Entra local avant confirmation, sans retrait."
               : "Le diagnostic distant crée une tâche SYSTEM temporaire et sa preuve, via le compte AD explicite ; aucune modification AD."];

    public EntraRenameAuthorization PrepareEntra(EntraPreparationRequest request)
    {
        MutationSessionGuard.RequireWritableSession();
        EntraPreparationRules.ValidateRequest(request);
        if (!OperatingSystem.IsWindows()) throw new PestoException("entra.platform", "Préparation native Entra indisponible hors Windows.");
        var binding = new MutationRequest(request.Kind, request.Computer, request.ComputerGuid, request.NewName, request.SourceOu,
            request.Domain, request.Dc, "entra-preparation", "entra-" + Guid.NewGuid().ToString("N"), request.SourceOu, ConfigurationSha256: request.ConfigurationSha256);
        using var pin = PinConfirmedConfiguration(binding);
        var policy = ReadEntraPolicy(request.ConfigurationSha256);
        var baseline = ReadWindowsBaselineForEntra(request); RequireEntraIdentity(request, baseline);
        var state = ReadEntraState(request.Computer, request.Domain, binding.ReceiptId);
        EntraPreparationRules.RequireAllowed(state, policy);
        var now = DateTimeOffset.UtcNow;
        var authorization = new EntraRenameAuthorization(Guid.NewGuid().ToString("N"), request, state, policy, baseline.MachineId!, now, now.AddMinutes(5));
        lock (entraGate)
        {
            foreach (var key in entraAuthorizations.Where(p => p.Value.Authorization.ExpiresAt <= now).Select(p => p.Key).ToArray()) entraAuthorizations.Remove(key);
            if (entraAuthorizations.Count >= 2000) throw new PestoException("entra.limit", "Trop de préparations Entra.");
            entraAuthorizations.Add(authorization.Token, (authorization, null));
        }
        return authorization;
    }

    // After the complete Windows/AD baseline, before the business receipt. This hook never leaves Entra.
    private string? EntraRenameRefusal(MutationRequest request, NativeReceiptSnapshot baseline)
    {
        if (request.Kind is not ("rename" or "renameMove"))
            return request.Entra is null && !request.EntraLeaveConfirmed ? null : "Jonction et déplacement seul ne peuvent autoriser un retrait Entra.";
        try
        {
            var a = RequireEntraAuthorization(request); RequireEntraIdentity(a.Request, baseline);
            if (!string.Equals(baseline.MachineId, a.MachineId, StringComparison.OrdinalIgnoreCase)) return "Identité Windows différente de l’aperçu Entra.";
            return ReadEntraState(request.Computer, request.Domain, request.ReceiptId) == a.State ? null
                : "L’état Entra a changé : préparez et confirmez un nouveau plan ; aucun retrait ni renommage.";
        }
        catch (Exception error) { return "Préparation Entra non confirmée : " + Short(error.Message); }
    }

    // AFTER durable receipt + coordination + final guards, outside any catch promising no native command.
    private MutationOutcome? PrepareEntraBeforeRename(MutationRequest request, NativeReceiptSnapshot baseline, string receiptPath)
    {
        if (request.Kind is not ("rename" or "renameMove")) return null;
        try
        {
            var a = RequireEntraAuthorization(request); RequireEntraIdentity(a.Request, baseline);
            if (!string.Equals(a.MachineId, baseline.MachineId, StringComparison.OrdinalIgnoreCase)) return Refused(96, "Identité Windows modifiée.");
            using var document = JsonDocument.Parse(ReadReceiptBytes(receiptPath)); var saved = document.RootElement;
            if (!Matches(saved, "ReceiptId", request.ReceiptId) || !Matches(saved, "PlanId", request.PlanId)
                || !Matches(saved, "Computer", request.Computer) || !Matches(saved, "ComputerGuid", request.ComputerGuid)
                || !Matches(saved, "ConfigurationSha256", request.ConfigurationSha256))
                return Refused(96, "Le reçu préalable ne correspond pas au plan Entra ; aucun retrait.");
            if (!a.LeaveRequired)
                return ReadEntraState(request.Computer, request.Domain, request.ReceiptId) == "adOnly" ? null
                    : Refused(96, "L’état AD seul n’est plus confirmé ; aucun retrait autorisé par ce plan.");
            if (SavedText(saved, "Entra") != "Requested") return Refused(96, "Effet Entra Requested non durable ; aucun retrait.");
            var evidenceRoot = Path.Combine(ReceiptGpRoot(), "V2", "entra");
            RequireNoReparsePoint(evidenceRoot); Directory.CreateDirectory(evidenceRoot); RequireNoReparsePoint(evidenceRoot);
            if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(evidenceRoot);
            var command = new EntraLeaveCommand(request.ReceiptId, request.PlanId, Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant(),
                a.Request, a.MachineId, DateTimeOffset.UtcNow);
            var result = new EntraLeaveTransaction(EntraEvidenceStore()).Execute(command, new PowerShellEntraExecution(fallbackCredentials, taskTransport));
            if (result.Effect == "Confirmed" && !result.MayStillRun) return null;
            return result.Effect == "NotRequested" && !result.MayStillRun ? Refused(96, result.Message) : Uncertain(97, result.Message);
        }
        catch (Exception error)
        {
            try
            {
                if (EntraEvidenceStore().Read(request.ReceiptId) is null) return Refused(96, "Intention Entra non enregistrable avant envoi : " + Short(error.Message));
            }
            catch (Exception) { }
            return Uncertain(97, "Preuve Entra interrompue ou préexistante ; aucun renommage ni second retrait.");
        }
    }

    // Wrap Send and PersistFinalReceipt: a real/possible leave can never become a no-effect failure.
    private MutationOutcome PreserveEntraEffects(MutationRequest request, MutationOutcome outcome)
    {
        if (request.Entra?.LeaveRequired != true) return outcome;
        var effect = CurrentEntraEffect(request, out _);
        if (outcome.Status == MutationStatus.Failed && effect is "Requested" or "Confirmed" or "Uncertain")
            return new(MutationStatus.Uncertain, 97, Short(outcome.Message + " Le retrait Entra a pu agir (effet " + effect
                + ") ; réinscription à vérifier séparément, aucun rejeu."), outcome.RestartRequired, outcome.ObservedGuid);
        return effect == "Confirmed" ? outcome with { Message = Short(outcome.Message + " Retrait Entra confirmé ; réinscription hybride à vérifier séparément.") } : outcome;
    }

    private static string InitialEntraEffect(MutationRequest request) => request.Entra is null ? "NotRequested" : request.Entra.LeaveRequired ? "Requested" : "Skipped";
    private void ApplyEntraReceipt(JsonObject stored, MutationRequest request)
    {
        var effect = CurrentEntraEffect(request, out var snapshot);
        if (stored["Entra"]?.GetValue<string>() == "Confirmed") effect = "Confirmed";
        stored["Entra"] = effect; stored["EntraEvidenceId"] = request.Entra?.LeaveRequired == true ? request.ReceiptId : null;
        stored["EntraEvidenceSha256"] = snapshot?.Sha256; stored["EntraMayStillRun"] = snapshot?.Event.MayStillRun ?? false;
        stored["EntraReenrollmentPending"] = effect == "Confirmed";
    }
    private string CurrentEntraEffect(MutationRequest request, out EntraLeaveSnapshot? snapshot)
    {
        snapshot = null;
        if (request.Entra?.LeaveRequired != true) return InitialEntraEffect(request);
        try { snapshot = EntraEvidenceStore().Read(request.ReceiptId); return snapshot?.Event.Effect ?? "NotRequested"; }
        catch (Exception) { return "Uncertain"; }
    }

    private EntraRenameAuthorization RequireEntraAuthorization(MutationRequest request)
    {
        var a = request.Entra ?? throw new PestoException("entra.required", "Préparation Entra avant confirmation requise.");
        lock (entraGate)
        {
            if (!entraAuthorizations.TryGetValue(a.Token, out var saved) || !ReferenceEquals(saved.Authorization, a)
                || saved.ReceiptId is not null && saved.ReceiptId != request.ReceiptId || a.ExpiresAt <= DateTimeOffset.UtcNow)
                throw new PestoException("entra.stale", "Autorisation Entra étrangère, expirée ou consommée.");
            var expected = new EntraPreparationRequest(request.Kind, request.Computer, request.ComputerGuid ?? "", request.NewName ?? "",
                request.Domain, request.Dc, request.SourceOu ?? "", request.ConfigurationSha256 ?? "");
            if (a.Request != expected || request.EntraLeaveConfirmed != a.LeaveRequired)
                throw new PestoException("entra.confirmation", "Le plan, l’identité ou la confirmation Entra ne correspondent pas.");
            if (ReadEntraPolicy(request.ConfigurationSha256!) != a.Policy) throw new PestoException("entra.changed", "Politique Entra modifiée.");
            EntraPreparationRules.RequireAllowed(a.State, a.Policy); entraAuthorizations[a.Token] = (a, request.ReceiptId); return a;
        }
    }
    private static void RequireEntraIdentity(EntraPreparationRequest request, NativeReceiptSnapshot baseline)
    {
        if (baseline.Error is not null || !Guid.TryParse(baseline.MachineId, out var machine) || machine == Guid.Empty
            || baseline.DomainController != false || baseline.DomainRole is not (1 or 3) || baseline.PartOfDomain != true
            || !string.Equals(baseline.Domain, request.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.ActiveName, request.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.ConfiguredName, request.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.AdGuid, request.ComputerGuid, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.AdName, request.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.AdOu, request.SourceOu, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("entra.identity", "GUID, noms Windows/AD, domaine, OU et rôle non prouvés ensemble ; aucun retrait.");
    }
    private string ReadEntraPolicy(string hash)
    {
        if (v1InstallationPath is null) throw new IOException("Configuration Entra absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json"); RequireNoReparsePoint(path);
        if (new FileInfo(path).Length is < 1 or > 1048576) throw new IOException("Configuration Entra invalide.");
        var bytes = File.ReadAllBytes(path);
        if (MutationPolicyGuard.ConfigurationRefusal(bytes, hash) is { } changed) throw new IOException(changed);
        return EntraPreparationRules.ReadPolicy(Encoding.UTF8.GetString(bytes).TrimStart('\uFEFF'));
    }
    private string ReadEntraState(string computer, string domain, string traceId)
    {
        if (!OperatingSystem.IsWindows()) return "unknown";
        if (!computer.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase))
        {
            if (fallbackCredentials is not IWindowsCredentialSource source) return "unknown";
            using var credential = source.AcquireForDiagnostic(); if (credential is null) return "unknown";
            var raw = taskTransport as ISystemDiagnosticTaskTransport;
            if (raw is null && taskTransport is not null) return "unknown";
            raw ??= new TaskSchedulerComTransport();
            using var bounded = new BoundedSystemDiagnosticTransport(raw, taskTransport is null);
            var result = new EntraDiagnosticTask(bounded, taskGpRoot ?? ReceiptGpRoot()).Read(computer, domain, traceId, credential);
            return result.TaskStateUncertain ? "unknown" : result.ResultCode switch { 0 => "adOnly", 43 => "hybrid", _ => "unknown" };
        }
        try
        {
            var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32", "dsregcmd.exe");
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            start.ArgumentList.Add("/status");
            using var process = Process.Start(start); if (process is null) return "unknown";
            var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(90000)) { try { process.Kill(entireProcessTree: true); } catch (Exception) { } return "unknown"; }
            _ = error.GetAwaiter().GetResult(); return EntraPreparationRules.State(process.ExitCode, output.GetAwaiter().GetResult());
        }
        catch (Exception) { return "unknown"; }
    }
    private EntraLeaveEvidence EntraEvidenceStore() => new(ReceiptGpRoot(), ConfigurationAccessMode.Live);

    public EntraBarrierEvidence ReadEntraBarrier(string receiptId)
    {
        var evidence = EntraEvidenceStore(); var result = evidence.ReadBarrier(receiptId);
        if (!result.CanAcknowledge) return result;
        try
        {
            if (evidence.Read(receiptId) is { } snapshot)
            {
                using var receipt = JsonDocument.Parse(ReadReceiptBytes(ReceiptPath(receiptId)));
                var saved = receipt.RootElement; var command = snapshot.Event.Command; var request = command.Request;
                if (!Matches(saved, "ReceiptId", command.ReceiptId) || !Matches(saved, "PlanId", command.PlanId)
                    || !Matches(saved, "Kind", request.Kind) || !Matches(saved, "Computer", request.Computer)
                    || !Matches(saved, "NewName", request.NewName) || !Matches(saved, "ComputerGuid", request.ComputerGuid)
                    || !Matches(saved, "Domain", request.Domain) || !Matches(saved, "MachineId", command.MachineId)
                    || !Matches(saved, "ConfigurationSha256", request.ConfigurationSha256)
                    || SavedText(saved, "EntraEvidenceId") != receiptId)
                    return new(false, "La preuve Entra est liée à un autre reçu ou à une autre identité.", snapshot.Sha256);
                return result;
            }
            var candidates = new List<string> { ReceiptPath(receiptId) };
            if (Guid.TryParse(receiptId, out var legacy)) candidates.Add(Path.Combine(ReceiptGpRoot(), "Interventions", legacy.ToString("N") + ".json"));
            foreach (var path in candidates.Where(File.Exists))
            {
                using var saved = JsonDocument.Parse(SharedCoordinationProtocol.ReadBounded(path, ReceiptAcknowledgementSource.MaximumBytes));
                if (SavedText(saved.RootElement, "Entra") is "Requested" or "Uncertain")
                    return new(false, "Effet Entra conservé sans preuve native de fin ; inspection requise avant acquittement.", result.EvidenceSha256);
            }
            return result;
        }
        catch (Exception) { return new(false, "Effet Entra illisible : aucun acquittement.", "invalid"); }
    }
    public EntraBarrierEvidence InspectEntraBarrier(string receiptId)
    {
        MutationSessionGuard.RequireWritableSession();
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        var evidence = EntraEvidenceStore();
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) return new(false, "Une mutation ou un acquittement détient GP ; aucune inspection concurrente.", "busy");
            var snapshot = evidence.Read(receiptId); if (snapshot is null) return ReadEntraBarrier(receiptId);
            var result = new PowerShellEntraExecution(fallbackCredentials, taskTransport)
                .Inspect(snapshot.Event.Command, snapshot, evidence.ContainsPhase(receiptId, "TaskDeleted"), ReceiptGpRoot());
            if (result.MayStillRun) return new(false, result.Message, snapshot.Sha256);
            _ = evidence.Append(snapshot, "Inspected", snapshot.Event.Effect, false); // Preserve the actual historical effect.
            return ReadEntraBarrier(receiptId);
        }
        catch (Exception) { return new(false, "Inspection Entra non confirmée ; aucune preuve remplacée.", "invalid"); }
        finally { if (owned) mutex.ReleaseMutex(); }
    }
    private string? EntraEvidenceAllowsReconciliation(JsonElement saved)
    {
        var effect = SavedText(saved, "Entra"); if (effect is null or "NotRequested" or "Skipped") return null;
        if (effect != "Confirmed")
        {
            var receiptId = SavedText(saved, "ReceiptId");
            return receiptId is not null && ReadEntraBarrier(receiptId).CanAcknowledge
                ? "Le résultat Entra reste incertain et n’est pas validé. La fin du travailleur est prouvée ; un acquittement explicite avec motif peut être préparé."
                : "Le retrait Entra reste demandé ou incertain ; sa fin doit être inspectée avant tout acquittement.";
        }
        var id = SavedText(saved, "ReceiptId");
        if (id is null || !ReadEntraBarrier(id).CanAcknowledge) return "Fin du travailleur Entra non confirmée.";
        try { return EntraEvidenceStore().Read(id)?.Event.Effect == "Confirmed" ? null : "Effet Entra sans sa preuve liée."; }
        catch (Exception) { return "Preuve Entra illisible ; aucune réussite déduite."; }
    }
}
