using System.Text.Json;

internal static class LabDomain
{
    private static string? _name;

    public static string Name
    {
        get
        {
            if (_name is not null) return _name;
            var env = Environment.GetEnvironmentVariable("PESTO_LABO_DOMAINE");
            if (!string.IsNullOrEmpty(env)) return _name = env;
            var path = Path.Combine(AppContext.BaseDirectory, "lab.local.json");
            if (File.Exists(path))
            {
                using var doc = JsonDocument.Parse(File.ReadAllText(path));
                if (doc.RootElement.TryGetProperty("domain", out var d) && d.ValueKind == JsonValueKind.String)
                {
                    var val = d.GetString();
                    if (!string.IsNullOrEmpty(val)) return _name = val;
                }
            }
            throw new InvalidOperationException("Domaine du labo absent : PESTO_LABO_DOMAINE ou lab.local.json.");
        }
    }

    public static string Dn => "DC=" + string.Join(",DC=", Name.Split('.'));
    public static string Dc => "dc01." + Name;

    public static void UseForTests(string name) => _name = name;
}
