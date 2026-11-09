# Tests visibles : deux Pesto côte à côte (C:\PestoDemo et C:\PestoDemo2, même cfg, même registre partagé) proposent
# des noms différents pour la même série.
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$P='t30';$log="$D\$P-deux-pesto.txt"
function Get-PestoDe([string]$Dossier,[int]$Delai=240){
  $fin=(Get-Date).AddSeconds($Delai)
  do{
    foreach($w in [System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)){
      if($w.Current.Name -notmatch 'Pesto 1\.0$'){continue}
      $pp=Get-CimInstance Win32_Process -Filter "ProcessId=$($w.Current.ProcessId)"
      $par=Get-CimInstance Win32_Process -Filter "ProcessId=$($pp.ParentProcessId)" -ErrorAction SilentlyContinue
      if(([string]$pp.CommandLine) -like "*$Dossier\*" -or ([string]$par.ExecutablePath) -like "$Dossier\*"){return $w}
    }
    Start-Sleep -Seconds 3
  }while((Get-Date) -lt $fin)
  $null
}
function Fill($w){
  Click-Id $w 'NavRename'; Start-Sleep -Seconds 2
  Click-Id $w 'BtnReadComputer'; Start-Sleep -Seconds 20
  Set-Combo $w 'CbOrg' 'Département 111301'; Set-Combo $w 'CbSite' 'Paris'; Start-Sleep -Seconds 6
  Set-Combo $w 'CbService' '765'; Set-Combo $w 'CbType' 'Portable'; Start-Sleep -Seconds 4
  $n = Find-Id $w 'CbName'; $v=$null; if($n -and $n.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$v)){return $v.Current.Value}; ''
}
& {
  try {
    $cfg='C:\PestoDemo\wad\cfg.json'; Copy-Item $cfg 'C:\PestoDemo2\wad\cfg.json' -Force; 'cfg identique copié dans C:\PestoDemo2'
    if (-not (Get-PestoDe 'C:\PestoDemo' 5)) { Start-Process C:\PestoDemo\Pesto.exe -WorkingDirectory C:\PestoDemo | Out-Null }
    $a = Get-PestoDe 'C:\PestoDemo'; if (-not $a) { throw 'Pesto A absent' }
    Start-Sleep -Seconds 40; $na = Fill $a; Start-Sleep -Seconds 6; $n = Find-Id $a 'CbName'; $v=$null; if($n -and $n.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$v)){$na=$v.Current.Value}; "Pesto A (C:\PestoDemo) propose : $na"
    Start-Sleep -Seconds 4
    "réservations après A : " + ((Get-ChildItem C:\PestoRegistre\reservations -Filter *.json | ForEach-Object { $_.BaseName }) -join ', ')
    Start-Process C:\PestoDemo2\Pesto.exe -WorkingDirectory C:\PestoDemo2 | Out-Null
    $b = Get-PestoDe 'C:\PestoDemo2'; if (-not $b) { throw 'Pesto B absent' }
    Start-Sleep -Seconds 40; $nb0 = Fill $b; "Pesto B (C:\PestoDemo2), première proposition : $nb0"
    # Le registre partagé réagit en une à deux secondes : relecture du nom retenu par B.
    Start-Sleep -Seconds 10; $n = Find-Id $b 'CbName'; $v=$null; if($n -and $n.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$v)){$nb=$v.Current.Value}else{$nb=$nb0}
    "Pesto B propose finalement : $nb"
    Start-Sleep -Seconds 4
    "réservations après B : " + ((Get-ChildItem C:\PestoRegistre\reservations -Filter *.json | ForEach-Object { "$($_.BaseName) ($((Get-Content $_.FullName -Raw|ConvertFrom-Json).Owner.Substring(0,6)))" }) -join ', ')
    # Côte à côte pour la capture.
    Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool r); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);'
    Add-Type -AssemblyName System.Windows.Forms; $r=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    foreach($x in @(@($a,0),@($b,1))){[void][W.U]::ShowWindow([IntPtr]$x[0].Current.NativeWindowHandle,9);[void][W.U]::MoveWindow([IntPtr]$x[0].Current.NativeWindowHandle,[int]($r.Width/2*$x[1]),0,[int]($r.Width/2),$r.Height,$true)}
    Start-Sleep -Seconds 3; Save-Ecran "$D\$P-1-cote-a-cote.png"
    if ($na -and $nb -and $na -ne $nb) { "RÉSULTAT : noms différents ($na / $nb), aucune collision" } else { "RÉSULTAT : COLLISION ou nom absent ($na / $nb)" }
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\$P-9-echec.png" } catch {} }
} *> $log
