using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pesto.Core;

public interface IPestoBackend
{
    Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default);
}

public sealed class PestoException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}

public static class PestoJson
{
    public static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    public static JsonElement Element(object value) => JsonSerializer.SerializeToElement(value, Options);
}

public static class Arguments
{
    public static void Only(JsonElement args, params string[] allowed)
    {
        if (args.ValueKind != JsonValueKind.Object) throw new PestoException("invalid_arguments", "Les arguments doivent être un objet JSON.");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in args.EnumerateObject())
            if (!allowed.Contains(item.Name, StringComparer.Ordinal) || !seen.Add(item.Name))
                throw new PestoException("invalid_arguments", "Champ inconnu ou répété : " + item.Name);
    }
    public static string Text(JsonElement args, string name, bool required = false, int maximum = 4096)
    {
        if (!args.TryGetProperty(name, out var value))
        {
            if (required) throw new PestoException("invalid_arguments", "Champ requis : " + name);
            return "";
        }
        if (value.ValueKind != JsonValueKind.String) throw new PestoException("invalid_arguments", "Texte attendu : " + name);
        var result = value.GetString()!.Trim();
        if (result.Length > maximum || result.Any(char.IsControl) || (required && result.Length == 0))
            throw new PestoException("invalid_arguments", "Valeur invalide : " + name);
        return result;
    }
    public static bool Flag(JsonElement args, string name, bool fallback = false)
    {
        if (!args.TryGetProperty(name, out var value)) return fallback;
        if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new PestoException("invalid_arguments", "Booléen attendu : " + name);
        return value.GetBoolean();
    }
    public static int Number(JsonElement args, string name, int fallback, int minimum, int maximum)
    {
        if (!args.TryGetProperty(name, out var value)) return fallback;
        if (!value.TryGetInt32(out var result) || result < minimum || result > maximum)
            throw new PestoException("invalid_arguments", "Nombre hors limites : " + name);
        return result;
    }
}

public sealed record Site(string Id, string Name, string Code, string Ou);
public sealed record Service(string Code, string Name);
public sealed record Capability(string Id, bool Enabled, string Reason);
public sealed record Check(string Label, string State, string Detail);
public sealed record Receipt(string Id, DateTimeOffset Time, string Kind, string Computer, string NewName,
    string TargetOU, string Mode, string Status, int Code, string Message, bool RestartRequired,
    string? ParentReceiptId = null, string? ResolutionChildReceiptId = null);
public sealed record LogEntry(string Id, DateTimeOffset Time, string Level, string Message);

public sealed record PestoSettings(string Domain, string Dc, string Prefix, bool Production,
    string NamingPattern, bool RandomNames, Site[] Sites, bool Simulation, bool LiveExecutionEnabled)
{
    public const string DefaultPattern = "{type}{prefix}{site}{service}{number:3}";
    public static PestoSettings Demo => new("example.local", "dc01.example.local", "111301", true,
        DefaultPattern, false,
        [new("paris", "Paris", "PA", "OU=Paris,OU=Postes,DC=example,DC=local"),
         new("lyon", "Lyon", "LY", "OU=Lyon,OU=Postes,DC=example,DC=local")], true, false);

    public static PestoSettings Parse(JsonElement args, bool simulation)
    {
        Arguments.Only(args, "domain", "dc", "prefix", "production", "namingPattern", "randomNames", "sites", "simulation", "liveExecutionEnabled");
        if (args.TryGetProperty("simulation", out _) && Arguments.Flag(args, "simulation") != simulation)
            throw new PestoException("mode_fixed", "Le mode ne peut pas être modifié depuis les paramètres.");
        if (Arguments.Flag(args, "liveExecutionEnabled")) throw new PestoException("live_execution_unavailable", "Les écritures réelles ne peuvent pas être activées par les paramètres.");
        var domain = Arguments.Text(args, "domain", true, 253).ToLowerInvariant();
        var dc = Arguments.Text(args, "dc", false, 253).ToLowerInvariant();
        if (!Regex.IsMatch(domain, @"^(?=.{3,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$"))
            throw new PestoException("invalid_settings", "Le domaine doit être un nom DNS complet.");
        if (dc.Length > 0 && (!dc.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase) || dc.Length > 253 || !Regex.IsMatch(dc, @"^[a-z0-9][a-z0-9.-]*$")))
            throw new PestoException("invalid_settings", "Le contrôleur doit être un FQDN du domaine configuré.");
        var prefix = Arguments.Text(args, "prefix", true, 10).ToUpperInvariant();
        if (!Regex.IsMatch(prefix, "^[A-Z0-9]{1,10}$")) throw new PestoException("invalid_settings", "Préfixe alphanumérique attendu.");
        if (!args.TryGetProperty("sites", out var siteValues) || siteValues.ValueKind != JsonValueKind.Array || siteValues.GetArrayLength() is < 1 or > 100)
            throw new PestoException("invalid_settings", "Définissez de 1 à 100 sites.");
        var sites = new List<Site>();
        var domainDn = string.Join(',', domain.Split('.').Select(s => "DC=" + s));
        foreach (var value in siteValues.EnumerateArray())
        {
            Arguments.Only(value, "id", "name", "code", "ou");
            var id = Arguments.Text(value, "id", true, 80);
            var name = Arguments.Text(value, "name", true, 100);
            var code = Arguments.Text(value, "code", true, 2).ToUpperInvariant();
            var ou = Arguments.Text(value, "ou", true, 2048);
            if (!Regex.IsMatch(id, @"^[A-Za-z0-9_-]+$") || !Regex.IsMatch(code, "^[A-Z]{2}$") || !ou.StartsWith("OU=", StringComparison.OrdinalIgnoreCase) || !ou.EndsWith("," + domainDn, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("invalid_settings", "Identifiant, code ou OU du site invalide : " + name);
            if (sites.Any(s => s.Id.Equals(id, StringComparison.OrdinalIgnoreCase) || s.Code.Equals(code, StringComparison.OrdinalIgnoreCase) || s.Ou.Equals(ou, StringComparison.OrdinalIgnoreCase)))
                throw new PestoException("invalid_settings", "Les identifiants, codes et OU des sites doivent être uniques.");
            sites.Add(new(id, name, code, ou));
        }
        var settings = new PestoSettings(domain, dc, prefix, Arguments.Flag(args, "production"),
            Arguments.Text(args, "namingPattern", true, 150), Arguments.Flag(args, "randomNames"), sites.ToArray(), simulation, false);
        _ = new NamingConvention(settings.NamingPattern, settings.Prefix);
        return settings;
    }
}

/// <summary>
/// Convention de nommage administrable, portée du modèle V1 (Assert-PestoNamingConvention / Get-PestoNamingLayout) :
/// les cinq facettes Type, Prefix, Site, Service et Number sont alignées exactement une fois chacune, dans l'ordre
/// configuré — le numéro peut se trouver ailleurs qu'en fin de nom —, chaque facette a une largeur fixe (site 1 à 4,
/// service 1 à 6, numéro 1 à 6 ; la largeur du préfixe est celle du préfixe lu), le type est un sous-ensemble sans
/// doublon de P, S et V, et le total reste plafonné à 15 caractères (plafond NetBIOS). Le contrat du pont rend la
/// convention sous forme de motif : <c>{type}</c> (ou <c>{type:PS}</c> pour un sous-ensemble), <c>{prefix}</c>,
/// <c>{site}</c>/<c>{site:3}</c>, <c>{service}</c>/<c>{service:4}</c>, <c>{number:2}</c> ; seuls des tirets séparent.
/// L'analyse inverse lit chaque facette à la position que la largeur lui donne, jamais à un offset fixe.
/// </summary>
public sealed class NamingConvention
{
    /// <summary>Facettes lues à la position que la convention leur donne, jamais à un offset fixe (port de ConvertTo-PestoNameParts v1).</summary>
    public sealed record NameParts(string Type, string Site, string Service, int Number);

    internal const string HistoricalOrder = "Type,Prefix,Site,Service,Number";
    private static readonly Regex Token = new(@"\{(?<name>type|prefix|site|service|number)(?::(?<arg>[A-Za-z0-9]{1,6}))?\}", RegexOptions.CultureInvariant);

    private readonly string pattern;
    private readonly string prefix;
    private readonly Regex parser;
    public int Maximum { get; }
    public int NumberWidth { get; }
    public int PrefixWidth { get; }
    public int SiteWidth { get; }
    public int ServiceWidth { get; }
    public string Types { get; }
    public IReadOnlyList<string> Tokens { get; }

    /// <summary>Convention historique rendue par l'absence de NamingConvention dans le cfg.json V1 (format livré de tous les cfg existants).</summary>
    public bool IsHistoricalDefault =>
        Types == "PSV" && PrefixWidth == 6 && SiteWidth == 2 && ServiceWidth == 3 && NumberWidth == 3 &&
        string.Join(',', Tokens) == HistoricalOrder;

    /// <summary>Rendu canonique du motif (largeurs omises quand elles sont historiques) : ce que le pont rend dans settings.get.</summary>
    public string ToPattern() => string.Concat(Tokens.Select(token => token switch
    {
        "Type" => Types == "PSV" ? "{type}" : "{type:" + Types + "}",
        "Prefix" => "{prefix}",
        "Site" => SiteWidth == 2 ? "{site}" : "{site:" + SiteWidth + "}",
        "Service" => ServiceWidth == 3 ? "{service}" : "{service:" + ServiceWidth + "}",
        _ => "{number:" + NumberWidth + "}",
    }));

    public NamingConvention(string pattern, string prefix)
    {
        this.pattern = pattern;
        this.prefix = prefix;
        PrefixWidth = prefix.Length;
        Types = "PSV";
        SiteWidth = 2;
        ServiceWidth = 3;
        var order = new List<string>();
        foreach (Match token in Token.Matches(pattern))
        {
            var name = char.ToUpperInvariant(token.Groups["name"].Value[0]) + token.Groups["name"].Value[1..];
            var arg = token.Groups["arg"].Success ? token.Groups["arg"].Value : null;
            if (order.Contains(name, StringComparer.Ordinal)) throw Invalid("chaque facette doit figurer exactement une fois.");
            switch (name)
            {
                case "Type":
                    if (arg is not null && (arg.Length is < 1 or > 3 || arg.Distinct().Count() != arg.Length || !arg.All(c => c is 'P' or 'S' or 'V')))
                        throw Invalid("types : sous-ensemble sans doublon de P, S et V (ex. {type:PS}).");
                    if (arg is not null) Types = arg;
                    break;
                case "Prefix":
                    if (arg is not null) throw Invalid("prefix ne prend pas de largeur : sa largeur est celle du préfixe réellement lu.");
                    break;
                case "Site":
                    if (arg is not null && (!int.TryParse(arg, out var siteWidth) || siteWidth < 1 || siteWidth > 4))
                        throw Invalid("site : largeur 1 à 4 caractères alphabétiques.");
                    if (arg is not null) SiteWidth = int.Parse(arg, System.Globalization.CultureInfo.InvariantCulture);
                    break;
                case "Service":
                    if (arg is not null && (!int.TryParse(arg, out var serviceWidth) || serviceWidth < 1 || serviceWidth > 6))
                        throw Invalid("service : largeur 1 à 6 caractères alphanumériques.");
                    if (arg is not null) ServiceWidth = int.Parse(arg, System.Globalization.CultureInfo.InvariantCulture);
                    break;
                default:
                    if (arg is null || !int.TryParse(arg, out var numberWidth) || numberWidth < 1 || numberWidth > 6)
                        throw Invalid("number:1 à number:6 est requis une seule fois.");
                    NumberWidth = int.Parse(arg, System.Globalization.CultureInfo.InvariantCulture);
                    break;
            }
            order.Add(name);
        }
        // Sans doublon (refusé ci-dessus) et avec uniquement les cinq facettes canoniques, cinq jetons = une permutation exacte.
        if (order.Count != 5)
            throw Invalid("type, prefix, site, service et number requis une seule fois chacun, dans l'ordre configuré.");
        Tokens = order;
        if (NumberWidth == 0) throw Invalid("number:1 à number:6 est requis une seule fois.");
        Maximum = (int)Math.Pow(10, NumberWidth) - 1;
        if (Token.Replace(pattern, "").Any(c => c != '-'))
            throw Invalid("seuls des tirets séparent les facettes.");
        var example = Format(Types[0].ToString(), new string('A', SiteWidth), new string('A', ServiceWidth), 1);
        if (example.Length > 15 || example.StartsWith('-') || example.EndsWith('-'))
            throw new PestoException("invalid_naming", "Le nom généré doit respecter la limite Windows de 15 caractères et ne pas commencer ou finir par un tiret.");
        parser = new Regex(BuildParserRegex(), RegexOptions.CultureInvariant | RegexOptions.Compiled);
    }

    private static PestoException Invalid(string reason) =>
        new("invalid_naming", "Convention refusée : " + reason + " Exemple historique : {type}{prefix}{site}{service}{number:3}.");

    private string BuildParserRegex()
    {
        var builder = new System.Text.StringBuilder("^");
        for (var i = 0; i < pattern.Length;)
        {
            if (pattern[i] != '{')
            {
                builder.Append(Regex.Escape(pattern[i].ToString()));
                i++;
                continue;
            }
            var end = pattern.IndexOf('}', i);
            var name = pattern[(i + 1)..end].Split(':')[0];
            builder.Append(name switch
            {
                "type" => "(?<type>[" + Types + "])",
                "prefix" => Regex.Escape(prefix),
                "site" => "(?<site>[A-Z]{" + SiteWidth + "})",
                "service" => "(?<service>[A-Z0-9]{" + ServiceWidth + "})",
                _ => "(?<number>\\d{" + NumberWidth + "})",
            });
            i = end + 1;
        }
        return builder.Append('$').ToString();
    }

    /// <summary>Analyse un nom observé selon la convention. Le numéro historique 000 est admis en lecture, jamais en génération.</summary>
    public NameParts? TryParse(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var match = parser.Match(name.Trim().ToUpperInvariant());
        if (!match.Success) return null;
        var number = int.Parse(match.Groups["number"].Value, System.Globalization.CultureInfo.InvariantCulture);
        if (number < 0 || number > Maximum) return null;
        return new NameParts(match.Groups["type"].Value, match.Groups["site"].Value, match.Groups["service"].Value, number);
    }
    public string Format(string type, string site, string service, int number)
    {
        if (type.Length != 1 || Types.IndexOf(type[0], StringComparison.Ordinal) < 0
            || !Regex.IsMatch(site, "^[A-Z]{" + SiteWidth + "}$") || !Regex.IsMatch(service, "^[A-Z0-9]{" + ServiceWidth + "}$")
            || number < 1 || number > Maximum)
            throw new PestoException("invalid_name", "Type, code site, service ou numéro invalide pour la convention active.");
        return Render(type, site, service, number.ToString("D" + NumberWidth, System.Globalization.CultureInfo.InvariantCulture));
    }

    // LDAP wildcards stand only for convention facets. Keep literal separators and token order.
    public string SeriesPattern(string type, string site, string service)
    {
        _ = Format(type, site, service, 1);
        return Render(type, site, service, "*");
    }

    public string SitePattern(string type, string site)
    {
        _ = Format(type, site, new string('A', ServiceWidth), 1);
        return Render(type, site, "*", "*").Replace("**", "*", StringComparison.Ordinal);
    }

    private string Render(string type, string site, string service, string number) =>
        Token.Replace(pattern, m => m.Groups["name"].Value switch
        {
            "type" => type,
            "prefix" => prefix,
            "site" => site,
            "service" => service,
            _ => number,
        }).ToUpperInvariant();
}
