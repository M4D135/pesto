using System.Globalization;
using System.IO.Enumeration;

namespace Pesto.Engine;

/// <summary>Choisit parmi les trous de la série relue pour cet aperçu. Aucun état ne survit à cet appel.</summary>
internal static class NameSeriesAvailability
{
    internal static (string? Name, int Count) Select(string series, int width, int maximum,
        IEnumerable<string> unavailableNames, IReadOnlyList<string> exclusions, int previous, Random? random)
    {
        var marker = series.IndexOf('*');
        var prefix = series[..marker];
        var suffix = series[(marker + 1)..];
        var format = "D" + width;
        string Name(int n) => prefix + n.ToString(format, CultureInfo.InvariantCulture) + suffix;

        var taken = new SortedSet<int>();
        foreach (var name in unavailableNames)
        {
            if (name.Length != prefix.Length + width + suffix.Length
                || !name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
                || !name.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) continue;
            var digits = name.AsSpan(prefix.Length, width);
            if (digits.ContainsAnyExceptInRange('0', '9')) continue;
            var number = int.Parse(digits, CultureInfo.InvariantCulture);
            if (number >= 1 && number <= maximum) taken.Add(number);
        }

        if (exclusions.Count != 0)
        {
            // ExcludedNames admits only ASCII letters, digits, hyphens and the V1 wildcards * and ?.
            // Compare the whole formatted name since an exclusion may span multiple facets.
            bool Excluded(string name)
            {
                foreach (var pattern in exclusions)
                    if (FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true)) return true;
                return false;
            }
            int count = 0, eligible = 0;
            string? first = null, chosen = null;
            for (var n = 1; n <= maximum; n++)
            {
                if (taken.Contains(n)) continue;
                var name = Name(n);
                if (Excluded(name)) continue;
                count++;
                first ??= name;
                if (random is null) { if (n > previous) chosen ??= name; }
                else if (n != previous && random.Next(++eligible) == 0) chosen = name;
            }
            return (chosen ?? first, count);
        }

        var available = maximum - taken.Count;
        if (available == 0) return (null, 0);
        if (random is null)
        {
            int After(int n) { while (++n <= maximum && taken.Contains(n)) { } return n; }
            var n = After(previous);
            return (Name(n <= maximum ? n : After(0)), available);
        }

        // Select a uniform rank among the free slots. Skip taken numbers without rendering any other
        // names, including when the configurable series spans 999,999 numbers.
        if (previous >= 1 && previous <= maximum && available > 1) taken.Add(previous);
        var rank = random.Next(maximum - taken.Count) + 1;
        foreach (var n in taken)
        {
            if (n > rank) break;
            rank++;
        }
        return (Name(rank), available);
    }
}
