using System.Text.Json;

namespace Pesto.Engine;

/// <summary>LocalTarget stays factual. A remote observation needs its own closed SYSTEM proof, never a fabricated local flag.</summary>
public static class ReceiptWindowsEvidence
{
    public static string? IdentityRefusal(ReceiptReconciliationObservation e)
    {
        if (!e.MachineIdentityMatches) return "L’identité Windows du poste ciblé ne correspond pas à la preuve initiale.";
        if (e.LocalTarget) return e.RemoteWindowsProof is null ? null : "Une preuve distante ne peut pas remplacer une observation locale.";
        if (e.Receipt.Kind == "join") return "La jonction reste strictement locale.";
        if (e.RemoteWindowsProof is not { } proof) return "Preuve Windows distante complète absente ; les anciens reçus sans baseline restent non vérifiables automatiquement.";
        try
        {
            var w = RemoteWindowsEvidenceProtocol.ValidateProof(proof);
            if (proof.Request.Purpose != "reconciliation" || proof.Request.ReceiptId != e.Receipt.Id
                || !RemoteWindowsEvidenceProtocol.Same(proof.Request.ReceiptSha256, e.ReceiptSha256)
                || !RemoteWindowsEvidenceProtocol.Same(proof.Request.ExpectedAdGuid, e.ExpectedGuid)
                || !RemoteWindowsEvidenceProtocol.Same(proof.Request.Domain, e.Domain)
                || !RemoteWindowsEvidenceProtocol.Same(w.ActiveName, e.WindowsActiveName)
                || !RemoteWindowsEvidenceProtocol.Same(w.ConfiguredName, e.WindowsConfiguredName)
                || !RemoteWindowsEvidenceProtocol.Same(w.Domain, e.WindowsDomain)
                || w.BootUtc != e.CurrentBootUtc || w.PartOfDomain != e.WindowsPartOfDomain || w.SecureChannel != e.SecureChannel)
                return "La preuve distante n’est pas liée aux octets du reçu et aux observations publiées.";
            return null;
        }
        catch (Exception) { return "Preuve Windows distante incomplète, modifiée ou nettoyage non confirmé."; }
    }

    public static bool RemoteBaselineMatches(JsonElement receipt)
    {
        try
        {
            string? Text(string key) => receipt.TryGetProperty(key, out var node) && node.ValueKind == JsonValueKind.String ? node.GetString() : null;
            if (!receipt.TryGetProperty("LocalTarget", out var local) || local.ValueKind != JsonValueKind.False
                || !receipt.TryGetProperty("WindowsBaselineProof", out var node) || node.ValueKind != JsonValueKind.Object) return false;
            var proof = RemoteWindowsEvidenceProtocol.ReadProof(node);
            var w = RemoteWindowsEvidenceProtocol.ValidateProof(proof);
            if (proof.Request.Purpose is not ("baseline" or "continuation") || proof.Request.ReceiptId != Text("ReceiptId")
                || !RemoteWindowsEvidenceProtocol.Same(proof.Request.ExpectedAdGuid, Text("ComputerGuid"))
                || !RemoteWindowsEvidenceProtocol.Same(w.MachineId, Text("MachineId"))
                || !RemoteWindowsEvidenceProtocol.Same(w.ActiveName, Text("Computer"))
                || !RemoteWindowsEvidenceProtocol.Same(w.ConfiguredName, Text("Computer"))
                || !RemoteWindowsEvidenceProtocol.Same(w.Domain, Text("Domain"))
                || !DateTimeOffset.TryParse(Text("InitialBootUtc"), out var boot) || boot != w.BootUtc) return false;
            if (proof.Request.Purpose == "continuation"
                && !RemoteWindowsEvidenceProtocol.Same(proof.Request.ReceiptSha256, Text("ParentReceiptSha256"))) return false;
            return Text("Kind") is "rename" or "renameMove" || Text("Kind") == "move" && proof.Request.Purpose == "continuation";
        }
        catch (Exception) { return false; }
    }

    public static bool RemoteReconciliationMatches(JsonElement receipt, JsonElement reconciliation)
    {
        try
        {
            static string? Text(JsonElement parent, string key) => parent.TryGetProperty(key, out var node) && node.ValueKind == JsonValueKind.String ? node.GetString() : null;
            static bool? Flag(JsonElement parent, string key) => parent.TryGetProperty(key, out var node) && node.ValueKind is JsonValueKind.True or JsonValueKind.False ? node.GetBoolean() : null;
            if (Flag(receipt, "LocalTarget") != false || !RemoteBaselineMatches(receipt)
                || !reconciliation.TryGetProperty("RemoteWindowsProof", out var remote)) return false;
            var proof = RemoteWindowsEvidenceProtocol.ReadProof(remote); var windows = RemoteWindowsEvidenceProtocol.ValidateProof(proof);
            return proof.Request.Purpose == "reconciliation" && proof.Request.ReceiptId == Text(receipt, "ReceiptId")
                && RemoteWindowsEvidenceProtocol.Same(proof.Request.ReceiptSha256, Text(reconciliation, "ReceiptSha256"))
                && RemoteWindowsEvidenceProtocol.Same(proof.Request.ExpectedAdGuid, Text(receipt, "ComputerGuid"))
                && RemoteWindowsEvidenceProtocol.Same(windows.MachineId, Text(receipt, "MachineId"))
                && RemoteWindowsEvidenceProtocol.Same(windows.Domain, Text(receipt, "Domain"))
                && RemoteWindowsEvidenceProtocol.Same(windows.Domain, Text(reconciliation, "WindowsDomain"))
                && RemoteWindowsEvidenceProtocol.Same(windows.ActiveName, Text(reconciliation, "WindowsActiveName"))
                && RemoteWindowsEvidenceProtocol.Same(windows.ConfiguredName, Text(reconciliation, "WindowsConfiguredName"))
                && RemoteWindowsEvidenceProtocol.Same(windows.ActiveName, Text(receipt, "NewName"))
                && DateTimeOffset.TryParse(Text(reconciliation, "CurrentBootUtc"), out var boot) && boot == windows.BootUtc
                && windows.PartOfDomain == Flag(reconciliation, "WindowsPartOfDomain") && windows.SecureChannel == Flag(reconciliation, "SecureChannel")
                && Flag(reconciliation, "MachineIdentityMatches") == true;
        }
        catch (Exception) { return false; }
    }
}
