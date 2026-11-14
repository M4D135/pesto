namespace Pesto.Engine;

/// <summary>
/// Un poste tel qu'observé dans l'annuaire. Une valeur <c>null</c> signifie « non observé », jamais « vide » :
/// le moteur ne remplit jamais une facette inconnue par une valeur supposée.
/// </summary>
public sealed record DirectoryComputer(
    string Name,
    string? DnsName,
    string? Ou,
    string? Os,
    string? Guid,
    string? Domain,
    string? Manufacturer,
    string? Model,
    string? Serial,
    string? Ip,
    bool? PendingRestart);

/// <summary>Lecture bornée : les items ramenés et le drapeau « tout a été lu ». incomplet n'est jamais présenté comme un succès.</summary>
public sealed record DirectorySearchResult(IReadOnlyList<DirectoryComputer> Items, bool Complete);

/// <summary>Inventaire de noms dans une portée, avec le drapeau de complétude de la lecture.</summary>
public sealed record DirectoryNameInventory(IReadOnlyList<string> Names, bool Complete);

/// <summary>Live naming inventory covers the entire domain and all CN/sAM/DNS aliases of one naming series.</summary>
public interface IAutomationNameInventory
{
    DirectoryNameInventory ListAutomationComputerNames(string domain, string dc, string seriesPattern, int maximum);
}

/// <summary>Identity of an organizational unit observed on the selected DC.</summary>
public sealed record DirectoryOrganizationalUnit(string DistinguishedName, string Guid, string? Name = null);

/// <summary>A selected DN must still identify the same configured site when its inventory is collected.</summary>
public sealed record SelectedSiteOu(string DistinguishedName, string? ExpectedName)
{
    public void RequireObserved(DirectoryOrganizationalUnit? ou)
    {
        if (ou is null || !StringComparer.OrdinalIgnoreCase.Equals(ou.DistinguishedName, DistinguishedName)
            || !System.Guid.TryParse(ou.Guid, out var guid) || guid == System.Guid.Empty
            || ExpectedName is not null && !StringComparer.OrdinalIgnoreCase.Equals(ou.Name, ExpectedName))
            throw new Pesto.Core.PestoException("site.invalid", "L’OU sélectionnée n’est plus confirmée par l’annuaire.");
    }
}

public sealed record SiteOuListing(IReadOnlySet<string> Explicit, IReadOnlyDictionary<string, IReadOnlyList<string>> Children);
public sealed record SiteComputerNames(DirectoryNameInventory InOu, DirectoryNameInventory WithTag);

/// <summary>
/// Seam de lecture annuaire du mode réel. Toute implémentation est en lecture seule, bornée et sans secret :
/// jamais de mot de passe, jamais de commande arbitraire, jamais d'écriture. Le moteur refuse chaque chemin
/// qu'une implémentation n'a pas encore qualifié, avec une raison exploitable.
/// </summary>
public interface IDirectoryGateway
{
    /// <summary>Origine observée des faits (ex. « Windows PowerShell 5.1 · module ActiveDirectory »).</summary>
    string Description { get; }

    /// <summary>Contrôleur inscriptible découvert, ou <c>null</c> si la découverte n'a pas abouti.</summary>
    string? DiscoverDomainController(string domain);

    /// <summary>Exact OU identity. A missing reader is refused, never replaced by a DN-only assumption.</summary>
    DirectoryOrganizationalUnit? FindOrganizationalUnit(string domain, string? dc, string distinguishedName)
        => throw new Pesto.Core.PestoException("directory.unavailable", "L’identité GUID de l’OU ne peut pas être lue par cet adaptateur.");

    /// <summary>Recherche bornée par sous-chaîne de nom. La limite est un plafond dur côté lecteur.</summary>
    DirectorySearchResult SearchComputers(string domain, string? dc, string query, int limit);

    /// <summary>Poste par nom exact ; <c>null</c> = absence confirmée. Une ambiguïté est une panne refusée, jamais tranchée.</summary>
    DirectoryComputer? FindComputer(string domain, string? dc, string name);

    /// <summary>Noms des OU enfants directs (résolution des sites, port d'Extract-Site v1).</summary>
    IReadOnlyList<string> ListChildOuNames(string domain, string? dc, string parentOu);

    SiteOuListing ReadSiteOus(string domain, string? dc, IReadOnlyList<string> explicitOus, IReadOnlyList<string> parents)
    {
        var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var dn in explicitOus)
            if (FindOrganizationalUnit(domain, dc, dn)?.DistinguishedName.Equals(dn, StringComparison.OrdinalIgnoreCase) == true)
                found.Add(dn);
        return new(found, parents.ToDictionary(parent => parent, parent => ListChildOuNames(domain, dc, parent), StringComparer.OrdinalIgnoreCase));
    }

    SiteComputerNames ReadSiteComputerNames(string domain, string? dc, string ou, IReadOnlyList<string> sitePatterns, int maximum)
        => throw new Pesto.Core.PestoException("directory.unavailable", "La lecture des services du site est indisponible.");

    SiteComputerNames ReadSelectedSiteComputerNames(string domain, string? dc, SelectedSiteOu site, IReadOnlyList<string> patterns, int maximum)
    {
        site.RequireObserved(FindOrganizationalUnit(domain, dc, site.DistinguishedName));
        return ReadSiteComputerNames(domain, dc, site.DistinguishedName, patterns, maximum);
    }

    DirectoryNameInventory ReadSelectedSiteSeries(string domain, string dc, SelectedSiteOu site, string pattern, int maximum)
    {
        site.RequireObserved(FindOrganizationalUnit(domain, dc, site.DistinguishedName));
        if (this is not IAutomationNameInventory inventory)
            throw new Pesto.Core.PestoException("names.unavailable", "La lecture des noms de la série dans le domaine est indisponible.");
        return inventory.ListAutomationComputerNames(domain, dc, pattern, maximum);
    }

    /// <summary>Noms des ordinateurs d'une portée, lecture bornée ; le drapeau de complétude conditionne toute disponibilité.</summary>
    DirectoryNameInventory ListComputerNames(string domain, string? dc, string scopeOu, int maxRows);
}
