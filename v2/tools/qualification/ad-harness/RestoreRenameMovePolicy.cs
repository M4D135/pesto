using System.Text.RegularExpressions;

// Evidence for the one recorded renameMove campaign, never a general-purpose rollback grant.
internal sealed record RestoreRenameMoveProof(string Id, string Kind, string Status, int Code, string Computer,
    string NewName, string TargetOu, bool RestartRequired, DateTimeOffset Time, string ReceiptSha256,
    string? ExpectedGuid, string Domain, string? InitialOu, bool? InitialProtected,
    string? AdGuid, string? AdName, string? AdOu, bool? AdProtected, string? ActiveName, string? ConfiguredName,
    string? WindowsDomain, bool? Member, bool? SecureChannel, bool LocalTarget, bool MachineIdentityMatches,
    DateTimeOffset? InitialBootUtc, DateTimeOffset? CurrentBootUtc, string? Error);

internal static class RestoreRenameMovePolicy
{
    public const string SourceReceiptId = "receipt-50a635a9b3ee46138c9fc231bcff83af";
    public const string CurrentName = "P111301LY765715";
    public static string Lyon => "OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab," + LabDomain.Dn;

    public static void Validate(RestoreRenameMoveProof source, RestoreRenameMoveProof returned)
    {
        RequireCurrentIdentity(source);
        RequireCurrentIdentity(returned);
        if (source.Id != SourceReceiptId || source.Kind != "renameMove" || source.Code != 77
            || !Same(source.Computer, RestoreNamePolicy.OriginalName) || !Same(source.NewName, CurrentName)
            || !Same(source.InitialOu, RestoreNamePolicy.Paris) || !Same(source.TargetOu, Lyon)
            || source.InitialBootUtc is null || source.CurrentBootUtc is null || source.CurrentBootUtc <= source.InitialBootUtc)
            throw Refused();
        if (!Regex.IsMatch(returned.Id, "^receipt-[a-fA-F0-9]{32}$", RegexOptions.CultureInvariant)
            || Same(returned.Id, source.Id) || returned.Kind != "move" || returned.Code != 30
            || !Same(returned.Computer, CurrentName) || (returned.NewName.Length > 0 && !Same(returned.NewName, CurrentName))
            || !Same(returned.InitialOu, Lyon) || !Same(returned.TargetOu, RestoreNamePolicy.Paris)
            || returned.Time <= source.Time || returned.CurrentBootUtc != source.CurrentBootUtc)
            throw Refused();
    }

    public static void RequireUnchanged(RestoreRenameMoveProof source, RestoreRenameMoveProof returned,
        string sourceHash, string returnHash)
    {
        Validate(source, returned);
        if (!Same(source.ReceiptSha256, sourceHash) || !Same(returned.ReceiptSha256, returnHash)) throw Refused();
    }

    private static void RequireCurrentIdentity(RestoreRenameMoveProof proof)
    {
        if (proof.Status != "succeeded" || proof.RestartRequired
            || !Regex.IsMatch(proof.ReceiptSha256, "^[a-fA-F0-9]{64}$", RegexOptions.CultureInvariant)
            || !Same(proof.ExpectedGuid, RestoreNamePolicy.Guid) || !Same(proof.AdGuid, RestoreNamePolicy.Guid)
            || !Same(proof.Domain, RestoreNamePolicy.Domain) || !Same(proof.WindowsDomain, RestoreNamePolicy.Domain)
            || !Same(proof.AdName, CurrentName) || !Same(proof.AdOu, RestoreNamePolicy.Paris)
            || !Same(proof.ActiveName, CurrentName) || !Same(proof.ConfiguredName, CurrentName)
            || proof.InitialProtected != false || proof.AdProtected != false || proof.Member != true || proof.SecureChannel != true
            || !proof.LocalTarget || !proof.MachineIdentityMatches || !string.IsNullOrEmpty(proof.Error))
            throw Refused();
    }

    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    private static InvalidOperationException Refused() => new("The recorded renameMove and a later verified return move to Paris are required; no rename authorized.");
}
