using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;

namespace Pesto.App;

/// <summary>Headless entry before WinForms, UAC, profile initialization, credential dialogs or directory construction.</summary>
internal static class CliHost
{
    public static int Run(string[] arguments)
    {
        ConnectOutput();
        WindowsAdCredentialSource? credentials = null;
        var executionEntered = false;
        try
        {
            var (profile, remaining) = OperatorProfile.Resolve(arguments);
            string? requestedRoot = null;
            var cliArguments = new List<string>();
            for (var i = 0; i < remaining.Length; i++)
            {
                if (remaining[i] != "--v1-root") { cliArguments.Add(remaining[i]); continue; }
                if (requestedRoot is not null || ++i >= remaining.Length)
                    throw new PestoException("automation.arguments", "Le dossier de configuration CLI est répété ou absent.");
                requestedRoot = remaining[i];
            }
            var options = PestoCliOptions.Parse(cliArguments);
            // Resolve only a local configuration; never initialize, import, replace or prompt in automation.
            var configuration = requestedRoot is null ? AppPaths.UserData(AppPaths.Channel, false, false, profile.LocalData)
                : HostWiring.Parse(["--v1-root", requestedRoot]).V1Root!;
            OperatorProfile.RejectLinks(configuration);
            if (UpdateTransaction.List(AppPaths.AppDirectory).Any(t => t.Status is not ("completed" or "rolledBack" or "cancelled")))
                throw new PestoException("automation.update_pending", "Une transaction binaire doit être reprise explicitement dans Pesto avant toute automatisation.");
            var local = WindowsAutomationSupport.ReadLocalIdentity();
            var context = new AutomationHostContext(configuration, profile.Sid, local.OperatorSid, local.MachineId,
                local.ComputerName, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GP"),
                local.AlreadyElevated, options.CredentialStdin, local.DomainJoined, WindowsAutomationSupport.SecureDirectory, WindowsManagedPolicyReader.Read);
            IPestoBackend Factory()
            {
                // A durable replay returns before this factory: no credential read, directory gateway or native worker.
                if (options.CredentialStdin) credentials = ReadCredential();
                return PestoBackend.CreateLive(configuration, new PowerShellDirectoryGateway(credentials, configuration),
                    new PowerShellMutationGateway(configuration, credentials));
            }
            executionEntered = options.Execute;
            var result = PestoCliRunner.Run(options, context, Factory);
            Write(result);
            return result.ExitCode;
        }
        catch (Exception error)
        {
            // No exception details, environment, argv or input can leak protected or plaintext credentials to stdout.
            var code = executionEntered ? 97 : 96;
            var message = executionEntered
                ? "L’exécution CLI n’a pas rendu de résultat exploitable. Son effet peut être engagé ; consultez le journal idempotent et le reçu. Aucun rejeu implicite."
                : error is PestoException known ? known.Message : "La demande CLI est refusée avant toute exécution. Vérifiez les arguments publics et la configuration locale.";
            try { Write(new PestoCliResult(1, "live", executionEntered ? "Uncertain" : "Refused", code, null, false, executionEntered, null, DateTimeOffset.UtcNow, message)); }
            catch (IOException) { }
            return code;
        }
        finally { credentials?.Dispose(); }
    }

    private static WindowsAdCredentialSource ReadCredential()
    {
        var input = GetStdHandle(-10);
        if (input == nint.Zero || input == new nint(-1) || GetFileType(input) != 3) throw InvalidCredential();
        // ConsoleStream.ReadAsync on Windows can block in synchronous ReadFile despite a cancelled token.
        // This single consumer reads only bytes already available in its private redirected pipe, with
        // an independent deadline and mandatory EOF; no background reader can retain the secret buffer.
        var elapsed = Stopwatch.StartNew();
        var bytes = new byte[32769];
        var pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            var length = 0;
            while (length < bytes.Length)
            {
                if (elapsed.Elapsed >= TimeSpan.FromSeconds(30)) throw InvalidCredential();
                if (!PeekNamedPipe(input, 0, 0, 0, out var available, 0))
                {
                    if (Marshal.GetLastWin32Error() is 109 or 232) break; // producer closed its end
                    throw InvalidCredential();
                }
                if (available == 0) { Thread.Sleep(10); continue; }
                var count = Math.Min(available, checked((uint)(bytes.Length - length)));
                if (!ReadFile(input, nint.Add(pinned.AddrOfPinnedObject(), length), count, out var read, 0) || read == 0 || read > count)
                    throw InvalidCredential();
                length += checked((int)read);
            }
            if (length is 0 or > 32768) throw InvalidCredential();
            using var document = JsonDocument.Parse(bytes.AsMemory(0, length), new JsonDocumentOptions { MaxDepth = 3 });
            Arguments.Only(document.RootElement, "userName", "blob");
            var user = Arguments.Text(document.RootElement, "userName", true, 512);
            var blob = Arguments.Text(document.RootElement, "blob", true, 24576);
            return WindowsAdCredentialSource.FromProtectedPayload(new(user, blob), interactiveFallback: false);
        }
        catch (Exception error) when (error is JsonException or ArgumentException or IOException or OperationCanceledException)
        { throw InvalidCredential(); }
        finally { CryptographicOperations.ZeroMemory(bytes); pinned.Free(); }
    }

    private static PestoException InvalidCredential() => new("automation.credential",
        "--credential-stdin exige un pipe redirigé fermé, contenant uniquement userName et blob DPAPI CurrentUser UTF-16LE. Aucun dialogue ni mot de passe en argument n’est accepté.");

    private static void Write(PestoCliResult result)
    {
        using var writer = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false), leaveOpen: true);
        writer.WriteLine(JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true }));
        writer.Flush();
    }

    private static void ConnectOutput()
    {
        if (!OperatingSystem.IsWindows()) return;
        var output = GetStdHandle(-11);
        if (output == nint.Zero || output == new nint(-1)) _ = AttachConsole(uint.MaxValue);
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AttachConsole(uint processId);
    [DllImport("kernel32.dll")]
    private static extern nint GetStdHandle(int handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetFileType(nint handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PeekNamedPipe(nint pipe, nint buffer, uint size, nint bytesRead, out uint available, nint bytesLeft);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadFile(nint file, nint buffer, uint count, out uint read, nint overlapped);
}
