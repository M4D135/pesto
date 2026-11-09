#requires -Version 5.1
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-Collections.ps1','Pesto-Preparation.ps1','Pesto-Workbench.ps1','Pesto-Core.ps1','Pesto-Contracts.ps1','Pesto-Operations.ps1','Pesto-Policy.ps1','Pesto-Interventions.ps1')){$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$t,[ref]$e);if($e.Count){throw ($file+': '+($e.Message -join '; '))};foreach($f in $ast.EndBlock.Statements){if($f -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$f.Name]=$f.Extent.Text}}}
# La fermeture est fermée par calcul, pas par liste : une fonction ajoutée au moteur et appelée par un
# cas ne peut plus manquer silencieusement à l'exécution (Get-PestoNamingLayout l'a fait en ac9e657).
$pending=[Collections.Generic.List[string]]::new()
foreach($name in @('ConvertTo-PestoSavedViews','Read-PestoSavedViews','Save-PestoSavedViews','Set-PestoColumnPreset','Get-PestoQueueGroupedRows','ConvertTo-PestoDynamicCollections','Read-PestoDynamicCollections','Save-PestoDynamicCollections','Get-PestoDynamicMembers','Compare-PestoDynamicMembers','ConvertTo-PestoPreparationBundle','Get-PestoPreparationCompatibility','ConvertTo-PestoPreparation','Read-PestoPreparations','ConvertTo-PestoDraftCollection','ConvertTo-PestoDraft','Assert-PestoClosedObject','Test-PestoDnsName','Test-PestoComputerName','ConvertTo-PestoNameParts','ConvertTo-PestoSearchText','Test-PestoOUPath','New-QueueTable','Get-PestoStableHash','Get-PestoGridRowId','New-PestoGridRowCollection','Update-PestoGridRows','Sync-Grid')){$pending.Add($name)}
$loaded=@{}
while($pending.Count){
    $name=$pending[0];$pending.RemoveAt(0)
    if($loaded.ContainsKey($name)){continue}
    if(-not$defs.ContainsKey($name)){throw ('Definition absente pour une fonction demandee par la suite : '+$name)}
    . ([scriptblock]::Create($defs[$name]));$loaded[$name]=$true
    foreach($call in [regex]::Matches($defs[$name],'[A-Za-z][A-Za-z0-9]*-[A-Za-z][A-Za-z0-9_]*')){if($defs.ContainsKey($call.Value) -and -not$loaded.ContainsKey($call.Value)){$pending.Add($call.Value)}}
}
function Assert {param($Value,[string]$Message='Assertion failed');if(-not$Value){throw $Message}}
function Case {param($Name,[scriptblock]$Test);try{&$Test;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Reject {param([scriptblock]$Test);$caught=$false;try{&$Test|Out-Null}catch{$caught=$true};Assert $caught}
function New-View {[pscustomobject]@{Name='Équipe';Table='queue';Search='ticket';Filter='Toute la file';Sort=@([pscustomobject]@{Property='Nom_du_PC';Direction='Descending'})}}
function New-Collection {[pscustomobject]@{Name='Lyon';Domain='lab.test';ConfigStamp=('a'*64);Query=[pscustomobject]@{Search='';Site='LY';Service='INF';Type='P'};Baseline=@();ObservedUtc='2026-10-13T10:00:00Z'}}
Case 'Views accept filter and sort only' {$r=@(ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@((New-View))}));Assert ($r.Count -eq 1 -and $r[0].Sort[0].Direction -eq 'Descending')}
Case 'View payload rejects execution consent and arbitrary expressions' {$v=New-View;$v|Add-Member NoteProperty Traiter $true;Reject{ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($v)})};$v=New-View;$v.Sort[0].Property='X;Remove-Item';Reject{ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($v)})}}
Case 'Duplicate views in same table rejected but same name across tables allowed' {$a=New-View;$b=New-View;Reject{ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($a,$b)})};$b.Table='names';Assert (@(ConvertTo-PestoSavedViews ([pscustomobject]@{Schema=1;Views=@($a,$b)})).Count -eq 2)}
Case 'Demo views persist only in memory with unchanged sort' {$script:GUI=$true;Save-PestoSavedViews @((New-View));$r=@(Read-PestoSavedViews);Assert ($r.Count -eq 1 -and $r[0].Search -eq 'ticket')}
Case 'Essential preset preserves fixed identity columns and diagnostic restores all' {$grid=[pscustomobject]@{Columns=@(1..5|%{[pscustomobject]@{Visibility='Visible'}})};$script:PestoTables=@{queue=[pscustomobject]@{Grid=$grid;Fixed=2;Keys=@('_column0','Statut','Nom_du_PC','Message','Reference')}};Set-PestoColumnPreset queue Essential;Assert ($grid.Columns[0].Visibility -eq 'Visible' -and $grid.Columns[3].Visibility -eq 'Collapsed');Set-PestoColumnPreset queue Diagnostic;Assert (@($grid.Columns|?{$_.Visibility -ne 'Visible'}).Count -eq 0)}
Case 'Grouping preserves actual queue order and selections' {$t=New-QueueTable;foreach($site in @('Z','A','Z')){$r=$t.NewRow();$r.Site=$site;$r.Nom_du_PC='PC'+$t.Rows.Count;$r.Traiter=$true;[void]$t.Rows.Add($r)};$r=@(Get-PestoQueueGroupedRows $t Site|Sort-Object Groupe,Ordre);Assert ($r[0].Ordre -eq 2 -and $t.Rows[0].Site -ceq 'Z' -and $t.Rows[0].Traiter)}
Case 'Collection schema rejects stored commands and identity-less baseline' {$c=New-Collection;$c|Add-Member NoteProperty Execute $true;Reject{ConvertTo-PestoDynamicCollections ([pscustomobject]@{Schema=1;Collections=@($c)})};$c=New-Collection;$c.Baseline=@([pscustomobject]@{Guid='';Name='PC1';DN=''});Reject{ConvertTo-PestoDynamicCollections ([pscustomobject]@{Schema=1;Collections=@($c)})}}
$guid1=[Guid]::NewGuid().ToString('D');$guid2=[Guid]::NewGuid().ToString('D');$pcs=@([pscustomobject]@{Name='P123456LYINF001';ObjectGUID=$guid1;DistinguishedName='CN=PC,OU=Lab,DC=lab,DC=test'},[pscustomobject]@{Name='S123456LYINF002';ObjectGUID=$guid2;DistinguishedName='CN=PC2,OU=Lab,DC=lab,DC=test'})
Case 'Dynamic collection ANDs type site service and text' {$r=@(Get-PestoDynamicMembers (New-Collection).Query $pcs '123456');Assert ($r.Count -eq 1 -and $r[0].Guid -ceq $guid1)}
Case 'Missing AD identity refuses the whole collection instead of matching by name' {$pc=$pcs[0].PSObject.Copy();$pc.ObjectGUID='';Reject{Get-PestoDynamicMembers (New-Collection).Query @($pc) '123456'}}
Case 'Member evaluation never reads AD and every saved member has stable identity' {$s=$defs['Get-PestoDynamicMembers'];Assert ($s -notmatch 'Get-AD|Get-Cim|Invoke-Command');$c=New-Collection;$c.Baseline=@(Get-PestoDynamicMembers $c.Query $pcs '123456');Assert (@(ConvertTo-PestoDynamicCollections ([pscustomobject]@{Schema=1;Collections=@($c)})).Count -eq 1)}
Case 'Delta distinguishes rename same GUID from removal and addition' {$before=@([pscustomobject]@{Guid=$guid1;Name='OLD';DN='OU=A'},[pscustomobject]@{Guid=$guid2;Name='REMOVED';DN='OU=A'});$after=@([pscustomobject]@{Guid=$guid1;Name='NEW';DN='OU=A'},[pscustomobject]@{Guid=[Guid]::NewGuid().ToString();Name='ADDED';DN='OU=A'});$r=@(Compare-PestoDynamicMembers $before $after);Assert ($r.Count -eq 3 -and @($r|?{$_.Etat -eq 'Nom ou emplacement changé'}).Count -eq 1 -and @($r|?{$_.Etat -eq 'Absent du périmètre'}).Count -eq 1)}
Case 'Collections memory storage roundtrips exact query and domain' {$script:GUI=$true;Save-PestoDynamicCollections @((New-Collection));$r=@(Read-PestoDynamicCollections);Assert ($r.Count -eq 1 -and $r[0].Domain -ceq 'lab.test' -and $r[0].Query.Site -ceq 'LY')}
Case 'Collection freeze checks both inventory and config generation before planner' {$s=$defs['Invoke-PestoCollectionTool'];Assert ($s.Contains('Show-PestoBulkPlanner -SourceNames @($members.Name)') -and $s.Contains('$inventory -cne [string]$script:InventoryUtc') -and $s.Contains('$members.Count -gt $limit') -and $s -notmatch 'Run-Queue|Start-PestoDirectOperation')}
$f=[pscustomobject]@{Name='Site';Value=[pscustomobject]@{Schema=1;Domain='lab.test';ConfigStamp=('a'*64);Org='ORG';Site='Lyon';Service='INF';Type='Portable'}}
Case 'Shared preparation bundle rejects arbitrary extra root or favorite fields' {$bad=[pscustomobject]@{Schema=1;Favorites=@($f);Drafts=@();Password='secret'};Reject{ConvertTo-PestoPreparationBundle $bad};$r=ConvertTo-PestoPreparationBundle ([pscustomobject]@{Schema=1;Favorites=@($f);Drafts=@()});Assert ($r.Favorites.Count -eq 1)}
Case 'Sharing compatibility is explicit and never rebases foreign config' {$bundle=ConvertTo-PestoPreparationBundle ([pscustomobject]@{Schema=1;Favorites=@($f);Drafts=@()});$r=@(Get-PestoPreparationCompatibility $bundle 'other.test' ('a'*64));Assert (-not$r[0].Compatible -and $r[0].Item.Value.Domain -ceq 'lab.test');Assert (@(Get-PestoPreparationCompatibility $bundle 'lab.test' ('a'*64))[0].Compatible)}
Case 'Bundle import requires preview and confirmation before writing and does not apply form' {$s=$defs['Invoke-PestoPreparationExchange'];Assert ($s.IndexOf('Compatibilité des préparations') -lt $s.IndexOf("-AcceptText 'Importer ces préparations'"));Assert ($s.IndexOf("-AcceptText 'Importer ces préparations'") -lt $s.IndexOf("Set-PestoAppearanceValue -Name 'Preparation'"));Assert ($s -notmatch 'Select-PCName|Run-Queue|\.IsChecked\s*=')}
Case 'Share buttons are initialized once, not on every save' {Assert ($defs['Initialize-PestoPreparationUI'].Contains('PrepImportCollection') -and -not$defs['Save-PestoPreparations'].Contains('Add_Click'))}
Case 'Saved name sorting is reapplied after asynchronous projection' {Assert ($defs['Complete-PestoNamesProjection'].Contains('$script:PestoNamesViewSort') -and $defs['Set-PestoSavedView'].Contains('Update-NameGrid'))}
[xml]$shell=Get-Content (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
Case 'Every collection/view/share action is exposed in XAML' {foreach($n in @('QueueViews','NmViews','NmSaveCollection','QueueCollection','PrepImportCollection','PrepExportCollection')){Assert ($null -ne $shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$n+'"]')) $n}}
Case 'Favorite storage roundtrips JSON integer schema without using registry' {$script:GUI=$true;$script:PestoPrepMemory=([pscustomobject]@{Schema=2;Favorites=@($f)}|ConvertTo-Json -Depth 6);$r=@(Read-PestoPreparations);Assert ($r.Count -eq 1 -and $r[0].Value.Site -ceq 'Lyon')}
Case 'Preparation schema rejects coerced strings and booleans' {foreach($schema in @('1',$true)){Reject{ConvertTo-PestoPreparationBundle ([pscustomobject]@{Schema=$schema;Favorites=@($f);Drafts=@()})};$bad=$f.Value.PSObject.Copy();$bad.Schema=$schema;Reject{ConvertTo-PestoPreparation $bad}}}
$script:LedgerNotifications=[Collections.Generic.List[object]]::new();$script:FakeGridSource=$null;$script:FakeGridSort=[Collections.Generic.List[object]]::new()
function New-LedgerRow {param([string]$Id,[string]$Label='En cours',[string]$Phase='Running',[string]$Task='Pending')
    [pscustomobject]@{RowId=$Id;StatusLabel=$Label;Receipt=[pscustomobject]@{Phase=$Phase;Tasks=@([pscustomobject]@{Phase=$Task})}}}
function New-FakeLedgerGrid {
    $script:FakeGridSource=$null;$script:FakeGridSort=[Collections.Generic.List[object]]::new();$script:LedgerHandler=$null
    $grid=[pscustomobject]@{SelectedItem=$null}
    [void]($grid|Add-Member -NotePropertyName Items -NotePropertyValue ([pscustomobject]@{SortDescriptions=$script:FakeGridSort}) -Force)
    # Le getter doit emettre la collection elle-meme, pas son enumeration : sans l'operateur virgule,
    # la ScriptProperty rend un Object[] et le helper ne reconnait plus la source observable.
    [void]($grid|Add-Member -MemberType ScriptProperty -Name ItemsSource -Value {,$script:FakeGridSource} -SecondValue {$script:FakeGridSource=$args[0];$script:FakeGridSort.Clear()} -Force)
    return $grid
}
function Watch-LedgerNotifications {
    # Un seul abonement a la fois : se re-abonner sans se desabonner cumulerait les handlers et
    # multiplierait le nombre de notifications relevees, ce qui ferait echouer le contrat de count.
    if($null -ne $script:LedgerHandler){$script:FakeGridSource.remove_CollectionChanged($script:LedgerHandler)}
    $script:LedgerHandler=[System.Collections.Specialized.NotifyCollectionChangedEventHandler]{param($s,$e);[void]$script:LedgerNotifications.Add([string]$e.Action)}
    [void]$script:LedgerNotifications.Clear()
    $script:FakeGridSource.add_CollectionChanged($script:LedgerHandler)
}
Case 'Ledger bind publishes an observable row collection instead of a replaced array' {
    $grid=New-FakeLedgerGrid;$r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId'
    Assert ($r.Rebound -and $grid.ItemsSource.Count -eq 2 -and $grid.ItemsSource -is [Collections.Specialized.INotifyCollectionChanged]) 'Premiere liaison non publiee.'
}
Case 'Re-applying the same projected rows notifies no row at all' {
    $grid=New-FakeLedgerGrid;$rows=@((New-LedgerRow 'a'),(New-LedgerRow 'b'));[void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId')
    Watch-LedgerNotifications;$r=Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId'
    Assert ($r.Operations -eq 0 -and $r.Unchanged -eq 2 -and $script:LedgerNotifications.Count -eq 0) 'Des lignes inchangees ont notifie le tableau.'
}
Case 'A re-projected row whose content did not change keeps the rendered instance' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId')
    $rendered=$grid.ItemsSource[0];Watch-LedgerNotifications
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId'
    Assert ($r.Replaced -eq 0 -and [object]::ReferenceEquals($grid.ItemsSource[0],$rendered) -and $script:LedgerNotifications.Count -eq 0) 'Une ligne a ete recreee sans changement de contenu.'
}
Case 'Only the row whose receipt changed is replaced and notified' {
    $grid=New-FakeLedgerGrid;$rows=@((New-LedgerRow 'a'),(New-LedgerRow 'b'));[void](Update-PestoGridRows -Grid $grid -Rows $rows -IdProperty 'RowId')
    $kept=$grid.ItemsSource[0];Watch-LedgerNotifications
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b' 'Verifie')) -IdProperty 'RowId'
    Assert ($r.Replaced -eq 1 -and $r.Operations -eq 1) 'Le nombre de lignes remplacees depasse la modification reelle.'
    Assert ($script:LedgerNotifications.Count -eq 1 -and $script:LedgerNotifications[0] -ceq 'Replace') 'La notification rendue nest pas un remplacement unique.'
    Assert ([object]::ReferenceEquals($grid.ItemsSource[0],$kept) -and -not [object]::ReferenceEquals($grid.ItemsSource[1],$rows[1])) 'Une ligne inchangee a ete recreee.'
}
Case 'A change only the row actions read still forces the row to be replaced' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a' 'Verifie' 'Verified' 'Finished')) -IdProperty 'RowId')
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a' 'Verifie' 'Verified' 'Deleted')) -IdProperty 'RowId'
    Assert ($r.Replaced -eq 1) 'Une tache modifiee a laisse la ligne rendue telle quelle.'
}
Case 'Selection follows the receipt identity across a replaced row' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId')
    $grid.SelectedItem=$grid.ItemsSource[1]
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b' 'Verifie')) -IdProperty 'RowId')
    Assert ($null -ne $grid.SelectedItem -and $grid.SelectedItem.RowId -ceq 'b' -and [object]::ReferenceEquals($grid.SelectedItem,$grid.ItemsSource[1])) 'La selection a ete perdue alors que le recu est toujours affiche.'
}
Case 'Selection is cleared when the selected receipt leaves the page' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId')
    $grid.SelectedItem=$grid.ItemsSource[0]
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'c')) -IdProperty 'RowId')
    Assert ($null -eq $grid.SelectedItem -and $grid.ItemsSource.Count -eq 1) 'La selection survit a la disparition du recu.'
}
Case 'Sort carried by the view is restored when a full rebind drops it' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a')) -IdProperty 'RowId')
    $script:FakeGridSort.Add([pscustomobject]@{PropertyName='UpdatedLocal';Direction='Descending'})
    $script:FakeGridSort.Add([pscustomobject]@{PropertyName='Computer';Direction='Ascending'})
    $script:FakeGridSource=@((New-LedgerRow 'a'))
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a')) -IdProperty 'RowId'
    Assert ($r.Rebound) 'Repli sur liaison complete non declenche.'
    Assert ($script:FakeGridSort.Count -eq 2 -and $script:FakeGridSort[0].PropertyName -ceq 'UpdatedLocal' -and $script:FakeGridSort[1].Direction -ceq 'Ascending') 'Le tri porte par la vue na pas etre restitue.'
}
Case 'In-place update leaves the sort carried by the view untouched' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b')) -IdProperty 'RowId')
    $sort=[pscustomobject]@{PropertyName='UpdatedLocal';Direction='Descending'};$script:FakeGridSort.Add($sort)
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b' 'Verifie')) -IdProperty 'RowId')
    Assert ($script:FakeGridSort.Count -eq 1 -and [object]::ReferenceEquals($script:FakeGridSort[0],$sort)) 'Le tri a ete remanie pendant une mise a jour en place.'
}
Case 'Structural churn beyond the bound falls back to one full rebind' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b'),(New-LedgerRow 'c')) -IdProperty 'RowId')
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'x'),(New-LedgerRow 'y'),(New-LedgerRow 'z')) -IdProperty 'RowId' -MaximumInPlaceOperations 2
    Assert ($r.Rebound -and $grid.ItemsSource.Count -eq 3 -and $grid.ItemsSource[0].RowId -ceq 'x') 'Le repli sur liaison complete na pas ete pris.'
}
Case 'Inserted and removed receipts keep the requested page order' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'b'),(New-LedgerRow 'c')) -IdProperty 'RowId')
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'c'),(New-LedgerRow 'd'),(New-LedgerRow 'a')) -IdProperty 'RowId')
    Assert ((@($grid.ItemsSource|ForEach-Object{$_.RowId}) -join '') -ceq 'cda') 'Ordre de page non respecte.'
}
Case 'Missing or duplicated row identity is refused instead of guessed' {
    $grid=New-FakeLedgerGrid
    Reject {Update-PestoGridRows -Grid $grid -Rows @([pscustomobject]@{StatusLabel='sans identite'}) -IdProperty 'RowId'}
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a')) -IdProperty 'RowId')
    Reject {Update-PestoGridRows -Grid $grid -Rows @((New-LedgerRow 'a'),(New-LedgerRow 'a')) -IdProperty 'RowId'}
}
function New-NamesRow {param([string]$Name,[string]$State='Libre dans l''inventaire',[bool]$InAD=$false)
    [pscustomobject]@{Nom=$Name;Type='Portable';Site='LY';Equipe='INF';Num='001';Statut=$State;InAD=$InAD;Reserved=$false;OwnReservation=$false}}
Case 'Names re-projection replaces only the row whose availability changed' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF001'),(New-NamesRow 'PLYLINF002')) -IdProperty 'Nom')
    $kept=$grid.ItemsSource[0];Watch-LedgerNotifications
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF001'),(New-NamesRow 'PLYLINF002' 'Occupe dans AD' $true)) -IdProperty 'Nom'
    Assert ($r.Replaced -eq 1 -and $r.Operations -eq 1 -and $script:LedgerNotifications.Count -eq 1) 'La page de noms a notifie plus que la ligne reellement changee.'
    Assert ([object]::ReferenceEquals($grid.ItemsSource[0],$kept)) 'Une ligne de noms inchangee a ete recreee.'
}
Case 'Names selection follows the candidate name across a re-projected page' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF001'),(New-NamesRow 'PLYLINF002')) -IdProperty 'Nom')
    $grid.SelectedItem=$grid.ItemsSource[1]
    [void](Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF001'),(New-NamesRow 'PLYLINF002' 'Occupe dans AD' $true)) -IdProperty 'Nom')
    Assert ($null -ne $grid.SelectedItem -and $grid.SelectedItem.Nom -ceq 'PLYLINF002') 'La selection de nom a ete perdue apres reprojection.'
}
Case 'A names page change falls back to one full rebind' {
    $grid=New-FakeLedgerGrid;[void](Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF001'),(New-NamesRow 'PLYLINF002'),(New-NamesRow 'PLYLINF003')) -IdProperty 'Nom')
    $r=Update-PestoGridRows -Grid $grid -Rows @((New-NamesRow 'PLYLINF004'),(New-NamesRow 'PLYLINF005'),(New-NamesRow 'PLYLINF006')) -IdProperty 'Nom' -MaximumInPlaceOperations 2
    Assert ($r.Rebound -and $grid.ItemsSource.Count -eq 3 -and $grid.ItemsSource[0].Nom -ceq 'PLYLINF004') 'Le changement de page de noms na pas pris le repli sur liaison complete.'
}
Case 'The ledger page updates its rows in place instead of rebinding the whole grid' {
    Assert ($defs['Update-PestoInterventionPage'].Contains('Update-PestoGridRows -Grid $ui.Grid') -and $defs['Update-PestoInterventionPage'] -notmatch '\$ui\.Grid\.ItemsSource\s*=') 'Le registre relie encore tout le tableau a chaque page.'
}Case 'The names page updates its rows in place instead of rebinding the whole grid' {
    Assert ($defs['Complete-PestoNamesProjection'].Contains('Update-PestoGridRows -Grid $NmGrid') -and $defs['Complete-PestoNamesProjection'] -notmatch '\$NmGrid\.ItemsSource\s*=\s*\$Result') 'La page de noms relie encore tout le tableau a chaque calcul.'
}
function New-FakeQueueGrid {
    # Le pump de la file appelle Sync-Grid sur chaque ligne traitee : la grille factice releve les
    # Refresh complets forces et la fermeture d'edition, pour que le contrat incrmental de la file
    # soit asserte au meme titre que celui du registre et de la page des noms.
    $script:QueueRefreshes=0;$script:QueueEditsClosed=0;$script:QueueGridSource=$null
    $grid=[pscustomobject]@{}
    [void]($grid|Add-Member -MemberType ScriptMethod -Name CommitEdit -Value {$script:QueueEditsClosed++;'Compiling'} -Force)
    [void]($grid|Add-Member -MemberType ScriptMethod -Name CancelEdit -Value {$script:QueueEditsClosed++} -Force)
    [void]($grid|Add-Member -MemberType ScriptProperty -Name ItemsSource -Value {,$script:QueueGridSource} -SecondValue {$script:QueueGridSource=$args[0]} -Force)
    $items=[pscustomobject]@{}
    [void]($items|Add-Member -MemberType ScriptMethod -Name Refresh -Value {$script:QueueRefreshes++} -Force)
    [void]($grid|Add-Member -NotePropertyName Items -NotePropertyValue $items -Force)
    return $grid
}
Case 'The queue pump no longer force-refreshes its DataView-bound grid' {
    $grid=New-FakeQueueGrid
    $t=New-QueueTable;$r=$t.NewRow();$r.Nom_du_PC='PC1';[void]$t.Rows.Add($r)
    $script:QueueGridSource=$t.DefaultView
    $script:Grid=$grid
    Sync-Grid
    Assert ($script:QueueRefreshes -eq 0) 'Sync-Grid force encore un Refresh complet sur la liaison DataView de la file.'
    Assert ($script:QueueEditsClosed -eq 2) 'Sync-Grid ne ferme plus l edition de cellule avant de rendre la grille.'
}
Case 'A queue status write notifies its own cell and nothing else' {
    # Le contrat du pump : ecrire le statut d'une ligne dans la DataRow doit publier la cellule,
    # pas recrer les conteneurs de toute la file. C'est la derniere liaison qui forcait encore
    # le rafraichissement complet, ligne apres ligne, pendant l'execution.
    $grid=New-FakeQueueGrid
    $t=New-QueueTable;$r=$t.NewRow();$r.Nom_du_PC='PC1';[void]$t.Rows.Add($r)
    $view=$t.DefaultView;$script:QueueGridSource=$view
    $script:Grid=$grid
    $notifs=[Collections.Generic.List[string]]::new()
    $handler=[System.ComponentModel.ListChangedEventHandler]{param($s,$e);$p=if($null -ne $e.PropertyDescriptor){$e.PropertyDescriptor.Name}else{''};[void]$notifs.Add([string]$e.ListChangedType+':'+$p)}
    # C'est le contrat cellule par cellule que WPF consomme sur une DataView : ListChanged avec le
    # descripteur de la colonne changee, releve ici par l'interface de liaison elle-meme.
    $bl=[System.ComponentModel.IBindingList]$view
    [void]$bl.add_ListChanged($handler)
    try{
        $t.Rows[0].Statut='EN COURS'
        Sync-Grid
        Assert (@($notifs|Where-Object{$_ -ceq 'ItemChanged:Statut'}).Count -eq 1) ('Notifications de cellule relevees : '+($notifs -join ', '))
        Assert ($script:QueueRefreshes -eq 0) 'Le pump force encore la recreation de tous les conteneurs de ligne.'
    }finally{$bl.remove_ListChanged($handler)}
}
Case 'A silent binding still gets the full refresh fallback' {
    $grid=New-FakeQueueGrid
    $script:QueueGridSource=@([pscustomobject]@{Nom_du_PC='PC1'})
    $script:Grid=$grid
    Sync-Grid
    Assert ($script:QueueRefreshes -eq 1) 'Le repli sur Refresh complet a disparu pour les liaisons qui ne notifient rien.'
}
function New-BulkLedgerRows {param([int]$Count)
    $rows=[object[]]::new($Count)
    for($i=0;$i -lt $Count;$i++){$rows[$i]=New-LedgerRow ('r'+$i.ToString('D6'))}
    return ,$rows
}
function New-BulkProjection {param([object[]]$Rendered,[int]$Changed,[switch]$Fresh)
    # Les lignes non choisies sont reprojetees par la MEME instance : c'est ce qui dispense de l'empreinte.
    $next=[object[]]::new($Rendered.Count)
    for($i=0;$i -lt $Rendered.Count;$i++){$next[$i]=$Rendered[$i]}
    $stride=[Math]::Max(1,[int]($Rendered.Count/$Changed))
    for($k=0;$k -lt $Changed;$k++){
        $index=($k*$stride)%$Rendered.Count;$row=$Rendered[$index]
        $next[$index]=[pscustomobject]@{RowId=$row.RowId;StatusLabel=$row.StatusLabel+'.';Receipt=[pscustomobject]@{Phase=$row.Receipt.Phase;Tasks=$row.Receipt.Tasks}}
    }
    # Second consommateur branche : Invoke-PestoBuildNamesView fabrique une instance neuve pour chaque
    # ligne, y compris quand rien n'a change. Son profil de cout n'est pas celui du registre.
    if($Fresh){for($i=0;$i -lt $Rendered.Count;$i++){if([object]::ReferenceEquals($next[$i],$Rendered[$i])){$next[$i]=New-LedgerRow $Rendered[$i].RowId $Rendered[$i].StatusLabel}}}
    return ,$next
}
Case 'At a thousand rows only the changed rows are replaced and notified' {
    $grid=New-FakeLedgerGrid
    [void](Update-PestoGridRows -Grid $grid -Rows (New-BulkLedgerRows 1000) -IdProperty 'RowId')
    foreach($changed in @(1,10,100)){
        $rendered=@($grid.ItemsSource);$next=New-BulkProjection -Rendered $rendered -Changed $changed
        Watch-LedgerNotifications
        $r=Update-PestoGridRows -Grid $grid -Rows $next -IdProperty 'RowId'
        Assert (-not $r.Rebound) ('Repli sur liaison complete a '+$changed+' changement(s) sur 1000 lignes.')
        Assert ($r.Replaced -eq $changed) ('Lignes remplacees '+$r.Replaced+' au lieu de '+$changed+'.')
        Assert ($r.Unchanged -eq ($rendered.Count-$changed)) ('Lignes conservees '+$r.Unchanged+' au lieu de '+($rendered.Count-$changed)+'.')
        Assert ($script:LedgerNotifications.Count -eq $changed) ('Notifications publiees '+$script:LedgerNotifications.Count+' au lieu de '+$changed+'.')
        $recreated=@(for($i=0;$i -lt $rendered.Count;$i++){if([object]::ReferenceEquals($grid.ItemsSource[$i],$rendered[$i])){0}else{1}})
        Assert (@($recreated|Where-Object{$_ -eq 1}).Count -eq $changed) ('Des lignes inchangees ont ete recrees a '+$changed+' changement(s).')
    }
}
Case 'The row fingerprint is computed only for rows projected again' {
    $grid=New-FakeLedgerGrid
    [void](Update-PestoGridRows -Grid $grid -Rows (New-BulkLedgerRows 500) -IdProperty 'RowId')
    $script:PestoHashOriginal=(Get-Command -Name Get-PestoStableHash -CommandType Function).ScriptBlock
    $wrapper=[scriptblock]::Create('param($Value)$script:PestoHashCalls++;return (& $script:PestoHashOriginal $Value)')
    try{
        Set-Item -LiteralPath 'function:\Get-PestoStableHash' -Value $wrapper
        $next=New-BulkProjection -Rendered @($grid.ItemsSource) -Changed 5
        $script:PestoHashCalls=0
        $r=Update-PestoGridRows -Grid $grid -Rows $next -IdProperty 'RowId'
        Assert ($r.Replaced -eq 5) ('Lignes remplacees '+$r.Replaced+' au lieu de 5.')
        Assert ($script:PestoHashCalls -eq 5) ('Empreintes recalculees '+$script:PestoHashCalls+' au lieu de 5 : le cache de la collection liee n est pas reuse.')
    }finally{
        Set-Item -LiteralPath 'function:\Get-PestoStableHash' -Value $script:PestoHashOriginal
    }
}
Case 'A projection reads each row identity once per side and not once per phase' {
    # Le contrat de cout du chemin livre ne porte pas que sur les notifications : si l'identite etait
    # relue a chaque phase, la page paierait son prix complet meme pour une seule ligne changee, ce qui
    # etait le cas (sept lectures par ligne affichee) et ne se voyait dans aucun des cas precedents.
    $grid=New-FakeLedgerGrid
    [void](Update-PestoGridRows -Grid $grid -Rows (New-BulkLedgerRows 1000) -IdProperty 'RowId')
    $rendered=@($grid.ItemsSource);$next=New-BulkProjection -Rendered $rendered -Changed 1
    $script:PestoRowIdOriginal=(Get-Command -Name Get-PestoGridRowId -CommandType Function).ScriptBlock
    $wrapper=[scriptblock]::Create('param($Row,$IdProperty)$script:PestoRowIdCalls++;return (& $script:PestoRowIdOriginal -Row $Row -IdProperty $IdProperty)')
    try{
        Set-Item -LiteralPath 'function:\Get-PestoGridRowId' -Value $wrapper
        $script:PestoRowIdCalls=0
        $r=Update-PestoGridRows -Grid $grid -Rows $next -IdProperty 'RowId'
        Assert (-not $r.Rebound -and $r.Replaced -eq 1) ('Chemin en place attendu : Rebound='+$r.Rebound+' Replaced='+$r.Replaced)
        Assert ($script:PestoRowIdCalls -eq (2*$rendered.Count)) ('Lectures d identite '+$script:PestoRowIdCalls+' au lieu de '+(2*$rendered.Count)+' : l identite est relue par phase et la page paye son prix complet.')
    }finally{
        Set-Item -LiteralPath 'function:\Get-PestoGridRowId' -Value $script:PestoRowIdOriginal
    }
}
$script:PestoGridMeasure=[Collections.Generic.List[object]]::new()
Case 'In-place update and full rebind are measured at the same volume' {
    # Cout PowerShell du chemin lui-meme (construction de collection, notifications) : le frame time WPF
    # reste mesure par tools/Measure-PestoWpfProjection.ps1 sous Windows PowerShell 5.1 en STA.
    # Les deux profils branches sont releves : le registre rend les instances deja affichees, la page
    # de noms en fabrique de neuves, et le cout du chemin livre n'est pas le meme des deux cotes.
    foreach($volume in @(250,1000)){
        foreach($changed in @(1,100)){
            foreach($profile in @('ReusedInstances','FreshInstances')){
                $grid=New-FakeLedgerGrid
                [void](Update-PestoGridRows -Grid $grid -Rows (New-BulkLedgerRows $volume) -IdProperty 'RowId')
                $next=New-BulkProjection -Rendered @($grid.ItemsSource) -Changed $changed -Fresh:($profile -ceq 'FreshInstances')
                $clock=[Diagnostics.Stopwatch]::StartNew()
                $inplace=Update-PestoGridRows -Grid $grid -Rows $next -IdProperty 'RowId'
                $clock.Stop();$inPlaceMs=$clock.Elapsed.TotalMilliseconds
                $clock=[Diagnostics.Stopwatch]::StartNew()
                $grid.ItemsSource=New-PestoGridRowCollection -Rows @($next)
                $clock.Stop();$rebindMs=$clock.Elapsed.TotalMilliseconds
                Assert ($inplace.Replaced -eq $changed -and $grid.ItemsSource.Count -eq $volume) 'Mesure non representative.'
                [void]$script:PestoGridMeasure.Add([pscustomobject]@{Rows=$volume;Changed=$changed;Profile=$profile;Notifications=$inplace.Replaced;InPlaceMs=[Math]::Round($inPlaceMs,3);RebindCollectionMs=[Math]::Round($rebindMs,3)})
            }
        }
    }
}

$failed=@($results|Where-Object{-not $_.Passed});$report=[pscustomobject]@{Suite='Collections120';Passed=$results.Count-$failed.Count;Failed=$failed.Count;GridRowUpdate=$script:PestoGridMeasure.ToArray();Cases=$results};if($ReportPath){[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))};$failed|%{Write-Output ($_.Name+': '+$_.Error)};Write-Output ("Collections120 : {0}/{1} PASS" -f $report.Passed,$results.Count);if($failed.Count){exit 1}
