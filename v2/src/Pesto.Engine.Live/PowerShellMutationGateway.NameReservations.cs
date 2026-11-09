using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Production Windows/SMB editor. Only ERROR_FILE_EXISTS/ALREADY_EXISTS proves a create collision.
/// Every other failed response stays uncertain, including a flush or close after bytes may have reached the server.</summary>
public sealed class WindowsNameReservationFiles : ISharedNameReservationFiles
{
    public SharedNameReservationCreation CreateNew(string path, byte[] bytes)
    {
        RequireWindows(); SharedCoordinationProtocol.RequireNoLinks(path);
        using var handle = CreateFileW(path, 0x40000000, 0, 0, 1, 0x80200080, 0); // write, CREATE_NEW, reparse point + write-through
        if (handle.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            if (error is 80 or 183) return SharedNameReservationCreation.AlreadyExists;
            throw new PestoException("names.reservation_unavailable", "Création exclusive du bail non confirmée par Windows ; aucun nom acquis.");
        }
        RequirePlainFile(handle);
        using var stream = new FileStream(handle, FileAccess.Write);
        stream.Write(bytes); stream.Flush(true);
        return SharedNameReservationCreation.Created;
    }

    public void RewriteExisting(string path, byte[] replacement, Func<byte[], bool> mayReplace)
    {
        RequireWindows(); SharedCoordinationProtocol.RequireNoLinks(path);
        using var handle = CreateFileW(path, 0xc0000000, 0, 0, 3, 0x80200080, 0); // read/write, OPEN_EXISTING, share none
        if (handle.IsInvalid) throw new PestoException("names.reservation_held", "Le bail ne peut pas être ouvert exclusivement ; le nom reste indisponible.");
        RequirePlainFile(handle);
        using var stream = new FileStream(handle, FileAccess.ReadWrite);
        if (stream.Length is < 1 or > SharedNameReservationProtocol.MaximumLeaseBytes)
            throw new PestoException("names.reservation_held", "Le bail est illisible ; aucune expiration supposée ni réécriture.");
        var current = new byte[(int)stream.Length]; stream.ReadExactly(current);
        if (stream.ReadByte() != -1 || !mayReplace(current))
            throw new PestoException("names.reservation_held", "Un autre propriétaire, une preuve modifiée ou un bail incertain retient ce nom.");
        stream.Position = 0;
        stream.Write(replacement); stream.SetLength(replacement.Length); stream.Flush(true);
        stream.Position = 0;
        var observed = new byte[replacement.Length]; stream.ReadExactly(observed);
        if (stream.ReadByte() != -1 || !observed.AsSpan().SequenceEqual(replacement))
            throw new PestoException("names.reservation_changed", "Le renouvellement du bail n’a pas été relu exactement ; aucun nom acquis.");
    }

    private static void RequireWindows()
    {
        if (!OperatingSystem.IsWindows()) throw new PestoException("coordination.platform", "Le transport natif des baux de noms exige Windows.");
    }
    private static void RequirePlainFile(SafeFileHandle handle)
    {
        if (!GetFileInformationByHandle(handle, out var information)
            || (information.Attributes & ((uint)FileAttributes.ReparsePoint | (uint)FileAttributes.Directory)) != 0 || information.Links != 1)
            throw new PestoException("names.reservation_invalid", "Le bail n’est pas un fichier simple identifié ; aucune réécriture.");
    }
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
}

public sealed partial class PowerShellMutationGateway : IMutationNameReservations
{
    private readonly object nameReservationGate = new();
    private SharedNameReservationService? sharedNames;

    private SharedNameReservationService SharedNames
    {
        get
        {
            lock (nameReservationGate)
            {
                if (sharedNames is not null) return sharedNames;
                if (!OperatingSystem.IsWindows() || v1InstallationPath is null)
                    throw new PestoException("names.reservation_unavailable", "L’adaptateur natif des baux de noms n’est pas disponible.");
                return sharedNames = new(Path.Combine(v1InstallationPath, "cfg.json"), Path.Combine(ReceiptGpRoot(), "V2", "name-reservation-intents"),
                    SharedCoordinationAccessMode.Live, new WindowsNameReservationFiles(), coordinationDeletion, CoordinationAccess,
                    protectJournal: folder =>
                    {
                        if (!OperatingSystem.IsWindows()) throw new PestoException("coordination.platform", "La protection du journal natif exige Windows.");
                        RequireNoReparsePoint(folder); RestrictToSystemAndAdmins(folder);
                    });
            }
        }
    }

    public IReadOnlyList<string> OtherReservedNames(string domain) => SharedNames.OtherReservedNames(domain);
    public SharedNameReservationProof? ReservePreviewName(string domain, string name, string previewId, string configurationSha256)
    {
        MutationSessionGuard.RequireWritableSession();
        return SharedNames.ReservePreviewName(domain, name, previewId, configurationSha256);
    }
    public void VerifyPreviewName(SharedNameReservationProof proof, string configurationSha256) => SharedNames.VerifyPreviewName(proof, configurationSha256);
    public void ReleasePreviewName(SharedNameReservationProof proof)
    {
        MutationSessionGuard.RequireWritableSession();
        SharedNames.ReleasePreviewName(proof);
    }

    /// <summary>Run before the first native command and after fallback confirmation. Never retarget the confirmed name.</summary>
    private void VerifyNameReservationBeforeSend(MutationRequest request)
    {
        if (request.Kind is not ("join" or "rename" or "renameMove")) return;
        var configuration = ReadCoordinationConfiguration();
        if (!string.Equals(configuration.ConfigSha256, request.ConfigurationSha256, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("names.reservation_changed", "Configuration remplacée depuis le nom confirmé ; aucun envoi.");
        if (request.PrecreatedJoin is not null)
        {
            PrecreatedJoinRules.RequireRequest(request);
            return; // Exact existing GUID, never a lease asserting the name was free.
        }
        // A separately authorized AD reservation is already bound to its GUID and immutable name. Its resume/remove
        // flow still requires all shared mutation locks, but never creates an unrelated preview lease implicitly.
        if (request.Reservation is not null) return;
        if (configuration.Root.Length == 0)
        {
            if (request.NameReservation is not null) throw new PestoException("names.reservation_changed", "Le registre du bail affiché a été désactivé ; nouveau plan nécessaire.");
            return;
        }
        var proof = request.NameReservation ?? throw new PestoException("names.reservation_required", "Le nom confirmé ne porte aucun bail partagé de cette session ; un nouvel aperçu est requis.");
        if (!string.Equals(proof.Domain, request.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(proof.Name, request.NewName, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("names.reservation_changed", "Le bail ne correspond pas au nom confirmé ; aucun nom de remplacement choisi.");
        VerifyPreviewName(proof, request.ConfigurationSha256!);
    }

    private void FinalizeNameReservation(MutationRequest request)
    {
        if (request.NameReservation is not { } proof) return;
        try
        {
            using var document = JsonDocument.Parse(ReadReceiptBytes(ReceiptPath(request.ReceiptId)));
            if (SharedCoordinationProtocol.IsCompletedReceipt(document.RootElement)) ReleasePreviewName(proof);
        }
        catch (Exception error) { CoordinationCleanupFailed(request.ReceiptId, error); }
    }
}
