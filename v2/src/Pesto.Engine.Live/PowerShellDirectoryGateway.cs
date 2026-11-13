using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>
/// Adaptateur transitoire de lecture annuaire : Windows PowerShell 5.1 + module ActiveDirectory, exécutés avec
/// l'identité de la session courante, jamais un mot de passe, jamais une invite (-NonInteractive). Le script est une
/// constante du binaire : le pont ne transmet jamais de commande arbitraire et le script ne contient que des cmdlets
/// de lecture (Get-ADComputer, Get-ADOrganizationalUnit, Get-ADDomainController -Discover). Les gardes reprises de V1 :
/// -Server explicite, -ResultSetSize borné, -ResultPageSize 500, validation du nom avant filtre, échappement LDAP,
/// reprise uniquement sur panne réseau transitoire (port d'Invoke-PestoReadRetry), jamais de sélection arbitraire sur
/// un nom ambigu, aucune écriture, aucun mode non accompagné. Hors Windows ou sans module, chaque lecture est refusée
/// avec une raison exploitable : aucun fait n'est inventé.
/// </summary>
public sealed partial class PowerShellDirectoryGateway : IDirectoryGateway, IDirectoryAccountDisclosure, IAutomationNameInventory, IDisposable
{
    private const int TimeoutSeconds = 30;
    private const int ReadAttempts = 2;
    private const long MaximumResponseBytes = 8 * 1024 * 1024;
    private static readonly string PowerShellPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

    private readonly string? unavailableReason;
    private readonly IWindowsCredentialSource? credentials;
    private readonly string? v1InstallationPath;
    private readonly InteractiveReadSession? interactive;
    private int disposed;

    public string Description => "Windows PowerShell 5.1 · module ActiveDirectory · compte Windows ou compte AD explicite, secret en mémoire seule";
    public string? SelectedAccount => credentials?.DisplayUserName;

    // The CLI, mutation guards and qualification callers use this isolated, one-shot reader.
    public PowerShellDirectoryGateway(IWindowsCredentialSource? credentials = null, string? v1InstallationPath = null)
        : this(credentials, v1InstallationPath, false) { }

    public static PowerShellDirectoryGateway ForInteractiveReads(IWindowsCredentialSource? credentials, string? v1InstallationPath)
        => new(credentials, v1InstallationPath, true);

    private PowerShellDirectoryGateway(IWindowsCredentialSource? credentials, string? v1InstallationPath, bool reuse)
    {
        this.credentials = credentials;
        this.v1InstallationPath = V1ConfigDirectory.Resolve(v1InstallationPath);
        unavailableReason = Probe();
        if (reuse) interactive = new InteractiveReadSession(Script, TimeSpan.FromSeconds(TimeoutSeconds));
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0) interactive?.Dispose();
    }

    private static string? Probe() => WindowsPowerShellProbe.UnavailableReason;

    // ---- IDirectoryGateway ----------------------------------------------------------

    public string? DiscoverDomainController(string domain)
    {
        Require(domain.Length is > 0 and <= 253, "Domaine invalide pour la découverte du contrôleur.");
        var result = Run("dc", Payload(domain, null));
        return result.TryGetProperty("hostName", out var host) && host.ValueKind == JsonValueKind.String ? host.GetString() : null;
    }

    public DirectorySearchResult SearchComputers(string domain, string? dc, string query, int limit)
    {
        Require(domain.Length is > 0 and <= 253, "Domaine invalide pour la recherche.");
        Require(query.Length is > 0 and <= 64 && !query.Any(char.IsControl), "Requête de recherche invalide.");
        Require(limit is >= 1 and <= 100, "Limite de recherche hors bornes (1 à 100).");
        var result = Run("search", Payload(domain, dc, ("Query", query), ("Limit", limit)));
        var items = new List<DirectoryComputer>();
        if (result.TryGetProperty("items", out var array) && array.ValueKind == JsonValueKind.Array)
            foreach (var item in array.EnumerateArray()) items.Add(ToComputer(item));
        var complete = result.TryGetProperty("complete", out var flag) && flag.ValueKind == JsonValueKind.True;
        return new DirectorySearchResult(items, complete);
    }

    public DirectoryComputer? FindComputer(string domain, string? dc, string name)
    {
        Require(domain.Length is > 0 and <= 253, "Domaine invalide pour l’inspection.");
        var result = Run("find", Payload(domain, dc, ("Name", name)));
        if (result.TryGetProperty("ambiguous", out var ambiguous) && ambiguous.ValueKind == JsonValueKind.True)
            throw new PestoException("directory.ambiguous", "Nom AD ambigu (CN / sAMAccountName) : aucune sélection arbitraire n’est faite. Précisez la cible auprès de l’administrateur.");
        if (!result.TryGetProperty("computer", out var computer) || computer.ValueKind is not (JsonValueKind.Null or JsonValueKind.Object))
            throw new PestoException("directory.unavailable", "La réponse AD ne confirme pas l’état du nom.");
        if (computer.ValueKind == JsonValueKind.Null) return null;
        return ToComputer(computer);
    }

    public DirectoryOrganizationalUnit? FindOrganizationalUnit(string domain, string? dc, string distinguishedName)
    {
        RequireOu(distinguishedName);
        var result = Run("ou", Payload(domain, dc, ("Ou", distinguishedName)));
        if (!result.TryGetProperty("ou", out var ou) || ou.ValueKind != JsonValueKind.Object) return null;
        if (!ou.TryGetProperty("dn", out var dn) || dn.ValueKind != JsonValueKind.String
            || !ou.TryGetProperty("guid", out var guid) || guid.ValueKind != JsonValueKind.String
            || !Guid.TryParse(guid.GetString(), out var parsed) || parsed == Guid.Empty)
            throw new PestoException("directory.unavailable", "L’OU observée n’a pas d’identité GUID exploitable.");
        return new DirectoryOrganizationalUnit(dn.GetString()!, guid.GetString()!, ou.GetProperty("name").GetString());
    }

    public IReadOnlyList<string> ListChildOuNames(string domain, string? dc, string parentOu)
    {
        Require(domain.Length is > 0 and <= 253, "Domaine invalide pour la lecture des OU.");
        RequireOu(parentOu);
        var result = Run("ous", Payload(domain, dc, ("Ou", parentOu)));
        var names = new List<string>();
        if (result.TryGetProperty("names", out var array) && array.ValueKind == JsonValueKind.Array)
            foreach (var item in array.EnumerateArray())
                if (item.ValueKind == JsonValueKind.String) names.Add(item.GetString()!);
        return names;
    }

    public SiteOuListing ReadSiteOus(string domain, string? dc, IReadOnlyList<string> explicitOus, IReadOnlyList<string> parents)
    {
        foreach (var dn in explicitOus.Concat(parents)) RequireOu(dn);
        var result = Run("sites", Payload(domain, dc, ("Explicit", explicitOus), ("Parents", parents)));
        var found = new HashSet<string>(ReadStrings(result.GetProperty("found")), StringComparer.OrdinalIgnoreCase);
        var children = new Dictionary<string, IReadOnlyList<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var group in result.GetProperty("groups").EnumerateArray())
            children.Add(group.GetProperty("parent").GetString()!, ReadStrings(group.GetProperty("children")));
        Require(found.IsSubsetOf(explicitOus) && children.Count == parents.Count && parents.All(children.ContainsKey), "Réponse OU incomplète.");
        return new(found, children);
    }

    private static string[] ReadStrings(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array || value.EnumerateArray().Any(item => item.ValueKind != JsonValueKind.String))
            throw new PestoException("directory.unavailable", "L’annuaire a renvoyé une liste illisible.");
        return value.EnumerateArray().Select(item => item.GetString()!).ToArray();
    }

    public SiteComputerNames ReadSiteComputerNames(string domain, string? dc, string ou, IReadOnlyList<string> sitePatterns, int maximum)
        => ReadSiteServices(domain, dc, ou, sitePatterns, maximum, null);

    public SiteComputerNames ReadSelectedSiteComputerNames(string domain, string? dc, SelectedSiteOu site, IReadOnlyList<string> patterns, int maximum)
        => ReadSiteServices(domain, dc, site.DistinguishedName, patterns, maximum, site);

    private SiteComputerNames ReadSiteServices(string domain, string? dc, string ou, IReadOnlyList<string> sitePatterns, int maximum, SelectedSiteOu? selectedSite)
    {
        RequireOu(ou);
        Require(maximum is >= 1 and <= 20000 && sitePatterns.Count is >= 1 and <= 3 && sitePatterns.All(pattern =>
            pattern.Length is >= 2 and <= 15 && pattern.Contains('*') && pattern.All(c => char.IsAsciiLetterOrDigit(c) || c is '*' or '-')),
            "Motifs de site invalides.");
        var result = Run("siteServices", Payload(domain, dc, ("Ou", ou), ("Patterns", sitePatterns), ("Max", maximum), ("SelectedSite", selectedSite)));
        var complete = result.GetProperty("complete").ValueKind == JsonValueKind.True;
        return new(new(ReadStrings(result.GetProperty("inOu")), complete), new(ReadStrings(result.GetProperty("withTag")), complete));
    }

    public DirectoryNameInventory ListComputerNames(string domain, string? dc, string scopeOu, int maxRows)
    {
        Require(domain.Length is > 0 and <= 253, "Domaine invalide pour l’inventaire.");
        RequireOu(scopeOu);
        Require(maxRows is >= 1 and <= 20000, "Limite d’inventaire hors bornes (1 à 20 000).");
        var result = Run("names", Payload(domain, dc, ("Ou", scopeOu), ("Max", maxRows)));
        var names = new List<string>();
        if (result.TryGetProperty("names", out var array) && array.ValueKind == JsonValueKind.Array)
            foreach (var item in array.EnumerateArray())
                if (item.ValueKind == JsonValueKind.String) names.Add(item.GetString()!);
        var complete = result.TryGetProperty("complete", out var flag) && flag.ValueKind == JsonValueKind.True;
        return new DirectoryNameInventory(names, complete);
    }

    public DirectoryNameInventory ListAutomationComputerNames(string domain, string dc, string seriesPattern, int maximum)
        => ReadSeries(domain, dc, seriesPattern, maximum, null);

    public DirectoryNameInventory ReadSelectedSiteSeries(string domain, string dc, SelectedSiteOu site, string pattern, int maximum)
        => ReadSeries(domain, dc, pattern, maximum, site);

    private DirectoryNameInventory ReadSeries(string domain, string dc, string seriesPattern, int maximum, SelectedSiteOu? selectedSite)
    {
        Require(JoinClockGuard.IsServer(dc) && dc.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase), "Contrôleur exact requis pour la série automatisée.");
        Require(seriesPattern.Length is >= 2 and <= 15 && seriesPattern.Count(c => c == '*') == 1
            && seriesPattern.All(c => char.IsAsciiLetterOrDigit(c) || c is '*' or '-'), "Série automatisée invalide.");
        Require(maximum is >= 1 and <= 20000, "Inventaire automatisé hors limites.");
        if (selectedSite is not null) RequireOu(selectedSite.DistinguishedName);
        var result = Run("automationNames", Payload(domain, dc, ("Pattern", seriesPattern), ("Max", maximum), ("SelectedSite", selectedSite)));
        if (!result.TryGetProperty("names", out var names) || names.ValueKind != JsonValueKind.Array
            || names.GetArrayLength() > maximum * 3 || names.EnumerateArray().Any(item => item.ValueKind != JsonValueKind.String))
            throw new PestoException("directory.unavailable", "L'inventaire des alias de la série est illisible.");
        return new(names.EnumerateArray().Select(item => item.GetString()!).ToArray(),
            result.TryGetProperty("complete", out var complete) && complete.ValueKind == JsonValueKind.True);
    }

    // ---- exécution bornée (port d'Invoke-PestoReadRetry) ------------------------------

    private static Dictionary<string, object?> Payload(string domain, string? dc, params (string Key, object? Value)[] extra)
    {
        Require(System.Text.RegularExpressions.Regex.IsMatch(domain, @"^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$"), "Domaine invalide pour le lecteur annuaire.");
        var payload = new Dictionary<string, object?> { ["Domain"] = domain, ["Server"] = string.IsNullOrWhiteSpace(dc) ? domain : dc!.Trim() };
        foreach (var (key, value) in extra) payload[key] = value;
        return payload;
    }

    private JsonElement Run(string op, Dictionary<string, object?> payload)
    {
        if (Volatile.Read(ref disposed) != 0) throw new PestoException("directory.unavailable", "Le lecteur annuaire de cette session est fermé.");
        if (unavailableReason is not null) throw new PestoException("directory.unavailable", unavailableReason);
        var verification = DirectoryReadEvents.Log.Measure(op, "module.verify");
        string? modulePath;
        using (verification) modulePath = TrustedActiveDirectoryModule.Resolve(v1InstallationPath);
        var request = new Dictionary<string, object?>(payload) { ["Op"] = op, ["Credential"] = credentials?.CreateProtectedPayload(), ["ModulePath"] = modulePath };
        if (verification.Enabled) request["TraceTiming"] = true;
        var json = JsonSerializer.Serialize(request);
        PestoException last = new("directory.unavailable", "Aucune lecture n’a abouti.");
        for (var attempt = 1; attempt <= ReadAttempts; attempt++)
        {
            try
            {
                return ExecuteOnce(json, op, modulePath);
            }
            catch (PestoException error) when (error.Code == "directory.transient" && attempt < ReadAttempts)
            {
                last = error;
                Thread.Sleep(Math.Min(4000, 200 * (1 << (attempt - 1))));
            }
        }
        throw last;
    }

    private JsonElement ExecuteOnce(string requestJson, string op, string? modulePath)
    {
        using var timing = DirectoryReadEvents.Log.Measure(op, "worker.roundTrip");
        try
        {
            // Exact computer/OU identity and exclusion guards keep a dedicated worker, even on the GUI gateway.
            if (interactive is not null && (op is "dc" or "sites" or "siteServices" or "automationNames" or "search" or "names" or "ous"))
                return ParseReply(interactive.Execute(requestJson, modulePath), op);
            var start = PowerShellFixedWorker.StartInfo(Script);
            start.FileName = PowerShellPath;
            using var process = Process.Start(start) ?? throw new PestoException("directory.unavailable", "Le moteur Windows PowerShell n’a pas pu être lancé.");
            using var job = OwnedMutationJob.Attach(process);
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            PowerShellFixedWorker.Send(process, Script, requestJson);
            if (!process.WaitForExit(TimeoutSeconds * 1000))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { /* le processus vient de finir */ }
                throw new PestoException("directory.transient", $"Lecture annuaire interrompue après {TimeoutSeconds} s : aucun résultat partiel n’est publié. Relancez la lecture.");
            }
            var stdout = stdoutTask.GetAwaiter().GetResult();
            stderrTask.GetAwaiter().GetResult();
            if (Encoding.UTF8.GetByteCount(stdout) > MaximumResponseBytes)
                throw new PestoException("directory.unavailable", "Réponse du lecteur annuaire trop volumineuse : la lecture est refusée plutôt que tronquée.");
            return ParseReply(stdout, op);
        }
        catch (JsonException)
        {
            throw new PestoException("directory.unavailable", "Réponse du lecteur annuaire illisible : aucun résultat n’est publié.");
        }
        catch (System.ComponentModel.Win32Exception error)
        {
            throw new PestoException("directory.unavailable", "Le moteur Windows PowerShell n’a pas pu être lancé : " + error.Message);
        }
    }

    private static JsonElement ParseReply(string stdout, string operation)
    {
        using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(stdout) ? "{}" : stdout);
        var root = document.RootElement;
        if (DirectoryReadEvents.Log.IsEnabled() && root.ValueKind == JsonValueKind.Object &&
            root.TryGetProperty("timing", out var native) && native.ValueKind == JsonValueKind.Object)
        {
            foreach (var phase in new[] { "ps.moduleImport", "ps.selectedOu", "ps.query" })
                if (native.TryGetProperty(phase, out var value) && value.ValueKind == JsonValueKind.Number &&
                    value.TryGetInt64(out var ms) && ms >= 0) DirectoryReadEvents.Log.Duration(operation, phase, ms);
        }
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True
            && root.TryGetProperty("result", out var result)) return result.Clone();
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("ok", out var failed) && failed.ValueKind == JsonValueKind.False)
            throw MapFailure(root);
        throw new PestoException("directory.unavailable", "Réponse du lecteur annuaire illisible : aucun résultat n’est publié.");
    }

    /// <summary>Port de Get-PestoReadFailure / Get-PestoNativeGuidance : catégories et conduite, sans reprise automatique hors réseau transitoire.</summary>
    private static PestoException MapFailure(JsonElement root)
    {
        var message = root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString()!.Trim() : "";
        if (message.Length > 400) message = message[..400];
        var kind = root.TryGetProperty("kind", out var k) && k.ValueKind == JsonValueKind.String ? k.GetString() : "error";
        if (kind == "module")
            return new PestoException("directory.unavailable", "Le module ActiveDirectory livré avec Pesto est absent ou inutilisable : vérifiez l’intégrité du pack courant, puis rétablissez-le depuis son archive complète. " + message);
        int? code = root.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.Number && c.TryGetInt32(out var parsed) ? parsed : null;
        var detail = message.Length == 0 ? "Détail non fourni par le lecteur." : message;
        if (code is 5 or 1326 or 1385)
            return new PestoException("directory.access", "Accès refusé par l’annuaire. Vérifiez la délégation du compte de session pour cette lecture ; pas de nouvel essai automatique. " + detail);
        if (code is 53 or 64 or 121 or 1460 or 1722 or 1726)
            return new PestoException("directory.transient", "Panne réseau transitoire vers l’annuaire (reprise bornée épuisée). Vérifiez DNS et le transport ; aucun service n’est modifié. " + detail);
        if (code == 1355)
            return new PestoException("directory.discovery", "Domaine ou contrôleur introuvable. Vérifiez DNS et la découverte du contrôleur. " + detail);
        var guidance = code is null ? "Aucune réparation automatique." : $"Code natif {code}. Aucune réparation automatique.";
        return new PestoException("directory.unavailable", "Lecture annuaire refusée. " + guidance + " " + detail);
    }

    private static DirectoryComputer ToComputer(JsonElement item)
    {
        string? Text(string name) => item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        var name = Text("name") ?? throw new PestoException("directory.unavailable", "Objet annuaire sans nom observé : la lecture est refusée.");
        return new DirectoryComputer(name, Text("dnsName"), Text("ou"), Text("os"), Text("guid"), Text("domain"), null, null, null, null, null);
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new PestoException("invalid_arguments", message);
    }

    private static void RequireOu(string ou)
    {
        Require(ou.Length is > 0 and <= 2048 && !ou.Any(char.IsControl), "SearchBase d’OU invalide.");
    }

    // ---- script constant, lecture seule uniquement -------------------------------------

    public static string ConstantScript => Script;
    private static readonly string Script = GroupExclusionScript.Source + """
$ErrorActionPreference='Stop'
try{
  $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
  function Get-NativeCode($e){
    $x=$e.Exception
    for($i=0;$i -lt 4 -and $x;$i++){
      try{ if($x.PSObject.Properties['ErrorCode'] -and $null -ne $x.ErrorCode){ return [int]$x.ErrorCode } }catch{}
      $x=$x.InnerException
    }
    return $null
  }
  function ConvertTo-LdapLiteral([string]$s){
    $out=New-Object Text.StringBuilder
    foreach($c in $s.ToCharArray()){
      switch($c){
        '(' {[void]$out.Append('\28')}
        ')' {[void]$out.Append('\29')}
        '\' {[void]$out.Append('\5c')}
        ([char]0) {[void]$out.Append('\00')}
        '*' {[void]$out.Append('\2a')}
        default {[void]$out.Append($c)}
      }
    }
    $out.ToString()
  }
  function Get-ParentDn([string]$dn){
    for($i=0;$i -lt $dn.Length;$i++){
      $c=$dn[$i]
      if($c -eq '\'){$i++;continue}
      if($c -eq ','){ return $dn.Substring($i+1) }
    }
    throw 'Objet sans parent dans le DN.'
  }
  function Get-DomainFromDn([string]$dn){
    $labels=@()
    foreach($part in ($dn -split '(?<!\\),')){ if($part -match '(?i)^DC='){ $labels+=($part -replace '(?i)^DC=','') } }
    ($labels -join '.').ToLowerInvariant()
  }
  function Get-ComputerNode($pc){
    $dns=[string]$pc.DnsHostName
    $os=[string]$pc.OperatingSystem
    $guid=try{[string]$pc.ObjectGUID}catch{$null}
    [pscustomobject]@{
      name=[string]$pc.Name
      dnsName=$(if($dns){$dns}else{$null})
      ou=$(Get-ParentDn ([string]$pc.DistinguishedName))
      os=$(if($os){$os}else{$null})
      guid=$(if($guid){$guid}else{$null})
      domain=$(Get-DomainFromDn ([string]$pc.DistinguishedName))
    }
  }
  $timer=if($j.PSObject.Properties['TraceTiming'] -and $j.TraceTiming -eq $true){ [Diagnostics.Stopwatch]::StartNew() }
  $env:ADPS_LoadDefaultDrive='0' # All reads select the server explicitly; initializing AD: adds an unrelated DC lookup.
  if($j.ModulePath){ Import-Module -Name ([string]$j.ModulePath) -ErrorAction Stop }
  else{ throw 'Module ActiveDirectory Microsoft embarqué absent : vérifiez puis rétablissez le pack Pesto courant depuis son archive complète.' }
  if($timer){ $importMs=$timer.ElapsedMilliseconds }
  $adp=@{ Server=[string]$j.Server }
  if($null -ne $j.Credential){
    $bytes=$null;$secure=$null
    try{
      Add-Type -AssemblyName System.Security
      $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.Credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
      $secure=New-Object Security.SecureString
      for($i=0;$i -lt $bytes.Length;$i+=2){ $secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8))) }
      $secure.MakeReadOnly()
      $adp.Credential=New-Object Management.Automation.PSCredential([string]$j.Credential.userName,$secure)
    }catch{ throw 'Compte AD explicite indisponible pour cette session Windows.' }
    finally{ if($bytes){[Array]::Clear($bytes,0,$bytes.Length)} }
  }
  if($timer){ $beforeOu=$timer.ElapsedMilliseconds }
  if($null -ne $j.SelectedSite){
    $selectedDn=[string]$j.SelectedSite.DistinguishedName
    if($j.Op -notin @('siteServices','automationNames') -or !$selectedDn -or $selectedDn.Length -gt 2048 -or $selectedDn -match '[\x00-\x1f]' -or
       ($j.Op -eq 'siteServices' -and ![StringComparer]::OrdinalIgnoreCase.Equals($selectedDn,[string]$j.Ou))){throw 'Identite OU invalide.'}
    $observed=Get-ADOrganizationalUnit -Identity $selectedDn -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp
    $guid=[Guid]::Empty
    if(![StringComparer]::OrdinalIgnoreCase.Equals([string]$observed.DistinguishedName,$selectedDn) -or
       ![Guid]::TryParse([string]$observed.ObjectGUID,[ref]$guid) -or $guid -eq [Guid]::Empty -or
       ($null -ne $j.SelectedSite.ExpectedName -and ![StringComparer]::OrdinalIgnoreCase.Equals([string]$observed.Name,[string]$j.SelectedSite.ExpectedName))){
      throw 'L''OU selectionnee n''est plus confirmee par l''annuaire.'
    }
  }
  if($timer){ $beforeQuery=$timer.ElapsedMilliseconds }
  $result=$null
  switch([string]$j.Op){
    'groups'{
      $result=Get-PestoGroupExclusionObservation ([string]$j.ComputerGuid) @($j.ExcludedGroupGuids) $adp
    }
    'dc'{
      $found=@(Get-ADDomainController -Discover -Service ADWS -DomainName ([string]$j.Domain) -ForceDiscover -ErrorAction Stop)
      if($found.Count -ne 1 -or -not $found[0].HostName){ throw 'Aucun contrôleur inscriptible ADWS confirmé.' }
      $result=[pscustomobject]@{ hostName=([string]$found[0].HostName).TrimEnd('.') }
    }
    'search'{
      $q=[string]$j.Query
      if(-not $q -or $q.Length -gt 64 -or $q -match '[\x00-\x1f]'){ throw 'Requête de recherche invalide.' }
      $lit=ConvertTo-LdapLiteral $q
      $ldap='(|(name=*'+$lit+'*)(dNSHostName=*'+$lit+'*))'
      $rows=@(Get-ADComputer -LDAPFilter $ldap -Properties DistinguishedName,OperatingSystem,DnsHostName,ObjectGUID -ResultSetSize ([int]$j.Limit+1) -ResultPageSize 500 -ErrorAction Stop @adp)
      $complete=$rows.Count -le [int]$j.Limit
      $items=@($rows|Select-Object -First ([int]$j.Limit)|ForEach-Object{ Get-ComputerNode $_ })
      $result=[pscustomobject]@{ items=$items; complete=$complete }
    }
    'find'{
      $n=[string]$j.Name
      if($n -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$'){ throw ('Nom d''ordinateur invalide : '+$n) }
      $ldap='(|(name='+$n+')(sAMAccountName='+$n+'$)(dNSHostName='+$n+'.*))'
      $found=@(Get-ADComputer -LDAPFilter $ldap -Properties DistinguishedName,OperatingSystem,DnsHostName,ObjectGUID -ResultSetSize 2 -ErrorAction Stop @adp)
      if($found.Count -gt 1){ $result=[pscustomobject]@{ ambiguous=$true } }
      elseif($found.Count -eq 1){ $result=[pscustomobject]@{ computer=(Get-ComputerNode $found[0]) } }
      else{ $result=[pscustomobject]@{ computer=$null } }
    }
    'ou'{
      $ou=[string]$j.Ou
      if(-not $ou -or $ou.Length -gt 2048 -or $ou -match '[\x00-\x1f]'){ throw 'Identité OU invalide.' }
      $found=Get-ADOrganizationalUnit -Identity $ou -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp
      $result=[pscustomobject]@{ ou=[pscustomobject]@{ dn=[string]$found.DistinguishedName; guid=[string]$found.ObjectGUID; name=[string]$found.Name } }
    }
    'ous'{
      $ou=[string]$j.Ou
      if(-not $ou -or $ou.Length -gt 2048 -or $ou -match '[\x00-\x1f]'){ throw 'SearchBase d''OU invalide.' }
      $names=@(Get-ADOrganizationalUnit -SearchBase $ou -SearchScope OneLevel -Filter * -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name}|Sort-Object -Unique)
      $result=[pscustomobject]@{ names=$names }
    }
    'sites'{
      $domainRoot=(@(([string]$j.Domain)-split '\.'|ForEach-Object{'DC='+$_}) -join ',')
      $requested=@($j.Explicit);$found=@()
      for($start=0;$start -lt $requested.Count;$start+=64){
        $last=[Math]::Min($start+63,$requested.Count-1)
        $clauses=@($requested[$start..$last]|ForEach-Object{'(distinguishedName='+(ConvertTo-LdapLiteral ([string]$_))+')'})
        $found+=@(Get-ADOrganizationalUnit -SearchBase $domainRoot -LDAPFilter ('(|'+($clauses -join '')+')') -ResultSetSize ($clauses.Count+1) -ErrorAction Stop @adp|ForEach-Object{[string]$_.DistinguishedName})
      }
      $groups=@(foreach($parent in $j.Parents){
        $children=@(Get-ADOrganizationalUnit -SearchBase $parent -SearchScope OneLevel -Filter * -ResultPageSize 500 -ResultSetSize 20001 -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name})
        if($children.Count -gt 20000){throw 'Lecture des OU du site incomplète.'}
        [pscustomobject]@{parent=[string]$parent;children=@($children|Sort-Object -Unique)}
      })
      $result=[pscustomobject]@{found=$found;groups=$groups}
    }
    'siteServices'{
      $domainRoot=(@(([string]$j.Domain)-split '\.'|ForEach-Object{'DC='+$_}) -join ',')
      $max=[int]$j.Max
      $clauses=@(foreach($pattern in $j.Patterns){
        if($pattern.Length -lt 6 -or -not $pattern.EndsWith('*') -or $pattern.Substring(0,$pattern.Length-1).Contains('*') -or
           $pattern.Substring($pattern.Length-3,2) -notmatch '^[A-Za-z0-9]{2}$'){throw 'Motif de recherche invalide.'}
        '(name='+$pattern+')'
      })
      # Le tag de site occupe deux caractères avant l'astérisque. Dans l'OU,
      # chercher le préfixe d'organisme (sans le tag) évite de lire tous les PC
      # et conserve les noms Pesto mal rangés dans la mauvaise OU de site.
      $scopeClauses=@(foreach($pattern in $j.Patterns){
        $scopePattern=$pattern.Substring(0,$pattern.Length-3)+'*'
        '(name='+$scopePattern+')'
      })
      $inOu=@(Get-ADComputer -SearchBase $j.Ou -SearchScope Subtree -LDAPFilter ('(|'+($scopeClauses -join '')+')') -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name})
      $withTag=@(Get-ADComputer -SearchBase $domainRoot -SearchScope Subtree -LDAPFilter ('(|'+($clauses -join '')+')') -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name})
      $result=[pscustomobject]@{inOu=$inOu;withTag=$withTag;complete=($inOu.Count -le $max -and $withTag.Count -le $max)}
    }
    'automationNames'{
      $pattern=[string]$j.Pattern;$max=[int]$j.Max
      if($pattern.Length -lt 2 -or $pattern.Length -gt 15 -or $pattern -notmatch '^[A-Za-z0-9-]*\*[A-Za-z0-9-]*$' -or $max -lt 1 -or $max -gt 20000){throw 'Serie automatisee invalide.'}
      $root=(@(([string]$j.Domain)-split '\.'|ForEach-Object{'DC='+$_}) -join ',')
      $ldap='(|(name='+$pattern+')(sAMAccountName='+$pattern+'$)(dNSHostName='+$pattern+'.*))'
      $rows=@(Get-ADComputer -LDAPFilter $ldap -SearchBase $root -SearchScope Subtree -Properties SamAccountName,DNSHostName -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp)
      $complete=$rows.Count -le $max
      $names=@($rows|Select-Object -First $max|ForEach-Object{[string]$_.Name;([string]$_.SamAccountName).TrimEnd('$');(([string]$_.DNSHostName)-split '\.')[0]}|Where-Object{$_}|Sort-Object -Unique)
      $result=[pscustomobject]@{ names=$names; complete=$complete }
    }
    'names'{
      $ou=[string]$j.Ou
      if(-not $ou -or $ou.Length -gt 2048 -or $ou -match '[\x00-\x1f]'){ throw 'SearchBase d''OU invalide.' }
      $max=[int]$j.Max
      $rows=@(Get-ADComputer -Filter * -SearchBase $ou -SearchScope Subtree -Properties DistinguishedName -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp)
      $complete=$rows.Count -le $max
      $names=@($rows|Select-Object -First $max|ForEach-Object{[string]$_.Name})
      $result=[pscustomobject]@{ names=$names; complete=$complete }
    }
    default{ throw 'Opération de lecture non déclarée.' }
  }
  $reply=@{ ok=$true; result=$result }
  if($timer){
    $reply.timing=@{'ps.moduleImport'=$importMs; 'ps.selectedOu'=($beforeQuery-$beforeOu); 'ps.query'=($timer.ElapsedMilliseconds-$beforeQuery)}
  }
  $reply|ConvertTo-Json -Depth 6 -Compress
}catch{
  $code=Get-NativeCode $_
  $kind='error'
  if([string]$_.FullyQualifiedErrorId -match 'CommandNotFoundException'){ $kind='module' }
  @{ ok=$false; kind=$kind; code=$code; message=([string]$_.Exception.Message) }|ConvertTo-Json -Depth 3 -Compress
}finally{
  if($secure){$secure.Dispose()}
}
""";
}
){throw 'Motif de recherche invalide.'}
        '(name='+$pattern+')'
      })
      # Le tag de site occupe deux caractères avant l'astérisque. Dans l'OU,
      # chercher le préfixe d'organisme (sans le tag) évite de lire tous les PC
      # et conserve les noms Pesto mal rangés dans la mauvaise OU de site.
      $scopeClauses=@(foreach($pattern in $j.Patterns){
        $scopePattern=$pattern.Substring(0,$pattern.Length-3)+'*'
        '(name='+$scopePattern+')'
      })
      $inOu=@(Get-ADComputer -SearchBase $j.Ou -SearchScope Subtree -LDAPFilter ('(|'+($scopeClauses -join '')+')') -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name})
      $withTag=@(Get-ADComputer -SearchBase $domainRoot -SearchScope Subtree -LDAPFilter ('(|'+($clauses -join '')+')') -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp|ForEach-Object{[string]$_.Name})
      $result=[pscustomobject]@{inOu=$inOu;withTag=$withTag;complete=($inOu.Count -le $max -and $withTag.Count -le $max)}
    }
    'automationNames'{
      $pattern=[string]$j.Pattern;$max=[int]$j.Max
      if($pattern.Length -lt 2 -or $pattern.Length -gt 15 -or $pattern -notmatch '^[A-Za-z0-9-]*\*[A-Za-z0-9-]*$' -or $max -lt 1 -or $max -gt 20000){throw 'Serie automatisee invalide.'}
      $root=(@(([string]$j.Domain)-split '\.'|ForEach-Object{'DC='+$_}) -join ',')
      $ldap='(|(name='+$pattern+')(sAMAccountName='+$pattern+'$)(dNSHostName='+$pattern+'.*))'
      $rows=@(Get-ADComputer -LDAPFilter $ldap -SearchBase $root -SearchScope Subtree -Properties SamAccountName,DNSHostName -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp)
      $complete=$rows.Count -le $max
      $names=@($rows|Select-Object -First $max|ForEach-Object{[string]$_.Name;([string]$_.SamAccountName).TrimEnd('$');(([string]$_.DNSHostName)-split '\.')[0]}|Where-Object{$_}|Sort-Object -Unique)
      $result=[pscustomobject]@{ names=$names; complete=$complete }
    }
    'names'{
      $ou=[string]$j.Ou
      if(-not $ou -or $ou.Length -gt 2048 -or $ou -match '[\x00-\x1f]'){ throw 'SearchBase d''OU invalide.' }
      $max=[int]$j.Max
      $rows=@(Get-ADComputer -Filter * -SearchBase $ou -SearchScope Subtree -Properties DistinguishedName -ResultPageSize 500 -ResultSetSize ($max+1) -ErrorAction Stop @adp)
      $complete=$rows.Count -le $max
      $names=@($rows|Select-Object -First $max|ForEach-Object{[string]$_.Name})
      $result=[pscustomobject]@{ names=$names; complete=$complete }
    }
    default{ throw 'Opération de lecture non déclarée.' }
  }
  $reply=@{ ok=$true; result=$result }
  if($timer){
    $reply.timing=@{'ps.moduleImport'=$importMs; 'ps.selectedOu'=($beforeQuery-$beforeOu); 'ps.query'=($timer.ElapsedMilliseconds-$beforeQuery)}
  }
  $reply|ConvertTo-Json -Depth 6 -Compress
}catch{
  $code=Get-NativeCode $_
  $kind='error'
  if([string]$_.FullyQualifiedErrorId -match 'CommandNotFoundException'){ $kind='module' }
  @{ ok=$false; kind=$kind; code=$code; message=([string]$_.Exception.Message) }|ConvertTo-Json -Depth 3 -Compress
}finally{
  if($secure){$secure.Dispose()}
}
""";
}
