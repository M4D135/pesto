namespace Pesto.Engine.Tests;

internal sealed class NameSeriesAvailabilityTests
{
    private sealed class Rank(int index, int total) : Random
    {
        public override int Next(int maxValue)
        {
            Check.Equal(total, maxValue, "Chaque nom éligible doit correspondre à un rang unique");
            return index;
        }
    }

    [Test]
    public void EveryFreeRankMapsOnceAcrossHolesAndAnAlternativeSkipsOnlyThePreviousName()
    {
        // Number in the middle of the convention; names from other types, widths and suffixes
        // must not consume a slot. Different CN/SAM/DNS spellings of the same alias consume one.
        string[] observed = ["p1-s", "P1-S", "P3-S", "P4-S", "P6-S", "P7-S", "S2-S", "P02-S", "P4-T", "P0-S", "P?-S"];
        string[] eligible = ["P2-S", "P5-S", "P9-S"]; // P8-S was shown last; still included in the free count
        for (int rank = 0; rank < eligible.Length; rank++)
        {
            var (chosen, free) = NameSeriesAvailability.Select("P*-S", 1, 9, observed, [], 8, new Rank(rank, eligible.Length));
            Check.Equal(4, free, "Quatre noms disponibles, même si un seul a été affiché");
            Check.Equal(eligible[rank], chosen, "Un seul rang par nom libre, dans l’ordre des numéros");
        }
        var wrapped = NameSeriesAvailability.Select("P*-S", 1, 9, observed, [], 9, null);
        Check.Equal("P2-S", wrapped.Name, "Le choix séquentiel reprend au premier trou après la fin");
        var only = NameSeriesAvailability.Select("P*-S", 1, 9, observed.Concat(eligible), [], 8, new Rank(0, 1));
        Check.Equal(("P8-S", 1), only, "L'unique nom réellement libre reste disponible");
    }

    [Test]
    public void SparseSixDigitSeriesKeepsCountAndAReleasedEarlyNumberWithoutAnInventoryCache()
    {
        var observed = new List<string> { "P000001-X", "P000002-X", "P000003-X", "P999999-X" };
        var first = NameSeriesAvailability.Select("P*-X", 6, 999999, observed, [], 0, null);
        Check.Equal(("P000004-X", 999995), first, "Le premier trou et le compte exact proviennent des quatre noms");
        observed.Remove("P000002-X");
        var second = NameSeriesAvailability.Select("P*-X", 6, 999999, observed, [], 0, null);
        Check.Equal(("P000002-X", 999996), second, "La lecture suivante inclut immédiatement le nom libéré");
    }

    [Test]
    public void ExplicitWildcardExclusionsContinueToProtectBothCountsAndAlternatives()
    {
        string[] occupied = ["P004-X", "p010-x"];
        string[] excluded = ["p00?-x", "*11-X"];
        var result = NameSeriesAvailability.Select("P*-X", 3, 999, occupied, excluded, 999, null);
        Check.Equal(("P012-X", 979), result, "001–009, 010 et les dix noms en 11 sont indisponibles");
        var none = NameSeriesAvailability.Select("P*-X", 3, 999, occupied, ["*"], 0, null);
        Check.True(none.Name is null && none.Count == 0, "Une exclusion totale ne donne jamais un nom");
    }
}
