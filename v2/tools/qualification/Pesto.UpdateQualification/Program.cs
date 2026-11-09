using System.Text.Json;

namespace Pesto.UpdateQualification;

internal static class Program
{
    public static async Task<int> Main(string[] args)
    {
        try
        {
            object result = args switch
            {
                ["init", var basePack, var candidatePack, var candidateZip, var root] => Suite.Create(basePack, candidatePack, candidateZip, root),
                ["scenarios", var root] => Suite.Scenarios(Suite.Load(root)),
                ["prepare", var root, var scenario] => await Suite.PrepareAsync(root, scenario),
                ["request", var root, var scenario, var action] => Suite.Request(root, scenario, action),
                ["verify", var root, var scenario, var stage] => Suite.Verify(root, scenario, stage),
                ["cleanup", var root, var scenario] => Suite.Cleanup(root, scenario),
                ["finish", var root] => Suite.Finish(root),
                ["observe", var root, var scenario, var stage, var launch] when OperatingSystem.IsWindows()
                    => NativeMonitor.Observe(root, scenario, stage, launch),
                ["self-test"] => await PortableChecks.RunAsync(),
                ["socle-check", var pack] => Suite.SocleCheck(pack),
                ["ui-init", var currentPack, var targetPack, var targetZip, var root] => UiSuite.Create(currentPack, targetPack, targetZip, root),
                ["ui-adopt", var root] => UiSuite.Adopt(root),
                ["ui-verify", var root, var stage] => UiSuite.Verify(root, stage),
                ["ui-cleanup", var root] => UiSuite.Cleanup(root),
                ["ui-finish", var root] => UiSuite.Finish(root),
                _ => throw new InvalidOperationException("Unknown qualification command, argument count or unsupported native platform.")
            };
            Console.WriteLine(JsonSerializer.Serialize(result, Suite.Json));
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(JsonSerializer.Serialize(new { success = false, error = error.GetType().Name, message = error.Message }, Suite.Json));
            return 2;
        }
    }
}
