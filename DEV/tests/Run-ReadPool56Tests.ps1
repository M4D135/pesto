#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Async.ps1')
$passed=0
function Check($ok,$message){if(-not $ok){throw $message};$script:passed++}
function Run($lease,[string]$source){$p=[powershell]::Create();$p.Runspace=$lease.Slot.Runspace;try{[void]$p.AddScript($source);$r=@($p.Invoke());if($p.HadErrors){throw ($source+' => '+($p.Streams.Error|Out-String))};return $r}finally{$p.Dispose()}}
$p=New-PestoReadRunspacePool -Maximum 2
try{
 $a=Enter-PestoReadRunspace $p;$first=$a.Slot.Runspace
 [void](Run $a '$global:CredentialLeak="sentinel";function global:CredentialLeakFn {"sentinel"};Set-Alias -Scope Global -Name CredentialLeakAlias -Value Get-Date')
 $b=Enter-PestoReadRunspace $p
 Check (-not [object]::ReferenceEquals($first,$b.Slot.Runspace)) 'Concurrent readers shared a runspace'
 $refused=$false;try{Enter-PestoReadRunspace $p}catch{$refused=$true};Check $refused 'Pool admitted a third reader'
 Exit-PestoReadRunspace $a
 $next=Enter-PestoReadRunspace $p
 Check ([object]::ReferenceEquals($first,$next.Slot.Runspace)) 'Clean reader was not reused'
 $r=Run $next '@(Get-Variable | Where-Object Name -EQ CredentialLeak);@(Get-ChildItem Function: | Where-Object Name -EQ CredentialLeakFn);@(Get-Alias | Where-Object Name -EQ CredentialLeakAlias)'
 Check (@($r).Count -eq 0) 'State leaked across read jobs'
 Exit-PestoReadRunspace $next -Discard
 Check ($p.Count -eq 1) 'Faulted reader retained'
 Exit-PestoReadRunspace $next
 Check ($p.Count -eq 1) 'Double release changed accounting'
 Close-PestoReadRunspacePool $p
 Check ($p.Count -eq 1) 'Retirement closed a busy reader'
 Check ((Run $b '42')[0] -eq 42) 'Busy reader interrupted by retirement'
 Exit-PestoReadRunspace $b
 Check ($p.Count -eq 0) 'Retired reader retained'
 $refused=$false;try{Enter-PestoReadRunspace $p}catch{$refused=$true};Check $refused 'Retired pool reused'
}finally{Close-PestoReadRunspacePool $p}
# A clean lease keeps the built-in baseline. A changed baseline is never reused.
$probe=New-PestoReadRunspacePool -Maximum 1
try{
 $lease=Enter-PestoReadRunspace $probe;$original=$lease.Slot.Runspace
 $promptBefore=[string](Run $lease '(Get-Item Function:\prompt).Definition')
 $aliasBefore=[string](Run $lease '(Get-Alias cd).Definition')
 Exit-PestoReadRunspace $lease
 $lease=Enter-PestoReadRunspace $probe
 Check ([object]::ReferenceEquals($original,$lease.Slot.Runspace)) 'Untouched baseline was discarded'
 Check (([string](Run $lease '(Get-Item Function:\prompt).Definition')) -ceq $promptBefore) 'Initial function changed during cleanup'
 Check (([string](Run $lease '(Get-Alias cd).Definition')) -ceq $aliasBefore) 'Initial alias changed during cleanup'
 [void](Run $lease 'function global:prompt {"changed"}')
 Exit-PestoReadRunspace $lease
 Check ($probe.Count -eq 0) 'Altered initial function was reused'
 $lease=Enter-PestoReadRunspace $probe
 Check (-not [object]::ReferenceEquals($original,$lease.Slot.Runspace)) 'Discarded function state was reused'
 Check (([string](Run $lease '(Get-Item Function:\prompt).Definition')) -ceq $promptBefore) 'New runspace inherited altered function'
 [void](Run $lease 'Set-Alias -Name cd -Value Get-Date -Scope Global -Option AllScope -Force')
 Exit-PestoReadRunspace $lease
 Check ($probe.Count -eq 0) 'Altered initial alias was reused'
 $lease=Enter-PestoReadRunspace $probe
 [void](Run $lease 'Remove-Item -LiteralPath Function:\prompt -Force')
 Exit-PestoReadRunspace $lease
 Check ($probe.Count -eq 0) 'Deleted initial function was reused'
 $lease=Enter-PestoReadRunspace $probe
 [void](Run $lease 'Remove-Item -LiteralPath Alias:\cd -Force')
 Exit-PestoReadRunspace $lease
 Check ($probe.Count -eq 0) 'Deleted initial alias was reused'
}finally{Close-PestoReadRunspacePool $probe}
$c1=[pscredential]::new('EXAMPLE\a',(ConvertTo-SecureString 'fake-a' -AsPlainText -Force))
$c2=[pscredential]::new('EXAMPLE\a',(ConvertTo-SecureString 'fake-b' -AsPlainText -Force))
$p1=Get-PestoSessionReadPool $c1 'example.test' 'dc.example.test';$a=Enter-PestoReadRunspace $p1
[void](Run $a '$global:CredentialLeak="old-account"');Exit-PestoReadRunspace $a
Check ([object]::ReferenceEquals($p1,(Get-PestoSessionReadPool $c1 'example.test' 'dc.example.test'))) 'Same context did not reuse its pool'
$p2=Get-PestoSessionReadPool $c2 'example.test' 'dc.example.test'
Check ($p1.Retired -and $p1.Count -eq 0 -and $null -eq $p1.Credential) 'Credential switch retained the old pool'
Check ($p1.Scope -ne $p2.Scope) 'Credential switch reused identity scope'
$a=Enter-PestoReadRunspace $p2
Check (@(Run $a 'Get-Variable | Where-Object Name -EQ CredentialLeak').Count -eq 0) 'Identity leakage'
Exit-PestoReadRunspace $a
$p3=Get-PestoSessionReadPool $c2 'example.test' 'dc2.example.test'
Check ($p2.Retired -and $p2.Scope -ne $p3.Scope) 'DC switch reused old state'
Close-PestoReadRunspacePool $p3
# --- Concurrence reelle : des lecteurs paralleles empruntent le meme pool. ---
# Le plafond de creneaux est la seule valeur que le pool tient vraiment, et une suite sequentielle ne le
# prouve pas. Les lecteurs sont reveilles au meme instant par une barriere et comptent eux-memes le runspace
# qu on leur prete : deux lecteurs simultanes sur un meme runspace est une faute, jamais un hasard de mesure.
$asyncFile=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad/Pesto-Async.ps1'
$readBody='param($Marker);$c=[Diagnostics.Stopwatch]::StartNew();while($c.Elapsed.TotalMilliseconds -lt 40){};''lu'''
$saturatedReader={
    param($AsyncFile,$Pool,$Shared,$Work,$Index)
    . $AsyncFile
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Ready=$Shared.Ready+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $Shared.Go -and $clock.ElapsedMilliseconds -lt 15000){[Threading.Thread]::Sleep(1)}
    try{
        $lease=Enter-PestoReadRunspace $Pool
        [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Admitted=$Shared.Admitted+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
        Exit-PestoReadRunspace $lease
        'admis'
    }catch{
        [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Refused=$Shared.Refused+1;$Shared.Messages=@($Shared.Messages)+$_.Exception.Message}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
        'refuse'
    }
}.ToString()
$parallelReader={
    param($AsyncFile,$Pool,$Shared,$Work,$Index)
    . $AsyncFile
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Ready=$Shared.Ready+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while(-not $Shared.Go -and $clock.ElapsedMilliseconds -lt 15000){[Threading.Thread]::Sleep(1)}
    $wait=[Diagnostics.Stopwatch]::StartNew();$lease=$null
    while($null -eq $lease){
        try{$lease=Enter-PestoReadRunspace $Pool}
        catch{
            if($_.Exception.Message -notlike 'Pool de lectures sature*'){throw}
            [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.Refused=$Shared.Refused+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
            if($wait.ElapsedMilliseconds -gt 30000){throw 'A parallel reader waited too long for a slot.'}
            [Threading.Thread]::Sleep(2)
        }
    }
    $waited=$wait.ElapsedMilliseconds;$key=$lease.Slot.Runspace.InstanceId.ToString()
    [Threading.Monitor]::Enter($Shared.SyncRoot)
    try{
        if($waited -gt $Shared.MaxWaitMs){$Shared.MaxWaitMs=$waited}
        if(-not $Shared.PerRunspace.ContainsKey($key)){$Shared.PerRunspace[$key]=0}
        $Shared.PerRunspace[$key]=$Shared.PerRunspace[$key]+1
        if($Shared.PerRunspace[$key] -gt $Shared.PeakInFlight){$Shared.PeakInFlight=$Shared.PerRunspace[$key]}
        if($Shared.PerRunspace.Count -gt $Shared.PeakRunspaces){$Shared.PeakRunspaces=$Shared.PerRunspace.Count}
    }finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    $ps=[PowerShell]::Create();$ps.Runspace=$lease.Slot.Runspace
    [void]$ps.AddScript($Work).AddArgument('lecteur-'+$Index)
    $seen=@($ps.Invoke());if($ps.HadErrors){throw ('The borrowed read failed : '+($ps.Streams.Error|Out-String))}
    $ps.Dispose()
    [Threading.Monitor]::Enter($Shared.SyncRoot);try{$Shared.PerRunspace[$key]=$Shared.PerRunspace[$key]-1;$Shared.Done=$Shared.Done+1}finally{[Threading.Monitor]::Exit($Shared.SyncRoot)}
    Exit-PestoReadRunspace $lease
    'lu'
}.ToString()
function Start-PestoReaderWave {
    param([string]$Worker,[hashtable]$Pool,[hashtable]$Shared,[string]$Work,[int]$Count)
    $workers=@()
    foreach($n in 1..$Count){
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript($Worker,$true).AddArgument($asyncFile).AddArgument($Pool).AddArgument($Shared).AddArgument($Work).AddArgument($n)
        $workers+=@(@{PS=$ps;Handle=$ps.BeginInvoke()})
    }
    return $workers
}
function Wait-PestoReaderWave {
    param([hashtable]$Shared,[object[]]$Workers,[int]$Count,[int]$TimeoutMs=40000)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($Shared.Ready -lt $Count -and $clock.ElapsedMilliseconds -lt $TimeoutMs){[Threading.Thread]::Sleep(2)}
    Check ($Shared.Ready -eq $Count) ('Only '+$Shared.Ready+' readers of '+$Count+' reached the barrier')
    $Shared.Go=$true
    return @(foreach($worker in $Workers){$worker.PS.EndInvoke($worker.Handle)})
}
# Un pool deja plein doit refuser chaque demandeur arrive au meme instant, et rendre ensuite tous ses creneaux.
$ceiling=2
$saturated=New-PestoReadRunspacePool -Maximum $ceiling
try{
    $held=@(foreach($n in 1..$ceiling){Enter-PestoReadRunspace $saturated})
    $shared=[hashtable]::Synchronized(@{Ready=0;Go=$false;Admitted=0;Refused=0;Messages=@()})
    $workers=@(Start-PestoReaderWave -Worker $saturatedReader -Pool $saturated -Shared $shared -Work $readBody -Count 4)
    $verdicts=@(Wait-PestoReaderWave -Shared $shared -Workers $workers -Count 4)
    Check (@($verdicts|Where-Object{$_ -eq 'refuse'}).Count -eq 4) ('A borrower was admitted into a saturated pool : '+($verdicts -join ','))
    Check (@($shared.Messages|Where-Object{$_ -like 'Pool de lectures sature*'}).Count -eq 4) ('A saturated pool refused a borrower for another reason : '+((@($shared.Messages|Select-Object -Unique)) -join ' | '))
    Check ($saturated.Count -eq $ceiling -and $saturated.Idle.Count -eq 0) ('Concurrent borrowers changed the accounting of a saturated pool : '+$saturated.Count+' runspaces, '+$saturated.Idle.Count+' idle')
    foreach($lease in $held){Exit-PestoReadRunspace $lease}
    Check ($saturated.Idle.Count -eq $ceiling) ('A slot held during the saturation wave was never returned : '+$saturated.Idle.Count+' idle for '+$ceiling)
}finally{Close-PestoReadRunspacePool $saturated}
# Huit lecteurs reveilles ensemble sur trois creneaux : le plafond est tenu, aucun runspace n est partage.
$ceiling=3;$wave=8
$concurrent=New-PestoReadRunspacePool -Maximum $ceiling
try{
    $shared=[hashtable]::Synchronized(@{Ready=0;Go=$false;Done=0;Refused=0;PeakInFlight=0;PeakRunspaces=0;MaxWaitMs=0L;PerRunspace=@{}})
    $workers=@(Start-PestoReaderWave -Worker $parallelReader -Pool $concurrent -Shared $shared -Work $readBody -Count $wave)
    $read=@(Wait-PestoReaderWave -Shared $shared -Workers $workers -Count $wave)
    foreach($worker in $workers){$worker.PS.Dispose()}
    Check (@($read|Where-Object{$_ -eq 'lu'}).Count -eq $wave) ('The parallel wave did not finish all its reads : '+@($read|Where-Object{$_ -eq 'lu'}).Count+' of '+$wave)
    Check ($shared.PeakInFlight -eq 1) ('Two concurrent readers shared one borrowed runspace : '+$shared.PeakInFlight+' readers at once on a single runspace')
    Check ($shared.PeakRunspaces -le $ceiling) ('The pool admitted more concurrent runspaces than its maximum : '+$shared.PeakRunspaces+' for '+$ceiling)
    Check ($shared.PeakRunspaces -ge 2) ('The parallel wave never borrowed two runspaces at once : peak '+$shared.PeakRunspaces+' for '+$wave+' readers')
    Check ($shared.Refused -ge 1) ([string]$wave+' borrowers on '+[string]$ceiling+' slots never met one refusal : the wave ran sequentially, not concurrently')
    Check ($concurrent.Idle.Count -eq $concurrent.Count) ('A lease of the parallel wave never came back to the pool : '+$concurrent.Count+' runspaces, '+$concurrent.Idle.Count+' idle')
    Check ($concurrent.Count -le $ceiling -and $concurrent.Count -ge 2) ('The parallel wave left an unexpected number of runspaces in the pool : '+$concurrent.Count)
}finally{Close-PestoReadRunspacePool $concurrent}
# Une lecture en cours garde son runspace quand l identite change sous elle : le nouveau compte ne recycle rien.
$credA=[pscredential]::new('EXAMPLE\lecteur-a',(ConvertTo-SecureString 'marque-a' -AsPlainText -Force))
$credB=[pscredential]::new('EXAMPLE\lecteur-b',(ConvertTo-SecureString 'marque-b' -AsPlainText -Force))
$poolA=Get-PestoSessionReadPool $credA 'example.test' 'dc.example.test'
$inFlight=Enter-PestoReadRunspace $poolA
[void](Run $inFlight '$global:IdentityMarker="compte-a"')
$poolB=Get-PestoSessionReadPool $credB 'example.test' 'dc.example.test'
Check ($poolA.Retired -and -not $poolB.Retired) ('The account change that arrived under a read in flight left the pools in state ['+$poolA.Retired+'/'+$poolB.Retired+']')
Check (-not [object]::ReferenceEquals($poolA,$poolB)) 'The new account was handed the pool of the account still reading'
$other=Enter-PestoReadRunspace $poolB
Check (-not [object]::ReferenceEquals($inFlight.Slot.Runspace,$other.Slot.Runspace)) 'The new account reused the runspace borrowed by the account still reading'
Check (@(Run $other 'Get-Variable | Where-Object Name -EQ IdentityMarker').Count -eq 0) 'The account still reading leaked its state to the new account'
Check (@(Run $inFlight '(Get-Variable -Name IdentityMarker -ValueOnly -ErrorAction SilentlyContinue)')[0] -ceq 'compte-a') 'The read in flight lost its own state when the account changed'
Exit-PestoReadRunspace $inFlight
Check ($poolA.Count -eq 0 -and $poolA.Idle.Count -eq 0) ('A retired pool kept a returned runspace : '+$poolA.Count+' runspaces, '+$poolA.Idle.Count+' idle')
Exit-PestoReadRunspace $other
$poolA2=Get-PestoSessionReadPool $credA 'example.test' 'dc.example.test'
Check (-not [object]::ReferenceEquals($poolA,$poolA2) -and -not $poolA2.Retired) 'The retired pool of the first account was brought back when that account returned'
$again=Enter-PestoReadRunspace $poolA2
Check (@(Run $again 'Get-Variable | Where-Object Name -EQ IdentityMarker').Count -eq 0) 'A runspace of the first account survived that account s retirement'
Exit-PestoReadRunspace $again
Close-PestoReadRunspacePool $poolA2
Write-Output "ReadPool56 : $passed/$passed PASS"
