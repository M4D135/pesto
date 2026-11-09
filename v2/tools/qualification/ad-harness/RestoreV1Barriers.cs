using System.Text.Json;
using Pesto.Engine;

internal static class RestoreV1Barriers
{
    public static void RequireClear(string gpRoot)
    {
        foreach (var relative in new[] { Path.Combine("Join", "receipt.json"), Path.Combine("Operations", "direct.json") })
        {
            var path = Path.Combine(gpRoot, relative);
            for (string? current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
                if ((Directory.Exists(current) || File.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new InvalidOperationException("V1 raw barrier is a link or junction; restore refused.");
            try
            {
                using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                if (input.Length is 0 or > 65536) throw new InvalidOperationException("V1 raw barrier has invalid size; restore refused.");
                using var json = JsonDocument.Parse(input);
                if (!IsClear(json.RootElement)) throw new InvalidOperationException("V1 Join/direct barrier is unresolved; restore refused without any modification.");
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }
    public static bool IsClear(JsonElement receipt)
    {
        if (receipt.ValueKind != JsonValueKind.Object) return false;
        var fields = receipt.EnumerateObject().Select(p => p.Name).ToArray();
        if (fields.Distinct(StringComparer.Ordinal).Count() != fields.Length) return false;
        if (StoredMutationBarrier.IsAcknowledged(receipt)) return true;
        return receipt.TryGetProperty("Phase", out var phase) && phase.ValueKind == JsonValueKind.String
            && new[] { "Failed", "Verified", "NotStarted", "None" }.Contains(phase.GetString(), StringComparer.OrdinalIgnoreCase);
    }
}
