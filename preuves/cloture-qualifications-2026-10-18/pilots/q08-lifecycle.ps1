. 'C:\PestoQual_20261018\pilot\commun.ps1'

Add-Type -AssemblyName PresentationFramework
$defs=@{}
foreach($f in @('Pesto-Workspace.ps1','Pesto-Workbench.ps1','Pesto-Contracts.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile(('C:\PestoQualPersonal_20261018\candidate-fix\PROD\wad\'+$f),[ref]$t,[ref]$e)
 foreach($n in $ast.EndBlock.Statements){if($n -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$n.Name]=$n.Extent.Text}}
}
foreach($n in @('Show-PestoHostedWindow','Complete-PestoHostedWindow','Invoke-PestoHostedKey','Invoke-PestoPanelClosing','Show-PestoChoiceTable','Set-PestoChoiceGrouping','Get-PestoChoiceSearchKeys','New-PestoChoiceSearchIndex','ConvertTo-PestoSearchText','Update-PestoChoiceSearch','Get-PestoFilteredChoiceRows')){. ([scriptblock]::Create($defs[$n]))}
function Set-WindowIcon {param($Window)}
$script:references=[Collections.Generic.List[object]]::new();$script:allStopped=$true
$script:Win=[Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Pesto lifecycle probe" Width="600" Height="400"><Grid><TextBox Text="draft"/></Grid></Window>')
$script:Win.Add_Closing([ComponentModel.CancelEventHandler]${function:Invoke-PestoPanelClosing})
$script:closer=[Windows.Threading.DispatcherTimer]::new();$script:closer.Interval=[TimeSpan]::FromMilliseconds(250)
$script:closer.Add_Tick({param($s,$e)
 $s.Stop();$window=$script:PestoPanelStack[$script:PestoPanelStack.Count-1].HostedWindow
 $search=$window.FindName('Search');$search.Text='sam'
 $state=$search.Tag
 $script:references.Add([pscustomobject]@{Window=[WeakReference]::new($window);Timer=[WeakReference]::new($state.Timer);Search=[WeakReference]::new($search)})
 $window.Close()
 $script:allStopped=$script:allStopped -and $state.Closed -and -not $state.Timer.IsEnabled -and $state.SearchIndex.Count -eq 0
})
$script:Win.Show();$points=@()
try {
 foreach($cycle in 1..60){
  $script:closer.Start()
  [void](Show-PestoChoiceTable -Title ('Cycle '+$cycle) -Rows @([pscustomobject]@{Name='Sample'}) -Columns @(@{Key='Name';Label='Name'}))
  if($cycle -in 10,20,40,60){
   [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
   $p=Get-Process -Id $PID
   $points+=[pscustomobject]@{Cycle=$cycle;PrivateBytes=$p.PrivateMemorySize64;Handles=$p.HandleCount;LiveWindows=@($script:references|Where-Object {$_.Window.IsAlive}).Count;LiveTimers=@($script:references|Where-Object {$_.Timer.IsAlive}).Count;LiveSearches=@($script:references|Where-Object {$_.Search.IsAlive}).Count;PanelDepth=$script:PestoPanelStack.Count}
  }
 }
} finally {$script:closer.Stop();$script:Win.Close()}
$report=[pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o');Cycles=60;Source='Production hosted window and choice table functions, genuine WPF windows/search DispatcherTimers; partial pending search on every close';AllClosedSearchTimersStopped=$script:allStopped;Samples=$points;PowerShell=$PSVersionTable.PSVersion.ToString()}
$report|ConvertTo-Json -Depth 6|Set-Content "$D\q08-lifecycle.json" -Encoding UTF8
$report|ConvertTo-Json -Depth 6
