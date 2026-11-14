using System.Runtime.InteropServices;
using Pesto.Engine;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellDirectoryGateway : ILocalDomainMembership
{
    private const int NetSetupUnjoined = 1;
    private const int NetSetupWorkgroupName = 2;
    private const int NetSetupDomainName = 3;

    // NetGetJoinInformation is local: no DC, no network. An unknown status or a failed call stays null, never "not joined".
    public bool? LocalComputerJoined
    {
        get
        {
            if (!OperatingSystem.IsWindows()) return null;
            nint name = 0;
            try
            {
                if (NetGetJoinInformation(null, out name, out var status) != 0) return null;
                return status switch { NetSetupDomainName => true, NetSetupWorkgroupName or NetSetupUnjoined => false, _ => null };
            }
            catch (DllNotFoundException) { return null; }
            catch (EntryPointNotFoundException) { return null; }
            finally { if (name != 0) NetApiBufferFree(name); }
        }
    }

    [DllImport("netapi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int NetGetJoinInformation(string? server, out nint name, out int status);
    [DllImport("netapi32.dll", ExactSpelling = true)]
    private static extern int NetApiBufferFree(nint buffer);
}
