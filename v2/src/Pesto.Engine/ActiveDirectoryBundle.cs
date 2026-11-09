using System.Collections.ObjectModel;

namespace Pesto.Engine;

/// <summary>The six unchanged Microsoft files already shipped in Pesto V1. Shared by package validation
/// and the native resolver; declaring or hashing these files never loads a module or contacts AD.</summary>
public static class ActiveDirectoryBundle
{
    public const string RelativeDirectory = "wad/runtime/activedirectory";
    public const string ManifestName = "ActiveDirectory.psd1";

    public static IReadOnlyDictionary<string, string> Sha256 { get; } = new ReadOnlyDictionary<string, string>(new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["ActiveDirectory.psd1"] = "96e41708524316cb13a0d71d36a905f5d530e57e1714a12c3e5b30189a4c83eb",
        ["Microsoft.ActiveDirectory.Management.dll"] = "1a6af7b8f8bce5b35ff873e2528746480c980526d86e38ca5acd04c2e9037157",
        ["ActiveDirectory.Types.ps1xml"] = "3cb55021534ec67fa81d7981ee4b3364eea3ba79ebe61667ee44e14b7a668b3a",
        ["ActiveDirectory.Format.ps1xml"] = "ffefd16b151f10ea80b603f3acba3c361055314bb6b54f8f8f3f0b21e2ae3996",
        ["ActiveDirectoryPowerShellResources.dll"] = "e233d92238aa31ea1b3c60145d8811edb2e517e1b9b53f4bc496883ee5d9973b",
        ["fr-FR/ActiveDirectoryPowerShellResources.dll.mui"] = "bee3c0b2beeb6d5e5600e840e57c7361ef77aabd44006fd7d82f7fcbbfb8541e",
    });
}
