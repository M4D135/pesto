. 'C:\PestoQual_20261018\pilot\commun.ps1'

Add-Type -AssemblyName PresentationFramework
Add-Type 'using System;using System.Runtime.InteropServices;public static class PestoNativeCloseProbe{[DllImport("user32.dll")]public static extern bool PostMessage(IntPtr h,int m,IntPtr w,IntPtr l);}'
$defs=@{}
foreach($f in @('Pesto-Workspace.ps1','Pesto-Workbench.ps1','Pesto-Contracts.ps1')){
 $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile(('C:\PestoQualPersonal_20261018\candidate-fix\PROD\wad\'+$f),[ref]$t,[ref]$e)
 foreach($n in $ast.EndBlock.Statements){if($n -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$n.Name]=$n.Extent.Text}}
}
foreach($n in @('Show-PestoHostedWindow','Complete-PestoHostedWindow','Invoke-PestoHostedKey','Invoke-PestoPanelClosing','Show-PestoChoiceTable','Set-PestoChoiceGrouping','Get-PestoChoiceSearchKeys','New-PestoChoiceSearchIndex','ConvertTo-PestoSearchText','Update-PestoChoiceSearch','Get-PestoFilteredChoiceRows')){. ([scriptblock]::Create($defs[$n]))}
function Set-WindowIcon {param($Window)}
$script:events=[Collections.Generic.List[string]]::new()
$script:Win=[Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Pesto closing probe" Width="600" Height="400"><Grid><Grid Name="SuiteRoot"><TextBox Name="Draft" Text="unsaved"/></Grid></Grid></Window>')
$script:Win.Add_Closing({param($s,$e);$script:events.Add('before count='+$script:PestoPanelStack.Count)})
$script:Win.Add_Closing([ComponentModel.CancelEventHandler]${function:Invoke-PestoPanelClosing})
$script:Win.Add_Closing({param($s,$e);$script:events.Add('after cancel='+$e.Cancel)})
$script:tick=0
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromSeconds(1)
$timer.Add_Tick({param($s,$e)
 $script:tick++
 if($script:tick -eq 1){$h=[Windows.Interop.WindowInteropHelper]::new($script:Win).Handle;[void][PestoNativeCloseProbe]::PostMessage($h,0x10,[IntPtr]::Zero,[IntPtr]::Zero)}
 if($script:tick -eq 3){
  $script:events.Add('after native count='+$script:PestoPanelStack.Count)
  if($script:PestoPanelStack.Count){$script:PestoPanelStack[$script:PestoPanelStack.Count-1].HostedWindow.Close()}
 }
 if($script:tick -eq 5){$s.Stop();$script:Win.Close()}
})
$script:Win.Add_ContentRendered({
 $timer.Start()
 $result=Show-PestoChoiceTable -Title 'Preview' -Rows @([pscustomobject]@{Name='Sample'}) -Columns @(@{Key='Name';Label='Name'})
 $script:events.Add('preview returned tick='+$script:tick)
})
[void]$script:Win.ShowDialog()
$script:events|ConvertTo-Json
