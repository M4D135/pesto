using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationJoinReservation
{
    private JoinReservationCoordinator? joinReservations;
    private string? reservationConfigurationSha256;
    private DateTimeOffset? reservationNameLeaseExpiresAt;
    private JoinReservationCoordinator ReservationRegistry => joinReservations ??= new(
        new JoinReservationStore(ReceiptGpRoot()), new PowerShellJoinReservationNative(ResolveAdModulePath,
            () => (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload(),
            () => (Path.Combine(v1InstallationPath ?? throw ReservationRefused("Configuration absente."), "cfg.json"),
                reservationConfigurationSha256 ?? throw ReservationRefused("Empreinte de configuration absente du plan.")),
            () => ReadPolicyRequirements().ExcludedGroupGuids, () => reservationNameLeaseExpiresAt));

    public static string ReservationWorkerScript => PowerShellJoinReservationNative.ConstantScript;

    private static PestoException ReservationRefused(string message) => new("reservation.evidence", message);
    private sealed record JoinReservationBinding(MutationRequest Request, MutationOutcome? Refusal = null);

    public IReadOnlyList<JoinReservationView> ListReservations() => ReservationRegistry.List();

    private T WithReservationMutex<T>(Func<T> operation)
    {
        MutationSessionGuard.RequireWritableSession();
        if (unavailableReason is not null) throw ReservationRefused(unavailableReason);
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw ReservationRefused("Une autre opération utilise le mutex GP : aucune commande de réservation lancée.");
            MutationSessionGuard.RequireWritableSession();
            return operation();
        }
        finally { reservationConfigurationSha256 = null; reservationNameLeaseExpiresAt = null; if (owned) mutex.ReleaseMutex(); }
    }

    private JoinReservationPolicy ReadReservationPolicy()
    {
        if (v1InstallationPath is null) throw ReservationRefused("Configuration de réservation absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json");
        RequireNoReparsePoint(path);
        if (new FileInfo(path).Length is < 1 or > ConfigurationDocument.MaximumBytes) throw ReservationRefused("Configuration de réservation illisible.");
        return JoinReservationPolicy.Read(File.ReadAllText(path, Encoding.UTF8));
    }

    private string ReservationConfigurationStamp()
    {
        if (v1InstallationPath is null) throw ReservationRefused("Configuration absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json");
        RequireNoReparsePoint(path);
        if (new FileInfo(path).Length is < 1 or > ConfigurationDocument.MaximumBytes) throw ReservationRefused("Configuration illisible.");
        return JoinReservationStore.Digest(File.ReadAllBytes(path));
    }

    private void RequireReservationConfiguration(JoinReservationReceipt receipt, bool requireEnabled = false)
    {
        var policy = ReadReservationPolicy();
        if ((requireEnabled && !policy.Enabled) || !JoinReservationStore.Same(policy.Domain, receipt.Domain)
            || !(JoinReservationStore.Same(policy.RootOu, receipt.TargetOu) || receipt.TargetOu.EndsWith("," + policy.RootOu, StringComparison.OrdinalIgnoreCase)))
            throw ReservationRefused("La configuration actuelle ne correspond pas au domaine, à la portée ou à la politique de cette réservation.");
    }

    public JoinReservationView InspectReservation(string reservationId) => WithReservationMutex(() =>
    {
        var receipt = ReservationRegistry.Read(reservationId);
        reservationConfigurationSha256 = ReservationConfigurationStamp();
        RequireReservationConfiguration(receipt);
        // A creation response can be lost before its GUID is persisted. Establish ownership from AD first;
        // never adopt a GUID merely because a linked join receipt happens to contain one.
        if (receipt.ComputerGuid is null && receipt.State is "pending" or "uncertain")
            receipt = ReservationRegistry.Inspect(reservationId).Receipt;
        RecoverLinkedReservationReceipts(receipt);
        return ReservationRegistry.Inspect(reservationId);
    });

    private void RecoverLinkedReservationReceipts(JoinReservationReceipt reservation)
    {
        var folder = Path.Combine(ReceiptGpRoot(), "V2", "receipts");
        RequireNoReparsePoint(folder);
        if (!Directory.Exists(folder)) return;
        var paths = Directory.EnumerateFiles(folder, "*.json", SearchOption.TopDirectoryOnly).Take(5001).ToArray();
        if (paths.Length > 5000) throw ReservationRefused("Trop de reçus à vérifier avant la reprise.");
        foreach (var path in paths)
        {
            using var document = JsonDocument.Parse(ReadReceiptBytes(path));
            var saved = document.RootElement;
            if (SavedText(saved, "ReservationId") != reservation.Id) continue;
            var id = SavedText(saved, "ReceiptId") ?? throw ReservationRefused("Reçu lié sans identité.");
            if (Path.GetFileName(path) != id + ".json") throw ReservationRefused("Nom du reçu lié différent de son identité.");
            RequireReservationParentIdentity(saved, reservation, id);
            ReservationRegistry.TrackLinkedReceipt(reservation.Id, id);
        }
    }

    public JoinReservationPreparation PrepareReservation(string reservationId, string action, string planId) => WithReservationMutex(() =>
    {
        if (action is not ("resumeJoin" or "release")) throw ReservationRefused("Action de réservation invalide.");
        var configurationSha256 = ReservationConfigurationStamp();
        var receipt = ReservationRegistry.Read(reservationId);
        RequireReservationConfiguration(receipt, requireEnabled: action == "resumeJoin");
        if (ReadV1Barriers() is { } blocked) throw ReservationRefused(blocked);
        RequireNoOtherReservation(receipt.Id);
        // A pending creation interrupted before linking its known GUID is recovered only after an explicit inspection.
        var view = ReservationRegistry.View(receipt);
        if (action == "release" ? !view.CanRelease : !view.CanResume)
            throw ReservationRefused("Une inspection explicite fraîche et concluante est requise avant la préparation.");
        foreach (var parent in receipt.JoinReceiptIds) LinkReservationToJoinReceipt(receipt, parent);
        var parents = ReadReservationParents(receipt);
        var preparation = ReservationRegistry.Prepare(reservationId, action, planId, parents, configurationSha256);
        var request = ReservationRequest(preparation.Authorization, "preparation-" + Guid.NewGuid().ToString("N"));
        if (ConfiguredPolicyRefusal(request) is { } policy) throw ReservationRefused(policy);
        if (ReadV2Barrier(request) is { } barrier) throw ReservationRefused(barrier);
        return preparation;
    });

    private static MutationRequest ReservationRequest(JoinReservationAuthorization a, string receiptId) =>
        new("join", a.Computer, a.ComputerGuid, a.Name, a.TargetOu, a.Domain, a.Dc, a.PlanId, receiptId,
            TargetOuGuid: a.TargetOuGuid, Reservation: a, ReservationRequired: a.Action != "release", ConfigurationSha256: a.ConfigurationSha256);

    private void RequireNoOtherReservation(string? except)
    {
        if (ReservationRegistry.List().Any(v => v.Receipt.Id != except && !JoinReservationStore.IsTerminal(v.Receipt.State)))
            throw ReservationRefused("Une réservation AD conservée ou incertaine doit être inspectée avant toute nouvelle mutation.");
    }

    /// <summary>Hook under the existing GP mutex, before V2 receipt barriers. It never creates an account.</summary>
    private string? ReservationBarrier(MutationRequest request)
    {
        try
        {
            if (request.Reservation is { } authorization)
            {
                if (authorization.Action != "resumeJoin") return "Une reprise join exige une autorisation native resumeJoin, jamais une autorisation de retrait.";
                ValidateReservationRequest(request, authorization);
                RequireNoOtherReservation(authorization.ReservationId);
            }
            else RequireNoOtherReservation(null);
            return null;
        }
        catch (Exception error) { return Short(error.Message); }
    }

    private void ValidateReservationRequest(MutationRequest request, JoinReservationAuthorization a)
    {
        if (!ReservationRegistry.IsAuthorized(a) || request.Kind != "join" || request.PlanId != a.PlanId
            || request.ConfigurationSha256 != a.ConfigurationSha256 || ReservationConfigurationStamp() != a.ConfigurationSha256
            || !JoinReservationStore.Same(request.Computer, a.Computer) || !JoinReservationStore.Same(request.NewName, a.Name)
            || !JoinReservationStore.Same(request.Domain, a.Domain) || !JoinReservationStore.Same(request.Dc, a.Dc)
            || !JoinReservationStore.Same(request.TargetOu, a.TargetOu) || !JoinReservationStore.Same(request.TargetOuGuid, a.TargetOuGuid)
            || !JoinReservationStore.Same(request.ComputerGuid, a.ComputerGuid))
            throw ReservationRefused("L’autorisation de réservation n’est plus liée au plan, à son GUID ou à sa portée.");
        var receipt = ReservationRegistry.Read(a.ReservationId);
        RequireReservationConfiguration(receipt, requireEnabled: a.Action != "release");
        var parents = ReadReservationParents(receipt);
        if (parents.Count != a.Parents.Count || parents.Any(p => !a.Parents.Any(expected => expected == p)))
            throw ReservationRefused("Un reçu de jonction lié a changé depuis la préparation : aucune commande envoyée.");
    }

    /// <summary>Only exact, hash-bound parent receipts may be crossed by a fresh native reservation grant.</summary>
    private bool IsReservationParentBarrier(MutationRequest request, JsonElement parent, string path)
    {
        if (request.Reservation is not { } a || !ReservationRegistry.IsAuthorized(a)) return false;
        var id = SavedText(parent, "ReceiptId");
        return id is not null && Path.GetFileName(path) == id + ".json" && SavedText(parent, "ReservationId") == a.ReservationId
            && a.Parents.Any(p => p.ReceiptId == id && p.Sha256 == JoinReservationStore.Digest(ReadReceiptBytes(path)));
    }

    /// <summary>A confirmed removal resolves only the exact old bytes listed in its durable receipt.
    /// The old join phase is never rewritten into a fictitious no-write failure or success.</summary>
    private bool HasResolvedReservationParent(JsonElement parent, string path)
    {
        try
        {
            var reservationId = SavedText(parent, "ReservationId");
            var id = SavedText(parent, "ReceiptId");
            if (!JoinReservationStore.IsId(reservationId) || id is null || Path.GetFileName(path) != id + ".json") return false;
            var r = ReservationRegistry.Read(reservationId!);
            return r.State is "released" or "gone" && !r.NeedsReview && r.ResolvedParents is not null
                && r.ResolvedParents.Any(p => p.ReceiptId == id && p.Sha256 == JoinReservationStore.Digest(ReadReceiptBytes(path)));
        }
        catch (Exception) { return false; }
    }

    private IReadOnlyList<JoinReservationParent> ReadReservationParents(JoinReservationReceipt reservation)
    {
        return reservation.JoinReceiptIds.Select(id =>
        {
            var bytes = ReadReceiptBytes(ReceiptPath(id));
            using var document = JsonDocument.Parse(bytes);
            RequireReservationParentIdentity(document.RootElement, reservation, id);
            return new JoinReservationParent(id, JoinReservationStore.Digest(bytes));
        }).ToArray();
    }

    private static void RequireReservationParentIdentity(JsonElement saved, JoinReservationReceipt r, string receiptId)
    {
        if (!Matches(saved, "ReceiptId", receiptId) || !Matches(saved, "Kind", "join")
            || !JoinReservationStore.Same(SavedText(saved, "NewName"), r.Name)
            || (!JoinReservationStore.Same(SavedText(saved, "Computer"), r.Computer) && !JoinReservationStore.Same(SavedText(saved, "Computer"), r.Name))
            || !JoinReservationStore.Same(SavedText(saved, "Domain"), r.Domain) || !JoinReservationStore.Same(SavedText(saved, "Dc"), r.Dc)
            || !JoinReservationStore.Same(SavedText(saved, "TargetOu"), r.TargetOu)
            || !JoinReservationStore.Same(SavedText(saved, "TargetOuGuid"), r.TargetOuGuid)
            || !JoinReservationStore.Same(SavedText(saved, "MachineId"), r.MachineId)
            || (SavedText(saved, "ComputerGuid") is { } guid && !JoinReservationStore.Same(guid, r.ComputerGuid))
            || (SavedText(saved, "ReservationId") is { } id && id != r.Id))
            throw ReservationRefused("Un reçu lié ne correspond pas à l’identité immuable de cette réservation.");
    }

    private void LinkReservationToJoinReceipt(JoinReservationReceipt reservation, string receiptId)
    {
        var path = ReceiptPath(receiptId);
        var bytes = ReadReceiptBytes(path);
        using var document = JsonDocument.Parse(bytes);
        RequireReservationParentIdentity(document.RootElement, reservation, receiptId);
        var saved = JsonNode.Parse(bytes)!.AsObject();
        if (saved["ReservationId"]?.GetValue<string>() == reservation.Id
            && JoinReservationStore.Same(saved["ComputerGuid"]?.GetValue<string>(), reservation.ComputerGuid)) return;
        saved["ReservationId"] = reservation.Id;
        saved["ComputerGuid"] = reservation.ComputerGuid;
        var json = saved.ToJsonString();
        WriteAtomic(path, json);
        AuditDurableReceipt(json); // only the join receipt, never the reservation receipt
    }

    /// <summary>Called only after confirmation, the durable join receipt, coordination, and clock checks.
    /// No engine preview, settings form, navigation or cancellation calls this method.</summary>
    private JoinReservationBinding BindJoinReservationBeforeSend(MutationRequest request, NativeReceiptSnapshot baseline, string receiptPath)
    {
        if (request.Kind != "join") return new(request);
        // Explicit reuse of an existing GUID never creates a reservation, even when ReserveNamesInAD is enabled.
        if (request.PrecreatedJoin is not null)
        {
            try { RequirePrecreatedAccount(request); return new(request); }
            catch (Exception) { return new(request, Refused(96, "Le compte précréé confirmé ne peut plus être validé : aucun compte créé ni jonction lancée.")); }
        }
        JoinReservationReceipt? reservation = null;
        var reservationMayHaveStarted = false;
        try
        {
            var policy = ReadReservationPolicy();
            if (request.Reservation is null && policy.Enabled != request.ReservationRequired)
                return new(request, Refused(96, "La politique de réservation a changé depuis le plan confirmé : préparez un nouveau plan, aucun compte créé."));
            if (request.Reservation is null && !policy.Enabled) return new(request);
            if (!policy.Enabled) return new(request, Refused(96, "La réservation AD n’est plus activée ; aucun compte repris."));
            if (!JoinReservationStore.IsHash(request.ConfigurationSha256) || ReservationConfigurationStamp() != request.ConfigurationSha256)
                return new(request, Refused(96, "La configuration a changé depuis la confirmation : aucune réservation créée."));
            reservationConfigurationSha256 = request.ConfigurationSha256;
            reservationNameLeaseExpiresAt = request.NameReservation?.ExpiresAt;
            if (!JoinReservationStore.IsGuid(baseline.MachineId) || baseline.BootUtc is null || baseline.PartOfDomain != false
                || !JoinReservationStore.Same(baseline.ActiveName, request.Computer)
                || !JoinReservationStore.Same(baseline.ConfiguredName, request.Computer))
                return new(request, Refused(96, "Identité Windows ou nom en attente non confirmé : aucune réservation créée."));
            JoinReservationAuthorization authorization;
            if (request.Reservation is { } existing)
            {
                ValidateReservationRequest(request, existing);
                reservation = ReservationRegistry.Read(existing.ReservationId);
                authorization = existing;
            }
            else
            {
                var folder = new JoinReservationStore(ReceiptGpRoot()).DirectoryPath;
                RequireNoReparsePoint(folder); Directory.CreateDirectory(folder);
                if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder);
                reservationMayHaveStarted = true;
                var created = ReservationRegistry.Create(request, baseline.MachineId!, () =>
                {
                    if (ConfiguredPolicyRefusal(request) is { } changedPolicy) throw ReservationRefused(changedPolicy);
                    if (JoinClockRefusal(request) is { } changedClock) throw ReservationRefused(changedClock.Message);
                    VerifyCoordinationBeforeSend(request);
                    VerifyNameReservationBeforeSend(request);
                });
                // The returned view may contain late, non-durable evidence when completion persistence failed.
                // Only facts actually stored in the reservation may be linked into the durable join receipt.
                reservation = ReservationRegistry.Read(created.Receipt.Id);
                LinkReservationToJoinReceipt(reservation, request.ReceiptId);
                if (created.Receipt.State != "reserved" || reservation.State != "reserved")
                    return new(request, reservation.State is "refused" or "taken"
                        ? Refused(96, "Aucun compte créé par cette tentative : " + reservation.Message)
                        : new(MutationStatus.Uncertain, 97, "Réservation non confirmée ; compte éventuel conservé, aucune jonction lancée. " + created.Receipt.Message,
                            false, reservation.ComputerGuid));
                authorization = ReservationRegistry.Prepare(reservation.Id, "initialJoin", request.PlanId, ReadReservationParents(reservation), request.ConfigurationSha256!).Authorization;
            }
            RequireReservationConfiguration(reservation, requireEnabled: true);
            if (!JoinReservationStore.IsGuid(reservation.ComputerGuid)) throw ReservationRefused("Le GUID de la réservation n’a pas été persisté.");
            RequireReservedAccountGroups(request, reservation.ComputerGuid!);
            VerifyCoordinationBeforeSend(request);
            // Consumes the native grant, rereads all ownership evidence, then persists joining before any local rename or join.
            reservation = ReservationRegistry.BeginJoin(authorization, request.ReceiptId);
            LinkReservationToJoinReceipt(reservation, request.ReceiptId);
            return new(request with { ComputerGuid = reservation.ComputerGuid, Reservation = authorization });
        }
        catch (Exception error)
        {
            return new(request, reservation is not null || reservationMayHaveStarted
                ? new(MutationStatus.Uncertain, 97, "Le compte réservé éventuel reste conservé ; aucune jonction supplémentaire. " + Short(error.Message), false, reservation?.ComputerGuid)
                : Refused(96, "La réservation n’a pas pu être préparée : aucune création confirmée. " + Short(error.Message)));
        }
        finally { reservationConfigurationSha256 = null; reservationNameLeaseExpiresAt = null; }
    }

    /// <summary>Once a reservation was created, a join refusal cannot be advertised as a zero-write failure.</summary>
    private MutationOutcome CompleteReservationJoin(MutationRequest request, MutationOutcome outcome)
    {
        if (request.Reservation is not { } a) return outcome;
        try
        {
            _ = ReservationRegistry.CompleteJoin(a.ReservationId, outcome);
            return outcome with { Status = outcome.Status == MutationStatus.Failed ? MutationStatus.Uncertain : outcome.Status,
                Code = outcome.Status == MutationStatus.Failed ? 97 : outcome.Code, ObservedGuid = a.ComputerGuid,
                Message = outcome.Status == MutationStatus.Failed ? "Jonction refusée (code natif " + outcome.Code
                    + ") après réservation : le compte AD créé reste conservé. Inspectez avant toute reprise ; aucun retrait automatique." : outcome.Message };
        }
        catch (Exception)
        {
            return new(MutationStatus.Uncertain, 97, "Le résultat de la jonction réservée ne peut pas être enregistré : compte conservé, aucune reprise automatique.",
                outcome.RestartRequired, a.ComputerGuid);
        }
    }

    public JoinReservationView ReleaseReservation(JoinReservationAuthorization authorization) => WithReservationMutex(() =>
    {
        if (authorization.Action != "release") throw ReservationRefused("Seul un plan de retrait explicite est admis ici.");
        var request = ReservationRequest(authorization, "reservation-release-" + Guid.NewGuid().ToString("N"));
        ValidateReservationRequest(request, authorization);
        reservationConfigurationSha256 = authorization.ConfigurationSha256;
        var receipt = ReservationRegistry.Read(authorization.ReservationId);
        RequireNoOtherReservation(receipt.Id);
        if (ReadV1Barriers() is { } old) throw ReservationRefused(old);
        if (ReadV2Barrier(request) is { } blocked) throw ReservationRefused(blocked);
        if (ConfiguredPolicyRefusal(request) is { } policy) throw ReservationRefused(policy);
        if (receipt.State != "gone" && receipt.ComputerGuid is { } guid) RequireReservedAccountGroups(request, guid);
        var folder = Path.Combine(ReceiptGpRoot(), "V2", "reservation-actions");
        RequireNoReparsePoint(folder); Directory.CreateDirectory(folder);
        if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder);
        var path = Path.Combine(folder, request.ReceiptId + ".json");
        var journal = new JsonObject
        {
            ["Schema"] = 1, ["ReceiptId"] = request.ReceiptId, ["ReservationId"] = receipt.Id, ["PlanId"] = request.PlanId,
            ["Kind"] = "reservationRelease", ["Phase"] = "Running", ["Utc"] = DateTimeOffset.UtcNow.ToString("o"),
            ["Domain"] = request.Domain, ["Computer"] = request.Computer, ["NewName"] = request.NewName,
            ["ComputerGuid"] = request.ComputerGuid, ["TargetOu"] = request.TargetOu, ["Dc"] = request.Dc,
            ["Coordination"] = CoordinationReceipt(request),
        };
        WriteAtomic(path, journal.ToJsonString());
        try { AcquireCoordination(request, path); }
        catch
        {
            journal["Phase"] = "Failed"; journal["Message"] = "Coordination refusée avant toute suppression AD.";
            WriteAtomic(path, journal.ToJsonString());
            AbortCoordinationBeforeSend(request);
            throw;
        }
        JoinReservationView result;
        try { result = ReservationRegistry.Release(authorization, () => VerifyCoordinationBeforeSend(request)); }
        catch
        {
            // A changed identity is a refusal before Remove. The account remains preserved; no auto-retry.
            journal["Phase"] = "Failed"; journal["Message"] = "Preuve changée avant suppression ; aucun Remove-ADComputer envoyé.";
            WriteAtomic(path, journal.ToJsonString());
            AbortCoordinationBeforeSend(request);
            throw;
        }
        journal["Phase"] = result.Receipt.State is "released" or "gone" && !result.Receipt.NeedsReview ? "Verified" : "Uncertain";
        journal["Message"] = result.Receipt.Message;
        journal["ReservationSha256"] = ReservationRegistry.Stamp(receipt.Id);
        journal["Utc"] = DateTimeOffset.UtcNow.ToString("o");
        WriteAtomic(path, journal.ToJsonString());
        ReleaseCoordinationAfterCompletion(path, request.ReceiptId);
        if (journal["Phase"]!.GetValue<string>() == "Verified") ReleaseReservationParentCoordination(authorization.Parents);
        return result;
    });

    private static object? ReservationPayload(MutationRequest request) => request.Reservation is { } r ? new
    { r.ReservationId, r.MachineId, r.Name, r.Domain, r.Dc, r.TargetOu, r.TargetOuGuid, r.ComputerGuid, r.Marker } : null;

    /// <summary>Included in the fixed join worker. No GUID, marker or path is accepted from the browser.</summary>
    private const string ReservationJoinGuardScript = """
function Assert-PestoReservedJoin($r,$expectedName,$expectedOu,$expectedDomain,$expectedServer,$adp){
  if($null -eq $r){throw 'Autorisation de réservation absente.'}
  $id=[Guid]::Empty
  if(-not [Guid]::TryParse([string]$r.ComputerGuid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID réservé invalide.'}
  if([string]$r.Name -ine $expectedName -or [string]$r.TargetOu -ine $expectedOu -or [string]$r.Domain -ine $expectedDomain -or [string]$r.Dc -ine $expectedServer){throw 'Portée de réservation différente du plan.'}
  $machine=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
  if($machine -ine [string]$r.MachineId){throw 'Réservation d''une autre machine.'}
  $root=Get-ADRootDSE -ErrorAction Stop @adp
  if([string]$root.dnsHostName -ine $expectedServer){throw 'DC différent du reçu de réservation.'}
  $domainCheck=Get-ADDomain -ErrorAction Stop @adp
  if([string]$domainCheck.DNSRoot -ine $expectedDomain){throw 'Domaine différent du reçu de réservation.'}
  $owned=@(Get-ADComputer -Identity $id -Properties ObjectGUID,Name,DistinguishedName,Description,DNSHostName,ServicePrincipalName,userAccountControl -ErrorAction Stop @adp)
  if($owned.Count -ne 1 -or ([Guid]$owned[0].ObjectGUID) -ne $id -or [string]$owned[0].Name -ine $expectedName -or
     [string]$owned[0].DistinguishedName -ine ('CN='+$expectedName+','+$expectedOu) -or [string]$owned[0].Description -cne [string]$r.Marker -or
     [string]$owned[0].DNSHostName -or @($owned[0].ServicePrincipalName).Count -ne 0 -or $null -eq $owned[0].userAccountControl -or
     (([long]$owned[0].userAccountControl -band 8192) -ne 0)){throw 'Le compte réservé n''est plus l''objet exact, inutilisé et autorisé.'}
}
function Assert-PestoReservedJoinResult($r,$adp){
  $id=[Guid]$r.ComputerGuid
  $owned=@(Get-ADComputer -Identity $id -Properties ObjectGUID,Name,DistinguishedName -ErrorAction Stop @adp)
  $byName=@(Get-ADComputer -Identity ([string]$r.Name+'$') -Properties ObjectGUID -ErrorAction Stop @adp)
  if($owned.Count -ne 1 -or $byName.Count -ne 1 -or ([Guid]$owned[0].ObjectGUID) -ne $id -or ([Guid]$byName[0].ObjectGUID) -ne $id -or
     [string]$owned[0].Name -ine [string]$r.Name -or [string]$owned[0].DistinguishedName -ine ('CN='+[string]$r.Name+','+[string]$r.TargetOu)){
    throw 'L''identité exacte du compte réservé n''est pas confirmée après la jonction.'
  }
}
""";
}
