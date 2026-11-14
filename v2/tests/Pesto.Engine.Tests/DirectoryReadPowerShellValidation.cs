using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

// Real PS 5.1, compiled reader and production stdin/bootstrap. Only synthetic in-process cmdlets are imported.
internal static class DirectoryReadPowerShellValidation
{
    private const string Domain = "fixture.invalid", Dc = "dc1.fixture.invalid", DomainDn = "DC=fixture,DC=invalid";
    private const string Parent = "OU=Agences," + DomainDn, Site = "OU=Paris(1)," + Parent;
    private const string Series = "P111301PR765*";
    private static readonly string[] Patterns = ["P111301PR*", "L111301PR*"];
    private static readonly string[] Occupied = Enumerable.Range(1, 12).Select(i => $"P111301PR765{i:D3}").ToArray();
    private sealed record Read(JsonElement Reply, JsonElement[] Calls, int Pid);

    public static async Task<int> Run()
    {
        if (!OperatingSystem.IsWindows()) { Console.Error.WriteLine("Windows PowerShell 5.1 requis pour les cmdlets de test."); return 1; }
        var directory = Path.Combine(Path.GetTempPath(), "Pesto-read-contract-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var module = Path.Combine(directory, "SyntheticPestoDirectory.psm1");
            File.WriteAllText(module, FixtureModule, new UTF8Encoding(true));
            var sites = await Invoke(module, "sites", new { Explicit = new[] { Site, "OU=Missing," + Parent }, Parents = new[] { Parent } });
            var selection = new SelectedSiteOu(Site, "Paris(1)");
            var services = await Invoke(module, "siteServices", new { Ou = Site, Patterns, Max = 20, SelectedSite = selection });
            var names = await Invoke(module, "automationNames", new { Pattern = Series, Max = 12, SelectedSite = selection });
            var siteResult = Result(sites); var serviceResult = Result(services); var seriesResult = Result(names);
            EqualSet(siteResult.GetProperty("found"), [Site]);
            var group = siteResult.GetProperty("groups").EnumerateArray().Single();
            Check.Equal(Parent, Text(group, "parent"), "OU parente demandée"); EqualSet(group.GetProperty("children"), ["Paris(1)", "Lyon"]);
            Check.Equal(2, sites.Calls.Length, "Un lot explicite + une lecture OneLevel");
            var exactOu = sites.Calls[0]; Check.Equal(DomainDn, Text(exactOu, "base"), "DN du domaine des OU explicites");
            Check.Equal("(|(distinguishedName=OU=Paris\\281\\29," + Parent + ")(distinguishedName=OU=Missing," + Parent + "))", Text(exactOu, "ldap"), "DN échappés en un seul filtre LDAP");
            Check.Equal(3, exactOu.GetProperty("limit").GetInt32(), "Borne du lot explicite");
            Check.Equal(Parent, Text(sites.Calls[1], "base"), "OU source des enfants"); Check.Equal("OneLevel", Text(sites.Calls[1], "scope"), "Enfants directs seulement");
            Check.Equal(20001, sites.Calls[1].GetProperty("limit").GetInt32(), "Une ligne supplémentaire pour détecter la limite des OU");
            var v1Sites = await Invoke(module, "sites", new { Explicit = Array.Empty<string>(), Parents = new[] { Parent } }, "v1-sites");
            var observed = Result(v1Sites).GetProperty("groups").EnumerateArray().Single().GetProperty("children")
                .EnumerateArray().Select(item => item.GetString()!).ToArray();
            Check.Equal(1, v1Sites.Calls.Length, "Sans sites explicites V2, une lecture OneLevel retrouve aussi les sites ordinaires");
            AuditSiteCompatibilityTests.VerifyObservedSites(observed);
            EqualSet(serviceResult.GetProperty("inOu"), [Occupied[0], "P111301LY888001"]);
            EqualSet(serviceResult.GetProperty("withTag"), [Occupied[0], Occupied[3], Occupied[6], Occupied[9]]);
            Check.True(serviceResult.GetProperty("complete").GetBoolean(), "Inventaire des services complet");
            Check.Equal(3, services.Calls.Length, "Identité OU et deux lectures AD dans un worker pour les services");
            Check.Equal(Site, Text(services.Calls[0], "identity"), "OU exacte relue avant les postes");
            Check.Equal(Site, Text(services.Calls[1], "base"), "Postes du sous-arbre du site");
            Check.Equal("(|(name=P111301*)(name=L111301*))", Text(services.Calls[1], "ldap"), "Préfixes d’organisme filtrés dans l’OU, tous tags conservés");
            Check.Equal(DomainDn, Text(services.Calls[2], "base"), "Motifs de tag recherchés dans tout le domaine");
            Check.Equal("(|(name=P111301PR*)(name=L111301PR*))", Text(services.Calls[2], "ldap"), "Tous les types du site dans une seule lecture");
            foreach (var call in services.Calls.Skip(1)) RequireSubtree(call, 21);
            Check.True(seriesResult.GetProperty("complete").GetBoolean(), "Douze objets ne dépassent pas la borne de douze");
            var aliases = seriesResult.GetProperty("names").EnumerateArray().Select(x => x.GetString()!).ToArray();
            Check.True(Occupied.All(n => aliases.Contains(n, StringComparer.OrdinalIgnoreCase)), "CN, sAM sans $ et DNS sans suffixe occupent 001 à 012");
            Check.False(aliases.Any(n => n.EndsWith('$') || n.Contains('.')), "Alias normalisés avant la recherche du premier trou");
            var firstUnused = Enumerable.Range(1, 999).Select(i => $"P111301PR765{i:D3}").First(n => !aliases.Contains(n, StringComparer.OrdinalIgnoreCase));
            Check.Equal("P111301PR765013", firstUnused, "Premier trou de la série des alias synthétiques");
            Check.Equal(2, names.Calls.Length, "Identité OU et inventaire de série dans le même worker");
            Check.Equal(Site, Text(names.Calls[0], "identity"), "OU vérifiée avant les alias globaux");
            var query = names.Calls[1]; RequireSubtree(query, 13);
            Check.Equal(DomainDn, Text(query, "base"), "Série sur tout le domaine, autres OU comprises");
            Check.Equal("(|(name=P111301PR765*)(sAMAccountName=P111301PR765*$)(dNSHostName=P111301PR765*.*))", Text(query, "ldap"), "Un seul filtre sur les trois identités");
            EqualSet(query.GetProperty("properties"), ["SamAccountName", "DNSHostName"]);
            var nominal = new[] { sites, services, names };
            Check.True(nominal.All(r => r.Calls.All(c => Text(c, "server") == Dc && c.GetProperty("pid").GetInt32() == r.Pid)), "Un processus et le DC prévu pour chaque lecture");

            foreach (var mode in new[] { "foreign-ou", "empty-ou-guid", "renamed-ou", "missing-ou" })
            {
                var refused = await Invoke(module, "automationNames", new { Pattern = Series, Max = 12, SelectedSite = selection }, mode);
                Check.False(refused.Reply.GetProperty("ok").GetBoolean(), "OU non confirmée : " + mode);
                Check.Equal(1, refused.Calls.Length, "Aucune lecture de noms après refus d’identité OU : " + mode);
            }
            // Undersized bounds and failures after a first successful query cannot be presented as complete results.
            foreach (var mode in new[] { "overflow-ou", "overflow-tag" })
            {
                var clipped = Result(await Invoke(module, "siteServices", new { Ou = Site, Patterns, Max = 3 }, mode));
                Check.Equal(mode == "overflow-ou" ? 4 : 1, clipped.GetProperty("inOu").GetArrayLength(), "Borne réellement atteinte dans la lecture OU prévue");
                Check.Equal(mode == "overflow-tag" ? 4 : 1, clipped.GetProperty("withTag").GetArrayLength(), "Borne réellement atteinte dans la lecture du tag prévue");
                Check.False(clipped.GetProperty("complete").GetBoolean(), "Chacune des deux lectures peut rendre les services incomplets");
            }
            var clippedSeries = await Invoke(module, "automationNames", new { Pattern = Series, Max = 11 });
            Check.False(Result(clippedSeries).GetProperty("complete").GetBoolean(), "Une page de noms tronquée reste inconnue");
            foreach (var operation in new[] { "sites", "siteServices", "automationNames" })
            {
                object payload = operation switch {
                    "sites" => new { Explicit = new[] { Site }, Parents = new[] { Parent } },
                    "siteServices" => new { Ou = Site, Patterns, Max = 20 },
                    _ => new { Pattern = Series, Max = 12 }
                };
                var failed = await Invoke(module, operation, payload, "partial");
                Check.False(failed.Reply.GetProperty("ok").GetBoolean(), "Erreur du fournisseur : " + operation);
                Check.False(failed.Reply.TryGetProperty("result", out _), "Aucun résultat partiel publié : " + operation);
                Check.Contains("fixture.partial", Text(failed.Reply, "message"), "Refus causé par la panne simulée : " + operation);
            }
            var many = Enumerable.Range(0, 65).Select(n => n == 0 ? Site : "OU=Extra" + n + "," + Parent).ToArray();
            var batch = await Invoke(module, "sites", new { Explicit = many, Parents = Array.Empty<string>() });
            EqualSet(Result(batch).GetProperty("found"), [Site]);
            Check.True(batch.Calls.Select(x => x.GetProperty("limit").GetInt32()).SequenceEqual([65, 2]), "65 OU groupées 64+1 dans un seul processus");
            var excessive = await Invoke(module, "sites", new { Explicit = Array.Empty<string>(), Parents = new[] { Parent } }, "overflow");
            Check.False(excessive.Reply.GetProperty("ok").GetBoolean(), "La lecture de 20 001 OU échoue");
            Check.False(excessive.Reply.TryGetProperty("result", out _), "Aucune liste d’OU tronquée publiée");
            Check.Contains("incomplète", Text(excessive.Reply, "message"), "Refus causé par la borne des OU");
            Console.WriteLine(JsonSerializer.Serialize(new { kind = "pesto.directory-reads-ps51-fixture", success = true,
                powershell = "5.1", adExecuted = false, provider = "local synthetic module", scriptSha256 = Convert.ToHexStringLower(
                    SHA256.HashData(Encoding.UTF8.GetBytes(PowerShellDirectoryGateway.ConstantScript))),
                nominalWorkers = nominal.Length, nominalDirectoryCalls = nominal.Sum(r => r.Calls.Length), seriesWorkers = 1, seriesDirectoryCalls = names.Calls.Length,
                occupied = Occupied.Length, firstUnoccupiedFixtureMember = firstUnused, selectedOuRefusals = 4, incompleteAndFailureCases = 7,
                v1ObservedSites = observed.Length, v1ConfiguredPreproductionSites = 2, v1SuffixSites = 2 }));
            return 0;
        }
        catch (Exception e) { Console.Error.WriteLine("ECHEC lectures synthétiques PS5.1 : " + e.Message); return 1; }
        finally { Directory.Delete(directory, true); }
    }

    private static JsonElement Result(Read value)
    {
        Check.True(value.Reply.GetProperty("ok").GetBoolean(), "Résultat du script compilé : " + value.Reply);
        return value.Reply.GetProperty("result");
    }
    private static string? Text(JsonElement value, string name) => value.GetProperty(name).GetString();
    private static void EqualSet(JsonElement array, string[] expected) => Check.True(array.EnumerateArray().Select(x => x.GetString()!)
        .Order(StringComparer.Ordinal).SequenceEqual(expected.Order(StringComparer.Ordinal)), "Valeurs attendues : " + string.Join(", ", expected));
    private static void RequireSubtree(JsonElement call, int limit)
    {
        Check.Equal("Subtree", Text(call, "scope"), "Sous-arbre explicitement demandé");
        Check.Equal(500, call.GetProperty("page").GetInt32(), "Taille de page AD");
        Check.Equal(limit, call.GetProperty("limit").GetInt32(), "Borne avec ligne sentinelle");
    }

    private static async Task<Read> Invoke(string module, string op, object payload, string mode = "normal")
    {
        var script = PowerShellDirectoryGateway.ConstantScript;
        var request = JsonSerializer.SerializeToNode(payload)!.AsObject();
        request["Op"] = op; request["Domain"] = Domain; request["Server"] = Dc; request["ModulePath"] = module; request["Credential"] = null;
        var trace = Path.Combine(Path.GetDirectoryName(module)!, Guid.NewGuid().ToString("N") + ".jsonl");
        var output = await PowerShellTestWorker.Execute(script, script, request.ToJsonString(), start =>
        {
            start.Environment["PESTO_FIXTURE_TRACE"] = trace; start.Environment["PESTO_FIXTURE_MODE"] = mode;
        }, timeoutSeconds: 45);
        Check.Equal(0, output.Code, "Bootstrap PS5.1 : " + output.Stderr);
        using var response = JsonDocument.Parse(output.Stdout);
        Check.True(File.Exists(trace), "Le module synthétique doit tracer ses lectures : " + response.RootElement);
        var calls = File.ReadAllLines(trace).Select(line => JsonSerializer.Deserialize<JsonElement>(line)).ToArray();
        return new(response.RootElement.Clone(), calls, output.Pid);
    }

    private const string FixtureModule = """
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Windows PowerShell 5.1 required'}
if($env:ADPS_LoadDefaultDrive -cne '0'){throw 'Unexpected automatic AD drive initialization'}
$global:PSModuleAutoLoadingPreference='None'
$root='DC=fixture,DC=invalid';$parent='OU=Agences,'+$root;$site='OU=Paris(1),'+$parent
function Trace-Call($p){
  if($p.Server -cne 'dc1.fixture.invalid'){throw 'Unexpected fixture DC'}
  $event=[ordered]@{pid=$PID;server=[string]$p.Server;identity=[string]$p.Identity;base=[string]$p.SearchBase;scope=[string]$p.SearchScope;filter=[string]$p.Filter;ldap=[string]$p.LDAPFilter;properties=@($p.Properties);limit=[int]$p.ResultSetSize;page=[int]$p.ResultPageSize}
  [IO.File]::AppendAllText($env:PESTO_FIXTURE_TRACE,(ConvertTo-Json $event -Compress)+[Environment]::NewLine)
}
function Get-ADOrganizationalUnit {
  [CmdletBinding()]param([string]$Server,[string]$Identity,[string[]]$Properties,[string]$SearchBase,[string]$SearchScope,[string]$Filter,[string]$LDAPFilter,[int]$ResultSetSize,[int]$ResultPageSize)
  Trace-Call $PSBoundParameters
  if($Identity){
    if($Identity -cne $site){throw 'Unexpected selected OU'}
    if($env:PESTO_FIXTURE_MODE -eq 'missing-ou'){return}
    $dn=if($env:PESTO_FIXTURE_MODE -eq 'foreign-ou'){'OU=Foreign,'+$parent}else{$site}
    $name=if($env:PESTO_FIXTURE_MODE -eq 'renamed-ou'){'Foreign'}else{'Paris(1)'}
    $guid=if($env:PESTO_FIXTURE_MODE -eq 'empty-ou-guid'){[Guid]::Empty}else{[Guid]'11111111-2222-3333-4444-555555555555'}
    [pscustomobject]@{DistinguishedName=$dn;Name=$name;ObjectGUID=$guid};return
  }
  if($LDAPFilter){if($SearchBase -cne $root){throw 'Unexpected OU base'};if($LDAPFilter.Contains('OU=Paris\281\29,')){[pscustomobject]@{DistinguishedName=$site}};return}
  if($SearchBase -cne $parent -or $SearchScope -cne 'OneLevel'){throw 'Unexpected OU child scope'}
  if($env:PESTO_FIXTURE_MODE -eq 'v1-sites'){
    foreach($name in @('222_PROD_A_NOMMER','222_PREPROD','AgenceMN','SIEGE-XY')){[pscustomobject]@{Name=$name}}
    return
  }
  if($env:PESTO_FIXTURE_MODE -eq 'overflow'){for($i=0;$i -lt $ResultSetSize;$i++){[pscustomobject]@{Name="child$i"}};return}
  [pscustomobject]@{Name='Paris(1)'}
  if($env:PESTO_FIXTURE_MODE -eq 'partial'){throw 'fixture.partial'}
  [pscustomobject]@{Name='Lyon'}
}
function Get-ADComputer {
  [CmdletBinding()]param([string]$Server,[string]$SearchBase,[string]$SearchScope,[string]$Filter,[string]$LDAPFilter,[string[]]$Properties,[int]$ResultSetSize,[int]$ResultPageSize)
  Trace-Call $PSBoundParameters
  $rows=@(foreach($i in 1..12){
    $n='P111301PR765{0:d3}' -f $i;$other='OTHER{0:d3}' -f $i
    [pscustomobject]@{Name=$(if($i%3 -eq 1){$n}else{$other});SamAccountName=$(if($i%3 -eq 2){$n+'$'}else{$other+'$'});DNSHostName=$(if($i%3 -eq 0){$n+'.fixture.invalid'}else{$other+'.fixture.invalid'});InSite=($i -le 3)}
  })
  $rows+=@([pscustomobject]@{Name='P111301LY888001';SamAccountName='LEGACY$';DNSHostName='old.fixture.invalid';InSite=$true})
  if($SearchBase -ceq $site -and $LDAPFilter -ceq '(|(name=P111301*)(name=L111301*))'){
    if($env:PESTO_FIXTURE_MODE -eq 'overflow-ou'){
      $rows+=@(1..4|ForEach-Object{[pscustomobject]@{Name=('P111301ZZ765{0:d3}' -f $_);SamAccountName='';DNSHostName='';InSite=$true}})
    }
    $selected=@($rows|Where-Object {$_.InSite -and ($_.Name -like 'P111301*' -or $_.Name -like 'L111301*')})
  }
  elseif($SearchBase -ceq $root -and $LDAPFilter -ceq '(|(name=P111301PR*)(name=L111301PR*))'){$selected=@($rows|Where-Object {$_.Name -like 'P111301PR*' -or $_.Name -like 'L111301PR*'})}
  elseif($SearchBase -ceq $root -and $LDAPFilter -ceq '(|(name=P111301PR765*)(sAMAccountName=P111301PR765*$)(dNSHostName=P111301PR765*.*))'){$selected=@($rows|Where-Object {$_.Name -like 'P111301PR765*' -or $_.SamAccountName -like 'P111301PR765*$' -or $_.DNSHostName -like 'P111301PR765*.*'})}
  else{throw 'Unexpected computer filter or base'}
  if(($env:PESTO_FIXTURE_MODE -eq 'overflow-ou' -and $SearchBase -ceq $root) -or ($env:PESTO_FIXTURE_MODE -eq 'overflow-tag' -and $SearchBase -ceq $site)){$selected=@($selected|Select-Object -First 1)}
  foreach($row in ($selected|Select-Object -First $ResultSetSize)){
    $row
    if($env:PESTO_FIXTURE_MODE -eq 'partial' -and $SearchBase -ceq $root){throw 'fixture.partial'}
  }
}
Export-ModuleMember -Function Get-ADComputer,Get-ADOrganizationalUnit
""";
}
