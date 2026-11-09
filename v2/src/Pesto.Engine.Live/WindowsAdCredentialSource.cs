using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security;
using System.Text;
using System.Text.Json.Serialization;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Only the native host owns this source. The bridge never accepts or returns credentials.</summary>
public interface IWindowsCredentialSource : ITaskFallbackCredentialSource
{
    ProtectedWindowsCredential? CreateProtectedPayload();
    PestoAdCredential? AcquireForDiagnostic();
}

/// <summary>DPAPI CurrentUser envelope, UTF-16LE password, no optional entropy. Never persisted or logged.</summary>
public sealed record ProtectedWindowsCredential(
    [property: JsonPropertyName("userName")] string UserName,
    [property: JsonPropertyName("blob")] string Blob)
{
    public override string ToString() => "Compte AD protégé pour la session Windows";
}

/// <summary>
/// Explicit Windows credential UI. No browser, CLI argument, environment variable, settings file or credential
/// vault receives the password. Native plaintext buffers are zeroed immediately after DPAPI encryption; only the
/// encrypted envelope remains for this application session. Child PowerShell processes decrypt it in memory under
/// the same Windows user. The task fallback still needs a separate native confirmation naming the target/action.
/// </summary>
public sealed class WindowsAdCredentialSource : IWindowsCredentialSource, IDisposable
{
    private readonly object gate = new();
    private byte[]? protectedPassword;
    private Func<nint>? owner;
    private readonly bool interactiveFallback;
    public TaskFallbackAccountMode Mode => TaskFallbackAccountMode.ExplicitAccount;
    public string DisplayUserName { get; }

    private WindowsAdCredentialSource(string userName, byte[] encrypted, bool interactiveFallback = true)
    {
        DisplayUserName = userName;
        protectedPassword = encrypted;
        this.interactiveFallback = interactiveFallback;
    }

    /// <summary>Bounded DPAPI CurrentUser input from a redirected host pipe; no prompt and no automatic fallback consent.</summary>
    public static WindowsAdCredentialSource FromProtectedPayload(ProtectedWindowsCredential payload, bool interactiveFallback = false)
    {
        if (!OperatingSystem.IsWindows() || payload is null || payload.UserName is null || payload.Blob is null || payload.UserName.Length is < 3 or > 512
            || payload.UserName != payload.UserName.Trim() || payload.UserName.Any(char.IsControl)
            || (!payload.UserName.Contains('\\') && !payload.UserName.Contains('@')) || payload.Blob.Length is < 1 or > 24576)
            throw CredentialError();
        byte[] encrypted;
        try { encrypted = Convert.FromBase64String(payload.Blob); }
        catch (FormatException) { throw CredentialError(); }
        if (encrypted.Length is < 32 or > 16384) { CryptographicOperations.ZeroMemory(encrypted); throw CredentialError(); }
        var inputSize = encrypted.Length;
        var inputData = Marshal.AllocHGlobal(inputSize);
        try
        {
            Marshal.Copy(encrypted, 0, inputData, encrypted.Length);
            var input = new DataBlob { Size = encrypted.Length, Data = inputData };
            if (!CryptUnprotectData(ref input, 0, 0, 0, 0, 1, out var output)) throw CredentialError();
            try
            {
                if (output.Size is < 2 or > 8192 || output.Size % 2 != 0) throw CredentialError();
                var plain = new byte[output.Size];
                try
                {
                    Marshal.Copy(output.Data, plain, 0, plain.Length);
                    _ = new UnicodeEncoding(false, false, true).GetCharCount(plain);
                    for (var n = 0; n < plain.Length; n += 2) if (plain[n] == 0 && plain[n + 1] == 0) throw CredentialError();
                }
                catch (DecoderFallbackException) { throw CredentialError(); }
                finally { CryptographicOperations.ZeroMemory(plain); }
            }
            finally { Zero(output.Data, output.Size); _ = LocalFree(output.Data); }
            var result = new WindowsAdCredentialSource(payload.UserName, encrypted, interactiveFallback);
            encrypted = []; // ownership transferred; finally still clears every temporary buffer
            return result;
        }
        finally
        {
            Zero(inputData, inputSize);
            Marshal.FreeHGlobal(inputData);
            CryptographicOperations.ZeroMemory(encrypted);
        }
    }

    /// <summary>Set after construction of the native host; no HWND is sent to the web surface.</summary>
    public void SetOwner(Func<nint> ownerHandle) => owner = ownerHandle;

    /// <summary>Native desktop input only. Protect before returning; no plaintext managed string or persistence.</summary>
    public static WindowsAdCredentialSource FromSecurePassword(string userName, SecureString password)
    {
        if (!OperatingSystem.IsWindows()) throw CredentialError();
        var name = userName.Trim();
        var parts = name.Contains('\\') ? name.Split('\\') : name.Split('@');
        if (name.Length is < 3 or > 512 || name.Any(char.IsWhiteSpace) || name.Any(char.IsControl)
            || parts.Length != 2 || parts.Any(string.IsNullOrEmpty))
            throw new PestoException("credential.invalid", "Utilisez DOMAINE\\utilisateur ou utilisateur@domaine.");
        if (password.Length is < 1 or > 4096)
            throw new PestoException("credential.empty", "Saisissez le mot de passe de ce compte.");
        var plain = Marshal.SecureStringToGlobalAllocUnicode(password);
        try
        {
            var input = new DataBlob { Size = checked(password.Length * 2), Data = plain };
            if (!CryptProtectData(ref input, null, 0, 0, 0, 1, out var output)) throw CredentialError();
            try
            {
                var encrypted = new byte[output.Size];
                Marshal.Copy(output.Data, encrypted, 0, encrypted.Length);
                return new WindowsAdCredentialSource(name, encrypted);
            }
            finally { Zero(output.Data, output.Size); _ = LocalFree(output.Data); }
        }
        finally { Marshal.ZeroFreeGlobalAllocUnicode(plain); }
    }

    /// <summary>Null means the operator cancelled. Acquisition does not authenticate or authorize any mutation.</summary>
    public static WindowsAdCredentialSource? Prompt(nint parent = default)
    {
        if (!OperatingSystem.IsWindows() || !Environment.UserInteractive)
            throw new PestoException("credential.unavailable", "La connexion par compte AD exige une session Windows interactive.");
        var info = new CredUiInfo
        {
            Size = Marshal.SizeOf<CredUiInfo>(), Parent = parent,
            Caption = "Pesto — Compte Active Directory",
            Message = "Saisissez DOMAIN\\utilisateur ou utilisateur@domaine. Ce compte sert uniquement à cette session Pesto. Aucun mot de passe n’est enregistré."
        };
        uint authPackage = 0;
        nint packed = 0;
        uint packedSize = 0;
        try
        {
            // CREDUIWIN_GENERIC, without CHECKBOX: this API never saves credentials.
            var result = CredUIPromptForWindowsCredentialsW(ref info, 0, ref authPackage, 0, 0,
                out packed, out packedSize, 0, 1);
            if (result == 1223) return null; // ERROR_CANCELLED
            if (result != 0) throw CredentialError();
            uint userCount = 0, domainCount = 0, passwordCount = 0;
            _ = CredUnPackAuthenticationBufferW(0, packed, packedSize, 0, ref userCount, 0, ref domainCount, 0, ref passwordCount);
            if (Marshal.GetLastWin32Error() != 122 || userCount is 0 or > 4096 || domainCount > 4096 || passwordCount is < 2 or > 4096)
                throw CredentialError();
            domainCount = Math.Max(domainCount, 1);
            var userBytes = checked((int)userCount * 2);
            var domainBytes = checked((int)Math.Max(domainCount, 1) * 2);
            var passwordBytes = checked((int)passwordCount * 2);
            var user = Marshal.AllocHGlobal(userBytes);
            var domain = Marshal.AllocHGlobal(domainBytes);
            var password = Marshal.AllocHGlobal(passwordBytes);
            try
            {
                Zero(user, userBytes); Zero(domain, domainBytes); Zero(password, passwordBytes);
                if (!CredUnPackAuthenticationBufferW(0, packed, packedSize, user, ref userCount, domain, ref domainCount, password, ref passwordCount))
                    throw CredentialError();
                var name = (Marshal.PtrToStringUni(user) ?? "").Trim();
                var domainName = (Marshal.PtrToStringUni(domain) ?? "").Trim();
                if (!name.Contains('\\') && !name.Contains('@') && domainName.Length > 0) name = domainName + "\\" + name;
                if (string.IsNullOrWhiteSpace(name) || name.Any(char.IsControl) || (!name.Contains('\\') && !name.Contains('@')))
                    throw new PestoException("credential.invalid", "Saisissez un compte AD sous la forme DOMAIN\\utilisateur ou utilisateur@domaine.");
                // Scan the returned UTF-16 buffer directly: no immutable managed password string is created here.
                var length = 0;
                while (length < passwordBytes / 2 && Marshal.ReadInt16(password, length * 2) != 0) length++;
                if (length == 0 || length >= passwordBytes / 2) throw CredentialError();
                var input = new DataBlob { Size = length * 2, Data = password };
                if (!CryptProtectData(ref input, null, 0, 0, 0, 1, out var output)) throw CredentialError();
                try
                {
                    var encrypted = new byte[output.Size];
                    Marshal.Copy(output.Data, encrypted, 0, encrypted.Length);
                    return new WindowsAdCredentialSource(name, encrypted);
                }
                finally { Zero(output.Data, output.Size); _ = LocalFree(output.Data); }
            }
            finally
            {
                Zero(password, passwordBytes); Marshal.FreeHGlobal(password);
                Zero(domain, domainBytes); Marshal.FreeHGlobal(domain);
                Zero(user, userBytes); Marshal.FreeHGlobal(user);
            }
        }
        finally { if (packed != 0) { Zero(packed, checked((int)packedSize)); Marshal.FreeCoTaskMem(packed); } }
    }

    public ProtectedWindowsCredential CreateProtectedPayload()
    {
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(protectedPassword is null, this);
            return new ProtectedWindowsCredential(DisplayUserName, Convert.ToBase64String(protectedPassword!));
        }
    }

    public PestoAdCredential? AcquireForFallback(string computer, string? newName, string operationId)
    {
        if (!interactiveFallback || !OperatingSystem.IsWindows() || !Environment.UserInteractive) return null;
        var answer = MessageBoxW(owner?.Invoke() ?? 0,
            "Le renommage direct a été refusé.\n\nCréer et exécuter une tâche élevée sur « " + computer
            + " » pour le renommer en « " + newName + " », sous le compte « " + DisplayUserName
            + " » ?\n\nAucun redémarrage automatique. Une réponse inconnue bloque toute nouvelle tentative.",
            "Pesto — Confirmer le repli authentifié", 0x00000004 | 0x00000030 | 0x00000100); // Yes/No, warning, default No
        if (answer != 6) return null;
        return AcquireForDiagnostic();
    }

    /// <summary>Operation-scoped credential for the confirmed operation's read-only diagnostic; never a fallback authorization.</summary>
    public PestoAdCredential? AcquireForDiagnostic()
    {
        if (!OperatingSystem.IsWindows()) return null;
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(protectedPassword is null, this);
            var encrypted = protectedPassword!;
            var inputData = Marshal.AllocHGlobal(encrypted.Length);
            try
            {
                Marshal.Copy(encrypted, 0, inputData, encrypted.Length);
                var input = new DataBlob { Size = encrypted.Length, Data = inputData };
                if (!CryptUnprotectData(ref input, 0, 0, 0, 0, 1, out var output)) throw CredentialError();
                try
                {
                    var plaintext = new byte[output.Size];
                    try
                    {
                        Marshal.Copy(output.Data, plaintext, 0, plaintext.Length);
                        // COM requires a managed string; its lifetime is restricted to this fallback operation.
                        return new PestoAdCredential(DisplayUserName, Encoding.Unicode.GetString(plaintext));
                    }
                    finally { CryptographicOperations.ZeroMemory(plaintext); }
                }
                finally { Zero(output.Data, output.Size); _ = LocalFree(output.Data); }
            }
            finally { Zero(inputData, encrypted.Length); Marshal.FreeHGlobal(inputData); }
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (protectedPassword is not null) CryptographicOperations.ZeroMemory(protectedPassword);
            protectedPassword = null;
            owner = null;
        }
    }

    private static PestoException CredentialError() => new("credential.unavailable",
        "Windows n’a pas pu fournir le compte AD. Fermez puis relancez Pesto pour réessayer ; aucune opération n’a été lancée.");

    private static void Zero(nint address, int bytes)
    {
        if (address == 0) return;
        for (var i = 0; i < bytes; i++) Marshal.WriteByte(address, i, 0);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CredUiInfo
    {
        public int Size;
        public nint Parent;
        [MarshalAs(UnmanagedType.LPWStr)] public string Message;
        [MarshalAs(UnmanagedType.LPWStr)] public string Caption;
        public nint Banner;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob { public int Size; public nint Data; }

    [DllImport("credui.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern uint CredUIPromptForWindowsCredentialsW(ref CredUiInfo info, uint authError, ref uint authPackage,
        nint input, uint inputSize, out nint output, out uint outputSize, nint save, uint flags);
    [DllImport("credui.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredUnPackAuthenticationBufferW(uint flags, nint input, uint inputSize,
        nint user, ref uint userSize, nint domain, ref uint domainSize, nint password, ref uint passwordSize);
    [DllImport("crypt32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(ref DataBlob input, string? description, nint entropy, nint reserved,
        nint prompt, uint flags, out DataBlob output);
    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(ref DataBlob input, nint description, nint entropy, nint reserved,
        nint prompt, uint flags, out DataBlob output);
    [DllImport("kernel32.dll", ExactSpelling = true)]
    private static extern nint LocalFree(nint memory);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(nint owner, string message, string caption, uint type);
}
