using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Operation-scoped outbound identity. No mapped drive, persistent connection, command line or stored secret.</summary>
public sealed class WindowsCoordinationAccess(IWindowsCredentialSource? credentials = null) : ISharedCoordinationAccess
{
    public T Run<T>(Func<T> operation)
    {
        if (!OperatingSystem.IsWindows()) throw new PestoException("coordination.platform", "Le transport natif du registre partagé exige Windows.");
        if (credentials is null) return operation();
        using var credential = credentials.AcquireForDiagnostic()
            ?? throw new PestoException("coordination.credential", "Le compte AD de cette session n’est plus disponible pour le registre partagé.");
        var user = credential.UserName;
        string? domain = null;
        var separator = user.IndexOf('\\');
        if (separator >= 0)
        {
            domain = user[..separator]; user = user[(separator + 1)..];
            if (domain.Length == 0 || user.Length == 0 || user.Contains('\\')) throw new PestoException("coordination.credential", "Identité AD du registre invalide.");
        }
        var password = Marshal.StringToHGlobalUni(credential.TakePassword());
        try
        {
            // LOGON32_LOGON_NEW_CREDENTIALS / WINNT50 clones local rights and supplies only outbound credentials.
            // The token and all file handles are disposed before leaving this synchronous scope.
            if (!LogonUserW(user, domain, password, 9, 3, out var token))
                throw new PestoException("coordination.credential", "Windows n’a pas pu établir le contexte du compte AD pour le registre partagé.");
            using (token) return WindowsIdentity.RunImpersonated(token, operation);
        }
        finally { Marshal.ZeroFreeGlobalAllocUnicode(password); }
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LogonUserW(string userName, string? domain, nint password, int logonType, int provider, out SafeAccessTokenHandle token);
}

/// <summary>Compare and delete on the same exclusive Windows/SMB file handle. A replacement pathname cannot be deleted.</summary>
public sealed class WindowsCoordinationDeletion : ISharedCoordinationDeletion
{
    public CoordinationDeletionResult DeleteExact(string path, string expectedSha256, int maximumBytes)
    {
        if (!OperatingSystem.IsWindows()) throw new PestoException("coordination.platform", "La suppression vérifiée des verrous exige Windows.");
        SharedCoordinationProtocol.RequireNoLinks(path);
        // GENERIC_READ | DELETE, share none, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT.
        using var handle = CreateFileW(path, 0x80010000, 0, 0, 3, 0x00200080, 0);
        if (handle.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            if (error is 2 or 3) return CoordinationDeletionResult.Missing;
            throw new PestoException("coordination.delete", "Le verrou partagé ne peut pas être ouvert exclusivement ; il reste conservé.");
        }
        if (!GetFileInformationByHandle(handle, out var information)
            || (information.Attributes & ((uint)FileAttributes.ReparsePoint | (uint)FileAttributes.Directory)) != 0
            || information.Links != 1)
            throw new PestoException("coordination.delete", "L’identité du fichier de verrou n’est pas confirmée ; aucune suppression.");
        using var stream = new FileStream(handle, FileAccess.Read);
        if (stream.Length is < 1 || stream.Length > maximumBytes) return CoordinationDeletionResult.Changed;
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1 || SharedCoordinationProtocol.Hash(bytes) != expectedSha256) return CoordinationDeletionResult.Changed;
        var disposition = new FileDisposition { DeleteFile = 1 };
        if (!SetFileInformationByHandle(handle, 4, ref disposition, 1))
            throw new PestoException("coordination.delete", "La suppression du verrou n’a pas été acceptée par Windows ; aucun succès de nettoyage annoncé.");
        // Closing this exact handle completes its deletion; do not re-open/delete a potentially replaced path.
        return CoordinationDeletionResult.Deleted;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileDisposition { public byte DeleteFile; }
    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        public uint Attributes, CreationLow, CreationHigh, AccessLow, AccessHigh, WriteLow, WriteHigh,
            VolumeSerial, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string path, uint access, uint share, nint security, uint creation, uint flags, nint template);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int informationClass, ref FileDisposition information, uint size);
}

public sealed partial class PowerShellMutationGateway : ISharedCoordinationDisclosure
{
    private sealed record CoordinationOperation(SharedCoordinationIntent Intent, string? ReceiptPath = null, bool Attempted = false);
    private readonly object coordinationGate = new();
    private readonly Dictionary<string, CoordinationOperation> coordinationOperations = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> coordinationCleanupFailures = new(StringComparer.Ordinal);
    private SharedCoordinationCleanupStatus coordinationCleanup = new("notAttempted");
    public SharedCoordinationCleanupStatus CoordinationCleanupStatus { get { lock (coordinationGate) return coordinationCleanup; } }
    private static readonly WindowsCoordinationDeletion coordinationDeletion = new();
    private ISharedCoordinationAccess CoordinationAccess => new WindowsCoordinationAccess(fallbackCredentials as IWindowsCredentialSource);

    /// <summary>Hook in ReceiptJson. Pure with respect to the share: the durable receipt carries intent before IO.</summary>
    private JsonNode? CoordinationReceipt(MutationRequest request)
    {
        lock (coordinationGate)
        {
            if (coordinationOperations.TryGetValue(request.ReceiptId, out var previous)) return previous.Intent.ToJson();
            var configuration = ReadCoordinationConfiguration();
            if (!string.Equals(configuration.ConfigSha256, request.ConfigurationSha256, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("coordination.config_changed", "La configuration a changé depuis le plan confirmé ; aucune intention partagée créée.");
            SharedCoordinationIntent? parent = null;
            if (request.Continuation is { } continuation)
            {
                var bytes = ReadReceiptBytes(ReceiptPath(continuation.ParentReceiptId));
                if (Hash(bytes) != continuation.ParentReceiptSha256) throw new PestoException("coordination.parent", "Le reçu parent a changé avant l’intention de coordination.");
                using var document = JsonDocument.Parse(bytes);
                parent = ReadCoordinationIntent(document.RootElement, continuation.ParentReceiptId);
            }
            else if (request.Reservation is { } reservation)
            {
                ValidateReservationRequest(request, reservation);
                var savedReservation = ReservationRegistry.Read(reservation.ReservationId);
                // The native grant binds these append-only parents and their current exact bytes. A refused child
                // may have cleaned its own new keys, so only an unresolved parent can supply inherited ownership.
                foreach (var proof in reservation.Parents)
                {
                    var bytes = ReadReceiptBytes(ReceiptPath(proof.ReceiptId));
                    if (!string.Equals(Hash(bytes), proof.Sha256, StringComparison.OrdinalIgnoreCase))
                        throw new PestoException("coordination.parent", "Un reçu de réservation a changé avant l’intention partagée.");
                    using var document = JsonDocument.Parse(bytes);
                    RequireReservationParentIdentity(document.RootElement, savedReservation, proof.ReceiptId);
                    var candidate = ReadCoordinationIntent(document.RootElement, proof.ReceiptId);
                    if (candidate is not null && !SharedCoordinationProtocol.IsCompletedReceipt(document.RootElement)) parent = candidate;
                }
            }
            var identity = new SharedCoordinationIdentity(request.Domain, request.Computer, request.NewName, request.ComputerGuid);
            var intent = SharedCoordinationProtocol.CreateIntent(configuration, identity, request.ReceiptId, DateTimeOffset.UtcNow, parent,
                request.Reservation?.Parents);
            if (intent is null) return null;
            coordinationOperations[request.ReceiptId] = new(intent);
            return intent.ToJson();
        }
    }

    /// <summary>Hook after WritePreSendReceipt and parent/child linking, before any native mutation or fallback.</summary>
    private void AcquireCoordination(MutationRequest request, string receiptPath)
    {
        lock (coordinationGate)
        {
            if (!coordinationOperations.TryGetValue(request.ReceiptId, out var operation)) return;
            RequireCoordinationConfiguration(operation.Intent);
            WithCoordinationReceipt(receiptPath, request.ReceiptId, saved =>
            {
                var durable = ReadCoordinationIntent(saved, request.ReceiptId)
                    ?? throw new PestoException("coordination.intent", "L’intention du registre n’a pas été enregistrée avant l’envoi.");
                if (!SameIntent(operation.Intent, durable)) throw new PestoException("coordination.intent", "L’intention durable de coordination a changé.");
                coordinationOperations[request.ReceiptId] = operation with { ReceiptPath = receiptPath, Attempted = true };
                return CoordinationAccess.Run(() =>
                {
                    SharedCoordinationProtocol.Acquire(durable, SharedCoordinationAccessMode.Live, coordinationDeletion);
                    return true;
                });
            });
        }
    }

    /// <summary>Recheck after baseline/fallback confirmations as well as immediately before the first command.</summary>
    private void VerifyCoordinationBeforeSend(MutationRequest request)
    {
        lock (coordinationGate)
        {
            if (!coordinationOperations.TryGetValue(request.ReceiptId, out var operation)) return;
            if (!operation.Attempted || operation.ReceiptPath is null) throw new PestoException("coordination.intent", "Coordination non acquise avant envoi.");
            RequireCoordinationConfiguration(operation.Intent);
            WithCoordinationReceipt(operation.ReceiptPath, request.ReceiptId, saved =>
            {
                var durable = ReadCoordinationIntent(saved, request.ReceiptId);
                if (durable is null || !SameIntent(operation.Intent, durable)) throw new PestoException("coordination.intent", "L’intention durable de coordination a changé.");
                return CoordinationAccess.Run(() => { SharedCoordinationProtocol.Verify(durable, SharedCoordinationAccessMode.Live); return true; });
            });
        }
    }

    /// <summary>Only a proven failure before any native command may call this; borrowed parent locks stay in place.</summary>
    private void AbortCoordinationBeforeSend(MutationRequest request)
    {
        lock (coordinationGate)
        {
            if (!coordinationOperations.TryGetValue(request.ReceiptId, out var operation) || !operation.Attempted) return;
            CoordinationAccess.Run(() => { SharedCoordinationProtocol.ReleaseOwned(operation.Intent, SharedCoordinationAccessMode.Live, coordinationDeletion); return true; });
        }
    }

    /// <summary>Hook after the engine's final decision was durably persisted. Pending/uncertain keeps all locks.</summary>
    private void FinalizeCoordination(MutationRequest request, MutationOutcome outcome)
    {
        try { ReleaseCompletedCoordination(request.ReceiptId); FinalizeNameReservation(request); }
        finally { lock (coordinationGate) coordinationOperations.Remove(request.ReceiptId); }
    }

    /// <summary>Hook after explicit reconciliation or durable continuation completion. Never alter receipt bytes here.</summary>
    private void ReleaseCompletedCoordination(string receiptId)
    {
        try
        {
            var path = ReceiptPath(receiptId);
            if (!File.Exists(path)) return;
            ReleaseCoordinationAfterCompletion(path, receiptId);
            using var document = JsonDocument.Parse(ReadReceiptBytes(path));
            if (SavedText(document.RootElement, "ParentReceiptId") is { } parentId && SavedText(document.RootElement, "Phase") == "Verified")
                ReleaseCoordinationAfterCompletion(ReceiptPath(parentId), parentId, allowResolvedParent: true);
            if (SavedText(document.RootElement, "Phase") == "Verified"
                && ReadCoordinationIntent(document.RootElement, receiptId) is { } intent)
                foreach (var parent in intent.ReservationParents)
                    ReleaseCoordinationAfterCompletion(ReceiptPath(parent.ReceiptId), parent.ReceiptId, verifiedReservationChildPath: path);
        }
        catch (Exception error) { CoordinationCleanupFailed(receiptId, error); }
    }

    /// <summary>Also usable by the explicit reservation-removal journal after its own Verified/Failed durable proof.</summary>
    private void ReleaseCoordinationAfterCompletion(string receiptPath, string receiptId, bool allowResolvedParent = false,
        string? verifiedReservationChildPath = null)
    {
        try
        {
            WithCoordinationReceipt(receiptPath, receiptId, saved =>
            {
                var intent = ReadCoordinationIntent(saved, receiptId);
                if (intent is null) return true;
                if (!SharedCoordinationProtocol.IsCompletedReceipt(saved)
                    && !(allowResolvedParent && (HasResolvedContinuation(saved) || HasResolvedReservationParent(saved, receiptPath)))
                    && !(verifiedReservationChildPath is not null && HasVerifiedReservationCoordinationChild(saved, receiptPath, verifiedReservationChildPath)))
                {
                    lock (coordinationGate)
                        if (coordinationCleanup.State != "failed") coordinationCleanup = coordinationCleanup with { State = "retained", ReceiptId = receiptId };
                    return false;
                }
                CoordinationAccess.Run(() =>
                {
                    SharedCoordinationProtocol.ReleaseOwned(intent, SharedCoordinationAccessMode.Live, coordinationDeletion);
                    return true;
                });
                lock (coordinationGate)
                {
                    coordinationCleanupFailures.Remove(receiptId);
                    var remaining = coordinationCleanupFailures.FirstOrDefault();
                    coordinationCleanup = coordinationCleanup with
                    {
                        State = coordinationCleanupFailures.Count == 0 ? "confirmed" : "failed",
                        ReceiptId = coordinationCleanupFailures.Count == 0 ? receiptId : remaining.Key,
                        FailureCode = coordinationCleanupFailures.Count == 0 ? null : remaining.Value
                    };
                }
                return true;
            });
        }
        catch (Exception error) { CoordinationCleanupFailed(receiptId, error); }
        finally { lock (coordinationGate) coordinationOperations.Remove(receiptId); }
    }

    /// <summary>Called only after the removal's durable result. Each parent is checked against its exact resolution
    /// in the separate account-reservation receipt; their original uncertain phases and hashes stay untouched.</summary>
    private void ReleaseReservationParentCoordination(IReadOnlyList<JoinReservationParent> parents)
    {
        foreach (var parent in parents)
        {
            try
            {
                var path = ReceiptPath(parent.ReceiptId);
                if (!string.Equals(Hash(ReadReceiptBytes(path)), parent.Sha256, StringComparison.OrdinalIgnoreCase))
                    throw new PestoException("coordination.changed", "Un reçu parent a changé après la preuve de retrait ; ses verrous sont conservés.");
                ReleaseCoordinationAfterCompletion(path, parent.ReceiptId, allowResolvedParent: true);
            }
            catch (Exception error) { CoordinationCleanupFailed(parent.ReceiptId, error); }
        }
    }

    private bool HasVerifiedReservationCoordinationChild(JsonElement parent, string parentPath, string childPath)
    {
        try
        {
            var parentId = SavedText(parent, "ReceiptId");
            var reservationId = SavedText(parent, "ReservationId");
            if (parentId is null || !JoinReservationStore.IsId(reservationId)
                || Path.GetFileName(parentPath) != parentId + ".json") return false;
            var childId = Path.GetFileNameWithoutExtension(childPath);
            return WithCoordinationReceipt(childPath, childId, child =>
            {
                if (SavedText(child, "Phase") != "Verified" || !Matches(child, "Kind", "join")
                    || SavedText(child, "ReservationId") != reservationId
                    || !Matches(child, "Domain", SavedText(parent, "Domain")) || !Matches(child, "NewName", SavedText(parent, "NewName"))
                    || !Guid.TryParse(SavedText(parent, "ComputerGuid"), out var parentGuid)
                    || !Guid.TryParse(SavedText(child, "ComputerGuid"), out var childGuid) || childGuid != parentGuid) return false;
                var intent = ReadCoordinationIntent(child, childId);
                var digest = SharedCoordinationProtocol.Hash(ReadReceiptBytes(parentPath));
                return intent is not null && intent.ReservationParents.Any(p => p.ReceiptId == parentId && p.Sha256 == digest);
            });
        }
        catch (Exception) { return false; }
    }

    private void CoordinationCleanupFailed(string receiptId, Exception error)
    {
        var code = error is PestoException pesto && pesto.Code is "coordination.changed" or "coordination.delete" or "coordination.unprepared" or "coordination.credential"
            ? pesto.Code : "coordination.cleanup";
        lock (coordinationGate)
        {
            coordinationCleanupFailures[receiptId] = code;
            coordinationCleanup = new("failed", receiptId, code, (int)Math.Min(int.MaxValue, (long)coordinationCleanup.Failures + 1));
        }
        // Never rewrite a durable business result or its parent/child hashes merely to report SMB cleanup failure.
    }

    /// <summary>After an immutable acknowledgement event is flushed, under GP. Never changes a receipt or a parent link.</summary>
    private void ReleaseCoordinationAfterAcknowledgement(string receiptPath, string receiptId, ReceiptAcknowledgementEvidence acknowledgement)
    {
        try
        {
            if (acknowledgement.ReceiptId != receiptId || !ReceiptAcknowledgementStore.ValidateApplied(ReceiptGpRoot(), acknowledgement))
                throw new PestoException("coordination.ack", "L’acquittement durable ne couvre plus le reçu.");
            var entra = ReadEntraBarrier(receiptId);
            if (!entra.CanAcknowledge || entra.EvidenceSha256 != acknowledgement.Event.EntraEvidenceSha256)
                throw new PestoException("coordination.ack", "La preuve de fin Entra a changé ; verrous conservés.");
            RequireNoReparsePoint(receiptPath);
            using var pin = new FileStream(receiptPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (pin.Length is < 1 or > 1048576) throw new IOException("Reçu d’acquittement invalide.");
            var bytes = new byte[checked((int)pin.Length)]; pin.ReadExactly(bytes);
            var hash = SharedCoordinationProtocol.Hash(bytes);
            if (!acknowledgement.Event.Targets.Any(target => target.ReceiptSha256.Equals(hash, StringComparison.OrdinalIgnoreCase)
                && Path.GetFullPath(ReceiptAcknowledgementSource.ReceiptPath(ReceiptGpRoot(), target.Store, target.ReceiptId))
                    .Equals(Path.GetFullPath(receiptPath), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)))
                throw new PestoException("coordination.ack", "L’événement ne couvre pas les octets de ce reçu.");
            using var document = JsonDocument.Parse(bytes); var saved = document.RootElement;
            if (!saved.TryGetProperty("Coordination", out var coordination) || coordination.ValueKind == JsonValueKind.Null) return;
            CoordinationAccess.Run(() =>
            {
                if (saved.TryGetProperty("ReceiptId", out _))
                {
                    var intent = ReadCoordinationIntent(saved, receiptId);
                    if (intent is not null) SharedCoordinationProtocol.ReleaseOwned(intent, SharedCoordinationAccessMode.Live, coordinationDeletion);
                }
                else ReleaseLegacyAcknowledgedLocks(saved, coordination, receiptId);
                return true;
            });
            lock (coordinationGate)
            {
                coordinationCleanupFailures.Remove(receiptId);
                coordinationCleanup = coordinationCleanup with { State = "confirmed", ReceiptId = receiptId, FailureCode = null };
            }
        }
        catch (Exception error) { CoordinationCleanupFailed(receiptId, error); }
    }

    private void ReleaseLegacyAcknowledgedLocks(JsonElement saved, JsonElement coordination, string receiptId)
    {
        if (coordination.ValueKind != JsonValueKind.Object || !coordination.TryGetProperty("Enabled", out var enabled) || enabled.ValueKind != JsonValueKind.True) return;
        if (!Guid.TryParse(SavedText(saved, "OperationId"), out var operation) || operation == Guid.Empty
            || !Guid.TryParse(receiptId, out var expectedOperation) || expectedOperation != operation
            || !saved.TryGetProperty("Plan", out var plan) || plan.ValueKind != JsonValueKind.Object)
            throw new PestoException("coordination.ack", "Identité du reçu V1 non confirmée.");
        var configuration = ReadCoordinationConfiguration();
        var identity = new SharedCoordinationIdentity(SavedText(plan, "Domain") ?? "", SavedText(plan, "Nom_du_PC") ?? "",
            SavedText(plan, "Nouveau_Nom"), SavedText(plan, "Objet_GUID"));
        if (configuration.Root.Length == 0 || !configuration.Domain.Equals(identity.Domain, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("coordination.config", "Le registre V1 doit rester configuré dans son domaine.");
        var registry = SharedCoordinationProtocol.InspectRegistry(configuration.Root, identity.Domain);
        if (!registry.RootExists || !registry.MarkerPresent || !registry.LocksPresent)
            throw new PestoException("coordination.unprepared", "Registre V1 non confirmé ; aucun nettoyage.");
        var expectedKeys = SharedCoordinationProtocol.Keys(identity);
        if (!coordination.TryGetProperty("Keys", out var keys) || keys.ValueKind != JsonValueKind.Array || keys.GetArrayLength() is < 1 or > 3)
            throw new PestoException("coordination.ack", "Clés du reçu V1 invalides.");
        var unique = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in keys.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || item.GetString() is not { } key || !expectedKeys.Contains(key) || !unique.Add(key))
                throw new PestoException("coordination.ack", "Clé V1 étrangère à l’identité confirmée.");
            var path = Path.Combine(configuration.Root, "locks", key + ".json"); RequireNoReparsePoint(path);
            if (!File.Exists(path)) continue;
            var bytes = SharedCoordinationProtocol.ReadBounded(path, SharedCoordinationProtocol.MaximumLeaseBytes);
            using var lease = JsonDocument.Parse(bytes); var value = lease.RootElement;
            if (!Guid.TryParse(SavedText(value, "OperationId"), out var owner)) throw new PestoException("coordination.changed", "Propriétaire du verrou V1 invalide.");
            if (owner != operation) continue; // A borrowed parent's lock is never released by this acknowledgement.
            if (SavedText(value, "Key") != key || !string.Equals(SavedText(value, "Domain"), identity.Domain, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("coordination.changed", "Verrou V1 différent : aucune suppression.");
            if (coordinationDeletion.DeleteExact(path, SharedCoordinationProtocol.Hash(bytes), SharedCoordinationProtocol.MaximumLeaseBytes) == CoordinationDeletionResult.Changed)
                throw new PestoException("coordination.changed", "Verrou V1 changé depuis la lecture ; conservé.");
        }
    }

    private SharedCoordinationConfiguration ReadCoordinationConfiguration()
    {
        if (v1InstallationPath is null) throw new PestoException("coordination.config", "Configuration du registre absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json");
        RequireNoReparsePoint(path);
        var bytes = SharedCoordinationProtocol.ReadBounded(path, ConfigurationDocument.MaximumBytes);
        return SharedCoordinationConfiguration.ReadBytes(bytes);
    }

    private void RequireCoordinationConfiguration(SharedCoordinationIntent intent)
    {
        if (ReadCoordinationConfiguration().ConfigSha256 != intent.ConfigSha256)
            throw new PestoException("coordination.config_changed", "La configuration a changé après l’intention durable ; aucune commande native lancée.");
    }

    private static SharedCoordinationIntent? ReadCoordinationIntent(JsonElement receipt, string receiptId)
    {
        if (!receipt.TryGetProperty("Coordination", out var value) || value.ValueKind == JsonValueKind.Null) return null;
        var intent = SharedCoordinationProtocol.ReadIntent(value);
        if (intent.ReceiptId != receiptId || !Matches(receipt, "ReceiptId", receiptId)
            || !Matches(receipt, "Domain", intent.Domain) || !Matches(receipt, "Computer", intent.Identity.Computer)
            || !Matches(receipt, "NewName", intent.Identity.NewName)
            || intent.Identity.ComputerGuid is { } expected && (!Guid.TryParse(SavedText(receipt, "ComputerGuid"), out var actual) || actual != Guid.Parse(expected)))
            throw new PestoException("coordination.intent", "Le registre durable est lié à une autre identité de reçu ou de machine.");
        return intent;
    }

    private static bool SameIntent(SharedCoordinationIntent first, SharedCoordinationIntent second) =>
        first.ToJson().ToJsonString() == second.ToJson().ToJsonString();

    private static T WithCoordinationReceipt<T>(string path, string receiptId, Func<JsonElement, T> action)
    {
        RequireNoReparsePoint(path);
        // Keep the local receipt open against writes/replacement throughout the remote check/cleanup.
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length is < 1 or > 65536) throw new PestoException("coordination.receipt", "Reçu de coordination illisible.");
        var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
        using var document = JsonDocument.Parse(bytes);
        if (!Matches(document.RootElement, "ReceiptId", receiptId)) throw new PestoException("coordination.receipt", "Identité de reçu de coordination invalide.");
        return action(document.RootElement);
    }
}
