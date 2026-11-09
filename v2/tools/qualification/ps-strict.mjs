// Helper COMMUN de sérialisation des preuves invitées — correction SERIALIZATION_REVIEW_REQUIRED.md
// (24/10/2026 21:31 UTC). Le gel observé (PID 4740, 2681 Mo, ~20 min) venait de `$result | ConvertTo-Json -Depth 10`
// appliqué à un objet enrichi par le provider : `Get-Content -Raw` renvoie un System.String porteur des propriétés
// ETS PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/ReadCount/Length. ConvertTo-Json -Depth >= 10 descend alors
// dans PSDrive (DriveInfo) et PSProvider (ProviderInfo -> Provider -> DriveCollection -> ...) et part en explosion.
//
// Règle appliquée ici, unique pour TOUS les pilotes (diagnostics, deploy, smoke) :
//  - la sérialisation n'accepte QUE des primitives, des tableaux et des dictionnaires de données ;
//  - tout objet .NET non reconnu (DriveInfo, ProviderInfo, Process, FileInfo, X509Certificate2, ...) est rendu par la
//    balise "[PESTO_NON_DATA_TYPE:<type>]" au lieu d'être parcouru : plus AUCUNE exploration de graphe d'objets ;
//  - un objet étendu est d'abord décalé sur son PSObject.BaseObject, donc les propriétés ETS ne sont jamais énumérées ;
//  - les fichiers sont lus en texte pur côté .NET (Get-PlainText) : aucun objet enrichi n'est jamais produit ;
//  - garde d'exécution : borne temps 180 s et borne mémoire 512 Mo sur le PID invité lui-même, plus auto-enregistrement
//    du PID (identité création/owner/script) pour une annulation ciblée par le pilote qui l'a lancé.
// Aucun cast [string] isolé ne sert de preuve : c'est la PORTE D'ENTRÉE DE TYPE qui interdit l'expansion.
//
// Le helper est livré comme FICHIER à adresse de contenu sur l'invité (une seule source de vérité, dot-sourcé par
// chaque script) : l'inliner dans l'EncodedCommand ferait dépasser la limite de ~8191 caractères de la ligne de
// commande cmd.exe de l'hôte, ce qui faisait échouer silencieusement les appels courts.
import { createHash } from 'node:crypto';

export const GUARD_MAX_SEC = 180;
export const GUARD_MAX_MB = 512;
export const MAX_JSON_CHARS = 4 * 1024 * 1024;

export const HELPER_PS = `# Pesto v2 — helper COMMUN de sérialisation des preuves (source : v2/tools/qualification/ps-strict.mjs).
# Ne pas éditer sur l'invité : le nom du fichier porte le sha256 du contenu, il est redéposé par le pilote.
$ProgressPreference='SilentlyContinue'
$VerbosePreference='SilentlyContinue'
$WarningPreference='SilentlyContinue'
if (-not $script:PestoGuardSw) { $script:PestoGuardSw=[System.Diagnostics.Stopwatch]::StartNew() }
if (-not $script:PestoGuardMaxSec) { $script:PestoGuardMaxSec=180 }
if (-not $script:PestoGuardMaxMB) { $script:PestoGuardMaxMB=512 }
$script:PestoMaxJsonChars=${MAX_JSON_CHARS}
function Get-PestoBase {
  param($Value)
  # N'appeler .GetType() QUE sur un scalaire : sur une collection d'un seul element, l'enumeration de membres
  # PowerShell detourne GetType vers l'element (@('x').GetType() renvoie System.String, @().GetType() renvoie null).
  # Bug reel confirme sur l'invite : un tableau d'un seul element etait serialise en son element.
  if ($null -eq $Value) { return $null }
  if ($Value -is [System.Array]) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) { return $Value }
  if ($Value -is [System.Management.Automation.PSCustomObject]) { return $Value }
  if ($Value -is [System.Collections.IEnumerable]) { return $Value }
  $b=$Value.PSObject.BaseObject
  if ($null -ne $b) { return $b }
  return $Value
}
function ConvertTo-PestoJsonString {
  param([string]$S)
  if ($null -eq $S) { return 'null' }
  $bs=[char]92
  $sb=New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($ch in $S.ToCharArray()) {
    $c=[int]$ch
    if ($ch -eq '"') { [void]$sb.Append($bs); [void]$sb.Append('"') }
    elseif ($c -eq 92) { [void]$sb.Append($bs); [void]$sb.Append($bs) }
    elseif ($c -eq 8) { [void]$sb.Append($bs); [void]$sb.Append('b') }
    elseif ($c -eq 12) { [void]$sb.Append($bs); [void]$sb.Append('f') }
    elseif ($c -eq 10) { [void]$sb.Append($bs); [void]$sb.Append('n') }
    elseif ($c -eq 13) { [void]$sb.Append($bs); [void]$sb.Append('r') }
    elseif ($c -eq 9) { [void]$sb.Append($bs); [void]$sb.Append('t') }
    elseif ($c -lt 32) { [void]$sb.Append($bs); [void]$sb.Append('u'); [void]$sb.Append(('{0:x4}' -f $c)) }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}
function ConvertTo-PestoJson {
  param($Value,[int]$Depth=0)
  if ($Depth -gt 6) { return '"[PESTO_MAX_DEPTH]"' }
  if ($null -eq $Value) { return 'null' }
  # Les tests de CONTENEURS se font uniquement par -is : .GetType() sur une collection d'un seul element est
  # detourne par l'enumeration de membres PowerShell (voir Get-PestoBase).
  if ($Value -is [string]) { return (ConvertTo-PestoJsonString $Value) }
  if ($Value -is [System.Collections.IDictionary]) {
    $parts=@()
    foreach ($k in $Value.Keys) {
      if ($null -eq $k) { continue }
      $parts += ((ConvertTo-PestoJsonString ([string]$k)) + ':' + (ConvertTo-PestoJson $Value[$k] ($Depth+1)))
    }
    return '{' + ($parts -join ',') + '}'
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $parts=@()
    foreach ($p in $Value.PSObject.Properties) {
      if ($p.MemberType -ne 'NoteProperty') { continue }
      $parts += ((ConvertTo-PestoJsonString $p.Name) + ':' + (ConvertTo-PestoJson $p.Value ($Depth+1)))
    }
    return '{' + ($parts -join ',') + '}'
  }
  if (($Value -is [System.Array]) -or (($Value -is [System.Collections.IEnumerable]) -and ($Value -isnot [string]))) {
    $parts=@()
    foreach ($x in $Value) { $parts += (ConvertTo-PestoJson $x ($Depth+1)) }
    return '[' + ($parts -join ',') + ']'
  }
  $v=Get-PestoBase $Value
  if ($null -eq $v) { return 'null' }
  if ($v -is [bool]) { if ($v) { return 'true' } return 'false' }
  if ($v -is [byte] -or $v -is [sbyte] -or $v -is [int16] -or $v -is [uint16] -or $v -is [int32] -or $v -is [uint32] -or $v -is [int64] -or $v -is [uint64]) { return [string]$v }
  if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) {
    $d=[double]$v
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return (ConvertTo-PestoJsonString ([string]$v)) }
    return $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
  }
  if ($v -is [datetime]) { return (ConvertTo-PestoJsonString ($v.ToString('o',[System.Globalization.CultureInfo]::InvariantCulture))) }
  if ($v -is [datetimeoffset] -or $v -is [timespan] -or $v -is [guid] -or $v -is [uri] -or $v -is [char]) {
    return (ConvertTo-PestoJsonString ($v.ToString([System.Globalization.CultureInfo]::InvariantCulture)))
  }
  if ($v -is [System.Enum]) { return (ConvertTo-PestoJsonString ([string]$v)) }
  # Rien de reconnu : simple balise. AUCUNE exploration du graphe d'objets n'est possible (cause exacte du gel du
  # PID 4740 : ConvertTo-Json -Depth 10 descendant dans PSDrive/PSProvider du texte enrichi par le provider).
  $tn=[string]$v.GetType().FullName
  return (ConvertTo-PestoJsonString ('[PESTO_NON_DATA_TYPE:' + $tn + ']'))
}
function Get-PlainText {
  param([string]$Path)
  # Lecture .NET directe : le provider PowerShell n'est pas impliqué, donc AUCUN objet enrichi
  # (PSPath/PSParentPath/PSChildName/PSDrive/PSProvider/ReadCount/Length) n'est attaché au texte.
  $bytes=[System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return [System.Text.Encoding]::UTF8.GetString($bytes,3,($bytes.Length-3))
  }
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    return [System.Text.Encoding]::Unicode.GetString($bytes,2,($bytes.Length-2))
  }
  return [System.Text.Encoding]::UTF8.GetString($bytes)
}
function Get-PestoGuard {
  $mb=0.0
  try { $mb=((Get-Process -Id $PID).WorkingSet64/1MB) } catch { $mb=0.0 }
  return [ordered]@{ ElapsedMs=[int]$script:PestoGuardSw.ElapsedMilliseconds; WS_MB=[math]::Round($mb,1);
    Pid=[int]$PID; MaxSec=[int]$script:PestoGuardMaxSec; MaxMB=[int]$script:PestoGuardMaxMB }
}
function Assert-PestoGuard {
  $el=$script:PestoGuardSw.Elapsed.TotalSeconds
  if ($el -gt $script:PestoGuardMaxSec) { throw ('PESTO_GUARD_TEMPS_DEPASSE ' + [int]$el + 's') }
  $mb=0.0
  try { $mb=((Get-Process -Id $PID).WorkingSet64/1MB) } catch { $mb=0.0 }
  if ($mb -gt $script:PestoGuardMaxMB) { throw ('PESTO_GUARD_MEMOIRE_DEPASSEE ' + [int]$mb + 'MB') }
}
function Write-PestoSelf {
  if (-not $script:PestoSelfPath) { return }
  try {
    $wp=Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue
    $own=''
    try { $own=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch {}
    $cl=[string]$wp.CommandLine
    if ($cl.Length -gt 200) { $cl=$cl.Substring($cl.Length-200) }
    $self=[ordered]@{ Name=[string]$script:PestoEvidenceName; Pid=[int]$PID; ProcessName=[string]$wp.Name; Owner=$own;
      CreationDate=[string]$wp.CreationDate; CommandLineTail=($cl -replace '[\\x00-\\x1f]','?');
      ScriptPath=[string]$script:PestoScriptPath; StartedUtc=(Get-Date).ToUniversalTime().ToString('o') }
    $dir=Split-Path -Parent $script:PestoSelfPath
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($script:PestoSelfPath,(ConvertTo-PestoJson $self),(New-Object System.Text.UTF8Encoding($false)))
  } catch {}
}
function Write-PestoResult {
  param($Result,[string]$Path)
  $dir=Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $json=ConvertTo-PestoJson $Result
  if ($json.Length -gt $script:PestoMaxJsonChars) {
    $json=ConvertTo-PestoJson ([ordered]@{ Status='RESULT_TROP_GRAND'; Chars=$json.Length; Guard=(Get-PestoGuard) })
  }
  [System.IO.File]::WriteAllText($Path,$json,(New-Object System.Text.UTF8Encoding($false)))
  return $json.Length
}
`;

/// Octets exactement tels qu'ils sont déposés (BOM UTF-8 compris, indispensable pour que PowerShell 5.1 lise les
/// accents des commentaires) et nom à adresse de contenu : le nom du fichier invité EST le sha256 du fichier déposé,
/// donc `Get-FileHash` sur l'invité se compare directement au nom. Un helper modifié est automatiquement un nouveau
/// fichier : aucun script ne peut reposer sur un helper périmé.
export const HELPER_BYTES = '\uFEFF' + HELPER_PS;

export function helperFileName() {
  return 'pesto-strict-' + createHash('sha256').update(HELPER_BYTES, 'utf8').digest('hex').slice(0, 12) + '.ps1';
}

/// En-tête léger placé avant le corps de chaque script invité : règle les variables de garde puis DOT-SOURCE le
/// helper (transféré par lab-driver.ensureHelper) et enregistre l'identité du processus pour l'annulation ciblée.
export function strictPrelude({ name = null, selfPath = null, maxSec = GUARD_MAX_SEC, maxMb = GUARD_MAX_MB, helperPath } = {}) {
  if (!helperPath) throw new Error('strictPrelude exige helperPath (fichier helper déposé sur l\'invité)');
  const q = (s) => (s === null || s === undefined ? '$null' : "'" + String(s).replace(/'/g, "''") + "'");
  return `$ErrorActionPreference='Stop'
$script:PestoEvidenceName=${q(name)}
$script:PestoSelfPath=${q(selfPath)}
$script:PestoGuardMaxSec=${Math.trunc(maxSec)}
$script:PestoGuardMaxMB=${Math.trunc(maxMb)}
$script:PestoScriptPath=[string]$MyInvocation.MyCommand.Path
. '${helperPath}'
if (-not (Test-Path -LiteralPath '${helperPath}')) { throw 'HELPER_ABSENT' }
Write-PestoSelf
`;
}

/// Clôture commune : ajoute le garde au dictionnaire $result puis écrit la preuve en JSON STRICT.
export function resultTail(guestPath) {
  return `$__pestoResult=$result
if ($null -eq $__pestoResult) { $__pestoResult=[ordered]@{ Status='NO_RESULT' } }
if ($__pestoResult -is [System.Collections.IDictionary]) { $__pestoResult['Guard']=(Get-PestoGuard) }
$__pestoLen=Write-PestoResult -Result $__pestoResult -Path '${guestPath}'
Write-Output ('WROTE ' + $__pestoLen)
`;
}

/// Script invité d'annulation ciblée : n'arrête QUE le processus que ce pilote a lui-même enregistré,
/// après contrôle d'identité complet (PID enregistré, nom du processus, date de création, owner, script).
/// Aucun arrêt global, aucun arrêt d'un processus non enregistré par ce pilote.
export function cancelScript({ selfPath, name }) {
  return `$result=[ordered]@{ Status='REFUSED'; Reason='self absent'; Name='${name}'; TargetPid=$null;
  TargetName=$null; TargetCreation=$null; Owner=$null }
if (Test-Path -LiteralPath '${selfPath}') {
  $self=ConvertFrom-Json (Get-PlainText '${selfPath}')
  $result.Name=[string]$self.Name
  $result.TargetPid=[int]$self.Pid
  $result.TargetName=[string]$self.ProcessName
  $result.TargetCreation=[string]$self.CreationDate
  try { $result.Owner=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch {}
  if ([int]$self.Pid -le 0 -or [int]$self.Pid -eq $PID) {
    $result.Status='REFUSED'; $result.Reason='PID invalide ou auto-cible'
  } else {
    $wp=Get-CimInstance Win32_Process -Filter "ProcessId=$($self.Pid)" -ErrorAction SilentlyContinue
    if (-not $wp) {
      $result.Status='ALREADY_GONE'; $result.Reason='pid enregistre deja termine'
    } elseif ([string]$wp.Name -ne [string]$self.ProcessName) {
      $result.Status='REFUSED'; $result.Reason='nom de processus different'; $result.Found=[string]$wp.Name
    } elseif ([string]$wp.CreationDate -ne [string]$self.CreationDate) {
      $result.Status='REFUSED'; $result.Reason='date de creation differente'; $result.Found=[string]$wp.CreationDate
    } elseif ($self.ScriptPath -and ([string]$wp.CommandLine -notlike ('*' + [string]$self.ScriptPath + '*'))) {
      $result.Status='REFUSED'; $result.Reason='script different'
    } else {
      $own=''
      try { $own=[string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch {}
      if ($self.Owner -and $own -and ($own -ne [string]$self.Owner)) {
        $result.Status='REFUSED'; $result.Reason='owner different'
      } else {
        Stop-Process -Id ([int]$self.Pid) -Force
        Start-Sleep -Milliseconds 500
        $result.Reason='identite verifiee, arret du pid enregistre par ce pilote'
        $result.Status=if (Get-Process -Id ([int]$self.Pid) -ErrorAction SilentlyContinue) { 'STOP_FAILED' } else { 'STOPPED' }
      }
    }
  }
}
`;
}
