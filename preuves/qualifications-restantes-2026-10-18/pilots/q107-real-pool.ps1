param([ValidateSet('Reuse','Discard')][string]$Mode)
$ErrorActionPreference='Stop';$out='C:\PestoQual_20261018\preuves';$prod='C:\PestoQualPersonal_20261018\close-qualification\candidate\PROD'
. "$prod\wad\Pesto-Async.ps1"
$pool=New-PestoReadRunspacePool -Maximum 1 -Domain 'labo.local' -DC 'dc01.labo.local'
$rows=[Collections.Generic.List[object]]::new();$reads=0;$lastSlot=''
function Measure-Now([string]$Phase,[int]$Cycle){$proc=Get-Process -Id $PID;$rows.Add([pscustomobject]@{Phase=$Phase;Cycle=$Cycle;Utc=[datetime]::UtcNow.ToString('o');PrivateBytes=$proc.PrivateMemorySize64;Handles=$proc.HandleCount;Threads=$proc.Threads.Count;ManagedBytes=[GC]::GetTotalMemory($false);Gen2=[GC]::CollectionCount(2);PoolCount=$pool.Count;Idle=$pool.Idle.Count;LastSlot=$script:lastSlot})}
function Collect-Now{[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();Start-Sleep -Milliseconds 300}
try{
 for($cycle=-4;$cycle -le 30;$cycle++){
  $lease=Enter-PestoReadRunspace $pool;$script:lastSlot=$lease.Slot.Runspace.InstanceId.ToString();$ps=[powershell]::Create();$ps.Runspace=$lease.Slot.Runspace
  try{
   [void]$ps.AddScript({param($ModulePath) Import-Module $ModulePath -ErrorAction Stop;Get-ADComputer -Identity 'b4797c9c-d790-4797-bf71-424a57acb36e' -Server 'dc01.labo.local' -Properties ObjectGUID,DistinguishedName -ErrorAction Stop|Select ObjectGUID,DistinguishedName}.ToString());[void]$ps.AddArgument("$prod\wad\ActiveDirectory.psd1")
   $result=@($ps.Invoke());if($ps.HadErrors){throw ($ps.Streams.Error|Out-String)}
   if($result.Count -ne 1 -or [string]$result[0].ObjectGUID -ne 'b4797c9c-d790-4797-bf71-424a57acb36e'){throw 'Actual AD object missing'};$reads++;$result=$null
  }finally{$ps.Dispose();$ps=$null;Exit-PestoReadRunspace $lease -Discard:($Mode -eq 'Discard');$lease=$null}
  if($cycle -eq 0){Collect-Now;Measure-Now 'BaselineAfterWarmupGC' 0}
  elseif($cycle -gt 0){Measure-Now 'Natural' $cycle;if($cycle -in @(10,20,30)){Collect-Now;Measure-Now 'AfterGC' $cycle}}
 }
 Close-PestoReadRunspacePool $pool;Collect-Now;Measure-Now 'AfterPoolCloseGC' 30
 if($reads -ne 35 -or $pool.Count -ne 0){throw 'Read count or pool closure incorrect'}
 [pscustomobject]@{Schema=1;Mode=$Mode;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;ProcessId=$PID;ReadCount=$reads;WarmupReads=5;SourceSHA256=(Get-FileHash "$prod\wad\Pesto-Async.ps1").Hash;ExeSHA256=(Get-FileHash "$prod\Pesto.exe").Hash;Rows=$rows;Result='MEASURED_ONLY';Scope='Real product pool functions; real AD computer reads; separate process per mode; forced GC only in diagnostic process; not a GUI leak certification'}|ConvertTo-Json -Depth 6|Set-Content "$out\q107-pool-$Mode.json" -Encoding UTF8
}finally{Close-PestoReadRunspacePool $pool}
