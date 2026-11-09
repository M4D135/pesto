#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
# Point 114 : l'évaluation du diff d'attributs complémentaires est jouée comme un vrai processus enfant par le
# consommateur réel de l'intégrateur, integrations/Test-PestoAttributeDiff.ps1. Ce consommateur est le seul
# endroit où l'aperçu remis à l'opérateur (New-PestoAttributeProposal, Pesto.Optional.psm1) est confronté aux
# gardes du moteur lui-même (Get-PestoAttributeChanges et Assert-PestoAttributeChanges, wad/Pesto-Extensions.ps1) :
# les fichiers réels sont copiés hors sac, seule l'intégrité du paquet est doublée, sans quoi rien ne serait
# jouable hors Windows. Aucune lecture AD, aucun appel réseau, aucune écriture de registre, aucune mutation :
# la référence managedBy reste à épingler par le plan, seule étape autorisée à lire le répertoire.
$root=Split-Path $PSScriptRoot -Parent
$hostExe=(Get-Process -Id $PID).Path
$cases=[Collections.Generic.List[object]]::new()
function Require-Diff {param($Value,[string]$Message);if(-not $Value){throw $Message}}
function Equal-Diff {param($Actual,$Expected,[string]$Why='');if($Actual -cne $Expected){throw ('attendu ['+[string]$Expected+'] obtenu ['+[string]$Actual+'] '+$Why)}}
function Case-Diff {param($Name,[scriptblock]$Body)
    try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('PASS '+$Name)}
    catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('FAIL '+$Name+' : '+$_.Exception.Message)}}
$guid='22222222-2222-2222-2222-222222222222'
$refDn='CN=Admin Reference,OU=Postes,OU=Organisme,DC=example,DC=local'
$currentJson='{"description":"old","location":"old place","managedBy":""}'
function Write-Doc {param([string]$Name,[string]$Json)
    $path=Join-Path $temp ($Name+'.json')
    [IO.File]::WriteAllText($path,$Json,[Text.UTF8Encoding]::new($false))
    return $path}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('PestoAttributeDiff114-'+[Guid]::NewGuid().ToString('N'))
try{
    $install=Join-Path $temp 'pack'
    [void][IO.Directory]::CreateDirectory((Join-Path $install 'wad'))
    [void][IO.Directory]::CreateDirectory((Join-Path $install 'integrations'))
    foreach($relative in @('wad/Pesto-Contracts.ps1','wad/Pesto-Extensions.ps1','integrations/Pesto.Optional.psm1','integrations/Test-PestoAttributeDiff.ps1')){
        $destination=Join-Path $install $relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath (Join-Path $root $relative) -Destination $destination
    }
    $script:entry=Join-Path $install 'integrations/Test-PestoAttributeDiff.ps1'
    $script:module=Join-Path $install 'integrations/Pesto.Optional.psm1'
    function Set-Integrity {param([bool]$Ok)[IO.File]::WriteAllText((Join-Path $install 'wad/Pesto-Integrity.ps1'),('function Test-PestoPackage {param($Root);'+$(if($Ok){'$true'}else{'$false'}))+'}'+"`r`n",[Text.UTF8Encoding]::new($false))}
    function Mutate-Module {param([string]$Literal,[string]$Replacement)
        $text=[IO.File]::ReadAllText($script:module,[Text.UTF8Encoding]::new($true))
        Require-Diff (@([regex]::Matches($text,[regex]::Escape($Literal))).Count -eq 1) ('mutation attendue une seule fois : '+$Literal)
        $text=$text.Replace($Literal,$Replacement)
        [IO.File]::WriteAllText($script:module,$text,[Text.UTF8Encoding]::new($true))}
    function Restore-Module {[IO.File]::WriteAllText($script:module,[IO.File]::ReadAllText((Join-Path $root 'integrations/Pesto.Optional.psm1'),[Text.UTF8Encoding]::new($true)),[Text.UTF8Encoding]::new($true))}
    Set-Integrity -Ok $true
    function Invoke-Diff {param([string[]]$ChildArguments)
        $previous=$ErrorActionPreference;$ErrorActionPreference='Continue'
        $lines=@(& $hostExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:entry @ChildArguments 2>&1|ForEach-Object{[string]$_})
        $code=$LASTEXITCODE;$ErrorActionPreference=$previous
        return [pscustomobject]@{Code=$code;Text=($lines -join "`n")}}
    function Invoke-DiffReport {param([string[]]$ChildArguments,[int]$ExpectedExit)
        $run=Invoke-Diff -ChildArguments ($ChildArguments+@('-AsJson'))
        Require-Diff ($run.Code -eq $ExpectedExit) ('code '+$run.Code+' attendu pour '+$ExpectedExit+' : '+$run.Text)
        Require-Diff (-not ($run.Text -match '[^\x00-\x7F]')) ('sortie non ASCII : '+$run.Text)
        $value=$run.Text|ConvertFrom-Json
        Require-Diff ($value.ExitCode -eq $ExpectedExit) ('ExitCode du rapport incoherent avec le processus : '+$value.ExitCode)
        Require-Diff ($value.WindowsExecuted -eq $false -and $value.ADExecuted -eq $false -and $value.RegistryWritten -eq $false -and $value.PolicyChanged -eq $false) 'Le controle se declare executeur'
        $value|Add-Member -NotePropertyName RawText -NotePropertyValue $run.Text -Force|Out-Null
        return $value}
    function Invoke-Candidate {param([string]$RequestJson,[int]$ExpectedExit,[string]$CurrentJson=$currentJson,[string]$ObjectGuid=$guid)
        $current=Write-Doc -Name ('current-'+[Guid]::NewGuid().ToString('N')) -Json $CurrentJson
        $request=Write-Doc -Name ('request-'+[Guid]::NewGuid().ToString('N')) -Json $RequestJson
        return Invoke-DiffReport -ExpectedExit $ExpectedExit -ChildArguments @('-Installation',$install,'-ObjectGuid',$ObjectGuid,'-CurrentPath',$current,'-RequestPath',$request)}
    Case-Diff 'Accepted diff names the attributes the operator is about to hand over' {
        $r=Invoke-Candidate -RequestJson '{"description":"Atelier","location":""}' -ExpectedExit 0
        Equal-Diff $r.PreviewAccepted $true;Equal-Diff $r.EngineAccepted $true;Equal-Diff $r.DiffMatches $true
        Equal-Diff $r.Divergence $false;Equal-Diff $r.Executable $true;Equal-Diff $r.ChangeCount 2
        Equal-Diff (@($r.Attributes) -join ',') 'description,location'
        Equal-Diff (@($r.Clears) -join ',') 'location'
        Equal-Diff $r.ObjectGuid '22222222-2222-2222-2222-222222222222'
        }
    Case-Diff 'A managedBy reference stays pending for the plan step that alone may read AD' {
        $r=Invoke-Candidate -RequestJson ('{"managedBy":"'+$refDn+'"}') -ExpectedExit 0
        Equal-Diff $r.Executable $true;Equal-Diff $r.ReferencePending $true;Equal-Diff $r.ChangeCount 1
        Equal-Diff (@($r.Attributes) -join ',') 'managedBy'
        }
    Case-Diff 'A request equal to the current state is refused before the handover' {
        $r=Invoke-Candidate -RequestJson '{"description":"old"}' -ExpectedExit 96
        Equal-Diff $r.PreviewAccepted $false;Equal-Diff $r.PreviewError 'Un à trois changements attendus.'
        Equal-Diff $r.Executable $false;Equal-Diff $r.ChangeCount 0
        }
    Case-Diff 'A fourth change is refused by the preview guard' {
        $r=Invoke-Candidate -RequestJson ('{"description":"a","location":"b","managedBy":"'+$refDn+'","extra":"c"}') -ExpectedExit 96
        Equal-Diff $r.PreviewError 'Attribut non autorisé.';Equal-Diff $r.Executable $false
        }
    Case-Diff 'A duplicated member in the request document is refused on the text' {
        $r=Invoke-Candidate -RequestJson '{"description":"premiere","description":"seconde"}' -ExpectedExit 96
        Equal-Diff $r.Message 'Document candidat illisible.';Equal-Diff $r.Executable $false
        }
    Case-Diff 'An attribute outside the three allowed is refused without echoing its name' {
        $canary='CANARY114userAccountControl'
        $r=Invoke-Candidate -RequestJson ('{'+[char]34+$canary+[char]34+':'+[char]34+'0'+[char]34+'}') -ExpectedExit 96
        Equal-Diff $r.PreviewError 'Attribut non autorisé.';Equal-Diff $r.EngineError 'Champ non autorisé.'
        Require-Diff (-not $r.RawText.Contains($canary)) ('le nom candidat a fuité dans la sortie : '+$r.RawText)
        }
    Case-Diff 'A managedBy value without a distinguished name is refused by both legs' {
        $r=Invoke-Candidate -RequestJson '{"managedBy":"Administrator"}' -ExpectedExit 96
        Equal-Diff $r.PreviewError 'managedBy attend un DN validé séparément.'
        Equal-Diff $r.EngineError 'managedBy exige un DN.';Equal-Diff $r.Executable $false
        }
    Case-Diff 'An oversized value is refused before any plan is written' {
        $r=Invoke-Candidate -RequestJson ('{"location":"'+('x'*1025)+'"}') -ExpectedExit 96
        Equal-Diff $r.EngineError 'Valeur attribut invalide.';Equal-Diff $r.Executable $false
        }
    Case-Diff 'A control character in a value never reaches the report' {
        $r=Invoke-Candidate -RequestJson ('{"description":"mauvaise'+([char]9)+'valeur"}') -ExpectedExit 96
        Equal-Diff $r.EngineError 'Valeur attribut invalide.';Equal-Diff $r.Executable $false
        Require-Diff (-not ($r.RawText -match '[\x00-\x08\x0b\x0c\x0e-\x1f]')) ('caractere de controle dans la sortie : '+$r.RawText)
        }
    Case-Diff 'A preview that drops the reference field is refused as divergent' {
        try{Mutate-Module -Literal "After=`$property.Value;ReferenceGuid=''" -Replacement 'After=$property.Value'
            $r=Invoke-Candidate -RequestJson '{"description":"nouvelle valeur"}' -ExpectedExit 96
            Equal-Diff $r.Divergence $true;Equal-Diff $r.Message 'Aperçu divergent du moteur.';Equal-Diff $r.Executable $false
        }finally{Restore-Module}
        }
    Case-Diff 'A preview that rewrites the value it claims to replace is refused as divergent' {
        try{Mutate-Module -Literal 'Before=[string]$Current.($property.Name)' -Replacement ('Before='+[char]39+[char]39)
            $r=Invoke-Candidate -RequestJson '{"description":"nouvelle valeur"}' -ExpectedExit 96
            Equal-Diff $r.PreviewAccepted $true;Equal-Diff $r.EngineAccepted $true
            Equal-Diff $r.DiffMatches $false;Equal-Diff $r.Divergence $true
            Equal-Diff $r.Message 'Aperçu divergent du moteur.';Equal-Diff $r.Executable $false
        }finally{Restore-Module}
        }
    Case-Diff 'A preview that no longer counts changes is caught by the engine guard' {
        try{Mutate-Module -Literal 'if($changes.Count -lt 1 -or $changes.Count -gt 3){throw ''Un à trois changements attendus.''}' -Replacement 'if($false){throw ''Un à trois changements attendus.''}'
            $r=Invoke-Candidate -RequestJson '{"description":"old"}' -ExpectedExit 96
            Equal-Diff $r.PreviewAccepted $true;Equal-Diff $r.Divergence $false
            Equal-Diff $r.EngineError 'Une a trois modifications requises.';Equal-Diff $r.Executable $false
        }finally{Restore-Module}
        }
    Case-Diff 'A relative candidate path is refused before any read' {
        $current=Write-Doc -Name 'current-rel' -Json $currentJson
        $r=Invoke-DiffReport -ExpectedExit 96 -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath','request-rel.json')
        Equal-Diff $r.Message 'Document candidat illisible.'
        }
    Case-Diff 'An empty candidate document is refused' {
        $current=Write-Doc -Name 'current-empty' -Json $currentJson
        $request=Write-Doc -Name 'request-empty' -Json ''
        $r=Invoke-DiffReport -ExpectedExit 96 -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request)
        Equal-Diff $r.Message 'Document candidat illisible.'
        }
    Case-Diff 'An oversized candidate document is refused' {
        $current=Write-Doc -Name 'current-big' -Json $currentJson
        $path=Write-Doc -Name 'request-big' -Json '{"description":"a"}'
        [IO.File]::AppendAllText($path,(' '*(70000-[IO.File]::ReadAllBytes($path).Length)),[Text.UTF8Encoding]::new($false))
        $r=Invoke-DiffReport -ExpectedExit 96 -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$path)
        Equal-Diff $r.Message 'Document candidat illisible.'
        }
    Case-Diff 'A candidate document that is not a structured object is refused' {
        $current=Write-Doc -Name 'current-array' -Json $currentJson
        $request=Write-Doc -Name 'request-array' -Json '["description"]'
        $r=Invoke-DiffReport -ExpectedExit 96 -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request)
        Equal-Diff $r.Message 'Document candidat illisible.'
        }
    Case-Diff 'A relative installation path is refused' {
        $current=Write-Doc -Name 'current-inst' -Json $currentJson
        $request=Write-Doc -Name 'request-inst' -Json '{"description":"a"}'
        $r=Invoke-DiffReport -ExpectedExit 96 -ChildArguments @('-Installation','pack','-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request)
        Equal-Diff $r.Message 'Installation doit être un chemin absolu local.'
        }
    Case-Diff 'An unverified package is refused before any evaluation' {
        try{Set-Integrity -Ok $false
            $r=Invoke-Candidate -RequestJson '{"description":"a"}' -ExpectedExit 96
            Equal-Diff $r.Message 'Intégrité du paquet non confirmée.'
        }finally{Set-Integrity -Ok $true}
        }
    Case-Diff 'A missing or malformed object identity is refused' {
        $r=Invoke-Candidate -RequestJson '{"description":"a"}' -ExpectedExit 96 -ObjectGuid ''
        Equal-Diff $r.Message 'Identifiant AD requis.'
        $r=Invoke-Candidate -RequestJson '{"description":"a"}' -ExpectedExit 96 -ObjectGuid '00000000-0000-0000-0000-000000000000'
        Equal-Diff $r.Message 'Identifiant AD requis.'
        }
    Case-Diff 'The report is never silently overwritten' {
        $report=Join-Path $temp ('rapport-'+[Guid]::NewGuid().ToString('N')+'.json')
        $current=Write-Doc -Name 'current-report' -Json $currentJson
        $request=Write-Doc -Name 'request-report' -Json '{"description":"valeur remise"}'
        $first=Invoke-Diff -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request,'-ReportPath',$report)
        Equal-Diff $first.Code 0 'le premier rapport a échoué'
        $saved=[IO.File]::ReadAllText($report)
        $second=Invoke-Diff -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request,'-ReportPath',$report)
        Equal-Diff $second.Code 96 'un rapport deja ecrit a ete remplace sans refus'
        Equal-Diff ([IO.File]::ReadAllText($report)) $saved 'le rapport remis a ete reecrit'
        }
    Case-Diff 'The report never carries the candidate values' {
        $canary='CANARY114-'+[Guid]::NewGuid().ToString('N')
        $report=Join-Path $temp ('rapport-canary-'+[Guid]::NewGuid().ToString('N')+'.json')
        $current=Write-Doc -Name 'current-canary' -Json ('{"description":"'+$canary+'-avant","location":"place"}')
        $request=Write-Doc -Name 'request-canary' -Json ('{"description":"'+$canary+'-apres"}')
        $run=Invoke-Diff -ChildArguments @('-Installation',$install,'-ObjectGuid',$guid,'-CurrentPath',$current,'-RequestPath',$request,'-ReportPath',$report,'-AsJson')
        Equal-Diff $run.Code 0 $run.Text
        Require-Diff (-not $run.Text.Contains($canary)) ('valeur candidate dans la sortie : '+$run.Text)
        Require-Diff (-not ([IO.File]::ReadAllText($report)).Contains($canary)) 'valeur candidate dans le rapport'
        }
}finally{if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
$report=[pscustomobject]@{Schema=1;Suite='AttributeDiff114Preflight';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=$false;ADExecuted=$false;WPFExecuted=$false;Scope='Consommateur integrateur joue en processus enfant contre les fichiers reels du moteur ; seule l''integrite du paquet est doublee ; aucun appel reseau';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
Write-Host ("AttributeDiff114Preflight: $($report.Passed) passed, $($report.Failed) failed. Real integrator consumer, engine guards and preview compared; no AD call.")
$report|Select-Object Suite,Total,Passed,Failed|Format-Table
if($report.Failed){exit 1}
