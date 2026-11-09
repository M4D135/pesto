using System.Text.Json;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway
{
    private static NativeReceiptSnapshot UnknownWindows(string reason) => new(null, null, null, null, null, null, null, null, null, null, null, reason);

    /// <summary>Same complete baseline for Entra preparation and the eventual confirmed mutation. No command is replayed.</summary>
    private NativeReceiptSnapshot ReadWindowsBaselineForEntra(EntraPreparationRequest request) => ReadBoundWindowsEvidence(
        request.Domain, request.Dc, request.ComputerGuid, request.Computer, request.Computer, request.Computer,
        "entra-" + Guid.NewGuid().ToString("N"), "baseline");

    private NativeReceiptSnapshot ReadBoundWindowsEvidence(string domain, string? dc, string guid, string computer,
        string expectedActive, string expectedConfigured, string receiptId, string purpose,
        string? expectedMachineId = null, string? receiptSha256 = null)
    {
        try
        {
            var module = ResolveAdModulePath();
            if (module is null) return UnknownWindows("Module AD vérifié absent ; aucune preuve Windows/AD.");
            var payload = (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload();
            if (computer.Equals(Environment.MachineName, StringComparison.OrdinalIgnoreCase))
                return PowerShellReceiptEvidence.Read(domain, dc, guid, true, module, payload);
            if (!OperatingSystem.IsWindows() || fallbackCredentials is not IWindowsCredentialSource source)
                return UnknownWindows("La vérification distante exige Windows et le compte AD explicitement choisi dans cette session.");
            var request = new RemoteWindowsEvidenceRequest(receiptId, computer, domain, dc ?? domain, guid, expectedMachineId,
                receiptSha256, purpose, expectedActive, expectedConfigured);
            RemoteWindowsEvidenceProtocol.ValidateRequest(request);
            var before = PowerShellReceiptEvidence.Read(domain, dc, guid, false, module, payload);
            if (before.Error is not null || before.DomainController != false || before.AdProtected is null || before.AdOu is null
                || !RemoteWindowsEvidenceProtocol.Same(before.AdGuid, guid) || !RemoteWindowsEvidenceProtocol.Same(before.AdName, expectedConfigured))
                return UnknownWindows("L’identité AD par GUID, le nom ou la protection ne sont pas confirmés avant le diagnostic distant.");
            using var credential = source.AcquireForDiagnostic();
            if (credential is null) return UnknownWindows("Compte AD de la preuve distante indisponible ; aucun repli SSO.");
            var transport = taskTransport as ISystemDiagnosticTaskTransport;
            var owned = false;
            if (transport is null)
            {
                if (taskTransport is not null) return UnknownWindows("Le transport injecté ne permet pas la preuve SYSTEM.");
                transport = new TaskSchedulerComTransport(); owned = true;
            }
            using var bounded = new BoundedSystemDiagnosticTransport(transport, owned);
            using var resultFiles = new BoundedRemoteWindowsEvidenceFiles(new WindowsRemoteEvidenceFiles(credential), ownsInner: true);
            var result = new RemoteWindowsDiagnosticTask(bounded, resultFiles, ReceiptGpRoot(), protectJournal: folder =>
            {
                if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder);
            }).Read(request, credential);
            if (result.Proof is not { } proof) return UnknownWindows(result.Message);
            var windows = RemoteWindowsEvidenceProtocol.ValidateProof(proof);
            var after = PowerShellReceiptEvidence.Read(domain, dc, guid, false, module, payload);
            if (after.Error is not null || after.DomainController != false || after.AdProtected != before.AdProtected
                || !RemoteWindowsEvidenceProtocol.Same(after.AdGuid, before.AdGuid)
                || !RemoteWindowsEvidenceProtocol.Same(after.AdName, before.AdName) || !RemoteWindowsEvidenceProtocol.Same(after.AdOu, before.AdOu))
                return UnknownWindows("L’identité AD, l’OU ou la protection ont changé pendant le diagnostic distant ; aucune preuve utilisable.");
            return after with { BootUtc = windows.BootUtc, MachineId = windows.MachineId, ActiveName = windows.ActiveName,
                ConfiguredName = windows.ConfiguredName, Domain = windows.Domain, PartOfDomain = windows.PartOfDomain,
                SecureChannel = windows.SecureChannel, DomainRole = windows.DomainRole, RemoteProof = proof };
        }
        catch (Exception) { return UnknownWindows("La lecture Windows distante n’a pas fourni de preuve complète et liée ; aucun succès déduit."); }
    }

    private NativeReceiptSnapshot ReadMutationBaseline(MutationRequest request, string module, ProtectedWindowsCredential? credential, bool local)
    {
        if (!local && request.Kind is ("rename" or "renameMove"))
            return ReadBoundWindowsEvidence(request.Domain, request.Dc, request.ComputerGuid!, request.Computer,
                request.Computer, request.Computer, request.ReceiptId, "baseline");
        if (!local && request.Continuation is { } parent)
        {
            using var document = JsonDocument.Parse(ReadReceiptBytes(ReceiptPath(parent.ParentReceiptId)));
            if (!ReceiptWindowsEvidence.RemoteBaselineMatches(document.RootElement)) return UnknownWindows("Baseline distante du parent absente ou invalide.");
            return ReadBoundWindowsEvidence(request.Domain, request.Dc, request.ComputerGuid!, request.Computer,
                request.Computer, request.Computer, request.ReceiptId, "continuation", SavedText(document.RootElement, "MachineId"), parent.ParentReceiptSha256);
        }
        return PowerShellReceiptEvidence.Read(request.Domain, request.Dc, request.ComputerGuid, local, module, credential);
    }
}
