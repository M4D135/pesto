using System.Text.RegularExpressions;

internal sealed record RestoreObservation(string Uuid, string Guid, string Computer, string ActiveName, string ConfiguredName,
    string Domain, bool Member, int Role, bool Elevated, bool SecureChannel, string AdName, string Ou, bool Protected, long Uac,
    bool OriginalNameAvailable, string ReceiptId, string ReceiptKind, string ReceiptStatus, string ReceiptComputer,
    string ReceiptNewName, bool ReceiptRestartRequired, bool ExplicitCredential, string Confirmation, string ReturnPlan,
    bool RenameMoveReturnConfirmed = false);

internal static class RestoreNamePolicy
{
    public const string Uuid = "9b2ad4f0-0506-4f58-aed2-c43ac1973516";
    public const string Guid = "b4797c9c-d790-4797-bf71-424a57acb36e";
    public const string OriginalName = "P111301VA765158";
    public static string Domain => LabDomain.Name;
    public static string Paris => "OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab," + LabDomain.Dn;
    public const string Confirmation = "RESTORE ORIGINAL NAME P111301VA765158";
    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    public static void Validate(RestoreObservation o)
    {
        if (!Same(o.Uuid, Uuid) || !Same(o.Guid, Guid)) throw new InvalidOperationException("Restore is restricted to the recorded VM and AD GUID.");
        if (!o.Member || !Same(o.Domain, Domain) || o.Role != 1 || !o.Elevated || !o.SecureChannel)
            throw new InvalidOperationException("Elevated local domain member with healthy secure channel required.");
        var recordedRenameMove = o.ReceiptKind == "renameMove" && o.ReceiptId == RestoreRenameMovePolicy.SourceReceiptId
            && Same(o.Computer, RestoreRenameMovePolicy.CurrentName) && o.RenameMoveReturnConfirmed;
        var normalRename = o.ReceiptKind == "rename" && !o.RenameMoveReturnConfirmed
            && Regex.IsMatch(o.Computer, "^P111301VA765[0-9]{3}$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if ((!normalRename && !recordedRenameMove)
            || Same(o.Computer, OriginalName) || !Same(o.ActiveName, o.Computer) || !Same(o.ConfiguredName, o.Computer) || !Same(o.AdName, o.Computer))
            throw new InvalidOperationException("Current local and AD names must agree; no pending rename or replay.");
        if (!Same(o.Ou, Paris) || o.Protected || o.Uac != 4096 || !o.OriginalNameAvailable)
            throw new InvalidOperationException("Recorded Paris OU/protection/workstation state and free original name required.");
        if (!Regex.IsMatch(o.ReceiptId, "^receipt-[a-fA-F0-9]{32}$", RegexOptions.CultureInvariant)
            || o.ReceiptStatus != "succeeded" || o.ReceiptRestartRequired
            || !Same(o.ReceiptComputer, OriginalName) || !Same(o.ReceiptNewName, o.Computer))
            throw new InvalidOperationException("The exact Pesto rename receipt must first be reconciled after reboot.");
        if (!o.ExplicitCredential || o.Confirmation != Confirmation || o.ReturnPlan.Length < 20)
            throw new InvalidOperationException("Explicit native AD credential, distinct restore confirmation and return plan required.");
    }
}
