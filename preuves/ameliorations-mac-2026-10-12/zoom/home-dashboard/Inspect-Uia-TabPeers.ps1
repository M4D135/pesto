#requires -Version 5.1
param([string]$Root='C:\PestoZoom20261012\prod-final',[string]$ReportPath='C:\PestoZoom20261012\preuves-final\windows-Uia-AB.json')
$ErrorActionPreference='Stop';Set-StrictMode -Off
if([Diagnostics.Process]::GetCurrentProcess().SessionId -ne 0){throw 'Session 0 required'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
function Pump-Uia {
 $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(100)
 $script:UiaFrame=$frame
 $handler=[EventHandler]{param($Sender,$EventArgs);$Sender.Stop();$script:UiaFrame.Continue=$false}
 $timer.Add_Tick($handler);$timer.Start()
 try{[Windows.Threading.Dispatcher]::PushFrame($frame)}finally{$timer.Stop();$timer.Remove_Tick($handler)}
}
function Read-Peers {param($Peer)
 $ids=[Collections.Generic.List[string]]::new();$errors=[Collections.Generic.List[string]]::new();$todo=[Collections.Generic.Queue[object]]::new();$todo.Enqueue($Peer);$seen=[Collections.Generic.HashSet[object]]::new();$count=0
 while($todo.Count -and $count -lt 5000){$p=$todo.Dequeue();if(-not $seen.Add($p)){continue};$count++;try{$id=$p.GetAutomationId();if($id){$ids.Add($id)};foreach($c in @($p.GetChildren())){if($c){$todo.Enqueue($c)}}}catch{$errors.Add($_.Exception.Message)}}
 [pscustomobject]@{Count=$count;Ids=$ids.ToArray();Errors=$errors.ToArray()}
}
$cases=[Collections.Generic.List[object]]::new()
foreach($variant in @('Collapsed','MeasuredZeroHeight','CollapsedResetChildren')){
 $w=$null
 try{
  [xml]$x=Get-Content (Join-Path $Root 'wad\Pesto-Shell.xaml') -Raw -Encoding UTF8
  $node=$x.SelectSingleNode('//*[local-name()="Style" and @*[local-name()="Key"]="PageHost"]//*[local-name()="TabPanel"]')
  if(-not $node){throw 'PageHost TabPanel absent'}
  if($variant -eq 'MeasuredZeroHeight'){$node.SetAttribute('Visibility','Visible');$node.SetAttribute('Height','0');$node.SetAttribute('Opacity','0');$node.SetAttribute('IsHitTestVisible','False')}
  $w=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($x));$w.ShowInTaskbar=$false;$w.Opacity=0;$w.WindowStartupLocation='Manual';$w.Left=-12000;$w.Top=-12000;$w.Width=1100;$w.Height=760
  $w.FindName('SuiteRoot').Width=1060;$w.FindName('SuiteRoot').Height=700
  $main=$w.FindName('MainTabs');$main.SelectedIndex=4;$w.Show();Pump-Uia;$w.UpdateLayout()
  $peer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($w)
  foreach($page in @(4,0,4,0,4)){
   $main.SelectedIndex=$page;$w.UpdateLayout();Pump-Uia
   $focus=if($page -eq 4){$w.FindName('HomePrepare')}else{$w.FindName('CbSite')};[void]$focus.Focus();$w.UpdateLayout();Pump-Uia
   $tree=Read-Peers $peer
   $mainPeer=[Windows.Automation.Peers.UIElementAutomationPeer]::CreatePeerForElement($main)
   $itemPeer=@($mainPeer.GetChildren() | Where-Object {$_.GetName() -eq [string]$main.SelectedItem.Header} | Select-Object -First 1)[0]
   $selectedTree=if($itemPeer){Read-Peers $itemPeer}else{$null}
   if($variant -eq 'CollapsedResetChildren'){foreach($childPeer in @($mainPeer.GetChildren())){$childPeer.ResetChildrenCache();$childPeer.InvalidatePeer()};$mainPeer.ResetChildrenCache()};$mainPeer.InvalidatePeer();$peer.ResetChildrenCache();$peer.InvalidatePeer();Pump-Uia
   $freshTree=Read-Peers $peer
   $cases.Add([pscustomobject]@{Variant=$variant;PageIndex=$page;ExpectedId=$focus.Name;Found=($focus.Name -in $tree.Ids);SelectedFound=($selectedTree -and $focus.Name -in $selectedTree.Ids);SelectedPeerCount=$(if($selectedTree){$selectedTree.Count}else{0});AfterPublicInvalidation=($focus.Name -in $freshTree.Ids);PeerCount=$tree.Count;MainTabsPresent=('MainTabs' -in $tree.Ids);Ids=$tree.Ids;Errors=$tree.Errors})
  }
 }catch{$cases.Add([pscustomobject]@{Variant=$variant;Error=$_.Exception.Message})}finally{if($w){$w.Close()}}
}
[pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o');SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;PowerShell=[string]$PSVersionTable.PSVersion;ShellHash=(Get-FileHash (Join-Path $Root 'wad\Pesto-Shell.xaml') -Algorithm SHA256).Hash;Scope='Public WPF AutomationPeer traversal, isolated transparent off-screen window. No application startup, AD, registry or interactive desktop.';Cases=$cases.ToArray()}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $ReportPath -Encoding UTF8
$cases|Select-Object Variant,PageIndex,ExpectedId,Found,SelectedFound,SelectedPeerCount,AfterPublicInvalidation,PeerCount,MainTabsPresent,Error|ConvertTo-Json -Depth 4
