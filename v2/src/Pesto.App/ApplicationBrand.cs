namespace Pesto.App;

/// <summary>Local brand resources, also available before WebView and UAC.</summary>
internal static class ApplicationBrand
{
    // A single read-only bitmap is shared for the lifetime of the application.
    internal static Image Mark { get; } = LoadMark();

    internal static Icon CreateWindowIcon()
    {
        using var stream = Open("Pesto.Brand.Icon");
        using var icon = new Icon(stream);
        return (Icon)icon.Clone();
    }

    private static Image LoadMark()
    {
        using var stream = Open("Pesto.Brand.Mark");
        using var image = Image.FromStream(stream);
        return new Bitmap(image);
    }

    private static Stream Open(string name) => typeof(ApplicationBrand).Assembly.GetManifestResourceStream(name)
        ?? throw new InvalidOperationException("La ressource de marque Pesto est absente du programme.");
}
