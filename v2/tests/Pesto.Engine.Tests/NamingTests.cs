using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class NamingTests
{
    [Test]
    public void DefaultPatternFormatsHistoricalName()
    {
        var convention = new NamingConvention(PestoSettings.DefaultPattern, "111301");
        Check.Equal(3, convention.NumberWidth, "Largeur du numéro");
        Check.Equal(999, convention.Maximum, "Numéro maximum");
        Check.Equal("P111301PAINF001", convention.Format("P", "PA", "INF", 1), "Nom historique portable");
        Check.Equal("S111301LYLOG999", convention.Format("S", "LY", "LOG", 999), "Nom historique fixe");
    }

    [Test]
    public void NumberCanSitInTheMiddleWithCustomWidth()
    {
        var convention = new NamingConvention("{number:2}-{type}{prefix}{site}{service}", "123");
        Check.Equal("05-P123PAINF", convention.Format("P", "PA", "INF", 5), "Numéro en tête, largeur 2");
    }

    [Test]
    public void RejectsMissingOrDuplicatedToken()
    {
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site}{service}", "1"), "invalid_naming", "Numéro manquant refusé");
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site}{service}{number:3}{number:3}", "1"), "invalid_naming", "Numéro dupliqué refusé");
    }

    [Test]
    public void RejectsIllegalSeparatorAndOverlongName()
    {
        Check.Pesto(() => new NamingConvention("{type}_{prefix}{site}{service}{number:3}", "1"), "invalid_naming", "Séparateur illégal refusé");
        Check.Pesto(() => new NamingConvention(PestoSettings.DefaultPattern, "1234567890"), "invalid_naming", "Nom de plus de 15 caractères refusé");
    }

    [Test]
    public void RejectsBadFacetsAtFormatTime()
    {
        var convention = new NamingConvention(PestoSettings.DefaultPattern, "111301");
        Check.Pesto(() => convention.Format("X", "PA", "INF", 1), "invalid_name", "Type hors P/S/V refusé");
        Check.Pesto(() => convention.Format("P", "PAR", "INF", 1), "invalid_name", "Code site invalide refusé");
        Check.Pesto(() => convention.Format("P", "PA", "IN", 1), "invalid_name", "Service hors 3 caractères refusé");
        Check.Pesto(() => convention.Format("P", "PA", "INF", 0), "invalid_name", "Numéro nul refusé");
    }

    [Test]
    public void ConfiguredWidthsAndOrderDriveFormatAndParse()
    {
        // Port du modèle V1 (NAMING_119) : largeurs par facette, numéro ailleurs qu'en fin de nom.
        var convention = new NamingConvention("{service:4}{number:2}{type}{prefix}{site}", "123");
        Check.Equal("INF107P123PA", convention.Format("P", "PA", "INF1", 7), "Service à la largeur 4, numéro au milieu à la largeur 2");
        var parts = convention.TryParse("INF107P123PA");
        Check.NotNull(parts, "Analyse inverse selon les positions configurées");
        Check.Equal("P", parts!.Type, "Type lu à sa position");
        Check.Equal("PA", parts.Site, "Site lu à sa position");
        Check.Equal("INF1", parts.Service, "Service lu à la largeur configurée, pas à un offset fixe");
        Check.Equal(7, parts.Number, "Numéro lu à sa position");
    }

    [Test]
    public void RejectsWidthsOutsideTheV1Bounds()
    {
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site:5}{service}{number:3}", "1"), "invalid_naming", "Site borné à 4 (Assert-PestoNamingConvention)");
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site}{service:7}{number:3}", "1"), "invalid_naming", "Service borné à 6");
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site}{service}{number:7}", "1"), "invalid_naming", "Numéro borné à 6");
        Check.Pesto(() => new NamingConvention("{type}{prefix}{site}{service}{number:0}", "1"), "invalid_naming", "Numéro au moins 1");
        Check.Pesto(() => new NamingConvention("{type}{prefix:2}{site}{service}{number:3}", "1"), "invalid_naming", "La largeur du préfixe est celle du préfixe lu, pas un argument");
    }

    [Test]
    public void TypesIsASubsetWithoutDuplicatesOfPsv()
    {
        Check.Pesto(() => new NamingConvention("{type:PX}{prefix}{site}{service}{number:3}", "1"), "invalid_naming", "Hors P/S/V refusé");
        Check.Pesto(() => new NamingConvention("{type:PP}{prefix}{site}{number:3}{service}", "1"), "invalid_naming", "Doublon de type refusé");
        var fixedOnly = new NamingConvention("{type:S}{prefix}{site}{service}{number:3}", "111301");
        Check.Equal("S111301PAINF001", fixedOnly.Format("S", "PA", "INF", 1), "Le type configuré est admis");
        Check.Pesto(() => fixedOnly.Format("P", "PA", "INF", 1), "invalid_name", "Un type hors de la convention n'est jamais généré");
        Check.Pesto(() => fixedOnly.Format("V", "PA", "INF", 1), "invalid_name", "V hors convention refusée");
    }

    [Test]
    public void NumberWidthSixIsTheV1Ceiling()
    {
        var wide = new NamingConvention("{type}{prefix}{site}{service}{number:6}", "111");
        Check.Equal(999999, wide.Maximum, "10^6 - 1 numéros (plafond v1)");
        Check.Equal("P111PAINF000001", wide.Format("P", "PA", "INF", 1), "Remplissage à la largeur configurée, total 15 caractères");
    }

    [Test]
    public void PreviewSkipsTakenNamesAndAnnouncesCompleteness()
    {
        var backend = Harness.Simulation();
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "paris", service = "INF" });
        Check.Equal("P111301PAINF002", Harness.Str(preview, "name"), "Premier nom libre après le nom déjà pris");
        Check.Equal(998, Harness.Int(preview, "availableCount"), "Nombre de noms libres");
        Check.True(Harness.Bool(preview, "complete"), "Lecture simulée complète");
        Check.Equal("simulation", Harness.Str(preview, "source"), "Source annoncée");
    }

    [Test]
    public void AlternativeProposesADifferentName()
    {
        var backend = Harness.Simulation();
        var first = Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "paris", service = "INF" }), "name");
        var second = Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "paris", service = "INF", alternative = true }), "name");
        Check.False(string.Equals(first, second, StringComparison.Ordinal), "L’alternative change le nom proposé");
    }

    [Test]
    public void PreviewRejectsUnknownFacets()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "X", site = "paris", service = "INF" }), "type.invalid", "Type inconnu");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "mars", service = "INF" }), "site.invalid", "Site inconnu");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "paris", service = "XYZ" }), "service.invalid", "Service inconnu");
    }
}
