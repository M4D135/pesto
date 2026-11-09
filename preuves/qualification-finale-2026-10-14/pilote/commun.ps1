# Recette finale du 14/10/2026 (build a754ac88) : fonctions communes du pilote, exécuté dans la session de LABO\tech.pesto
# sur PESTO-W11-TEST (tâche planifiée élevée, lancer.ps1). Lecture et gestes par l'automatisation Windows (UIA, SendKeys) ;
# aucun mot de passe n'est saisi par ce pilote.
$ErrorActionPreference = 'Stop'
$R = 'C:\PestoFinal_20261014'
Import-Module "$R\pilot\pilote.psm1" -Force
. "$R\pilot\demo\demo-commun.ps1"
$D = "$R\preuves"   # après demo-commun.ps1, qui définit son propre dossier de captures
[void][IO.Directory]::CreateDirectory($D)

function Start-PestoCopie([string]$Dossier, [int]$Delai = 240) {
    # Lance Pesto.exe de la copie indiquée et attend sa fenêtre principale (initialisation comprise).
    if (Wait-Fenetre 'Pesto 1\.0$' 2) { throw 'Une fenêtre Pesto est déjà ouverte.' }
    $p = Start-Process "$Dossier\Pesto.exe" -WorkingDirectory $Dossier -PassThru
    Write-Host "Pesto lancé depuis $Dossier (pid $($p.Id)), EXE $((Get-FileHash "$Dossier\Pesto.exe").Hash.Substring(0,16))"
    $fin = (Get-Date).AddSeconds($Delai); $w = $null
    while (-not $w -and (Get-Date) -lt $fin) { $w = Wait-Fenetre 'Pesto 1\.0$' 5 }
    if (-not $w) { throw 'Fenêtre principale absente.' }
    Start-Sleep -Seconds 8
    return $w
}

function Stop-PestoFenetre($w) {
    # Fermeture par la croix (WM_CLOSE), comme l'opérateur.
    try { $p = $null; if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$p)) { $p.Close() } } catch {}
    Start-Sleep -Seconds 6
}

function Get-Ids($w, [int]$Max = 600) {
    # Éléments nommés par AutomationId : type, nom, actif, visible, position.
    $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $n = 0
    foreach ($e in $all) {
        $c = $e.Current
        if (-not $c.AutomationId) { continue }
        if ($c.IsOffscreen) { continue }
        $n++; if ($n -gt $Max) { break }
        '{0,-34} {1,-14} actif={2,-5} [{3}] {4}' -f $c.AutomationId, $c.ControlType.ProgrammaticName.Replace('ControlType.', ''), $c.IsEnabled, $c.BoundingRectangle.ToString(), ($c.Name -replace '\s+', ' ').Substring(0, [Math]::Min(90, ($c.Name -replace '\s+', ' ').Length))
    }
}

function Get-Texte($w) {
    # Textes visibles de la fenêtre (TextBlock), pour lire messages et états.
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)) { if (-not $e.Current.IsOffscreen -and $e.Current.Name) { ($e.Current.Name -replace '\s+', ' ') } }
}

function Save-Etape($w, [string]$Nom) {
    # Capture de la fenêtre au premier plan + arbre des éléments, horodatés.
    Set-Premier $w
    Save-Fenetre $w "$D\$Nom.png"
    Get-Ids $w | Set-Content "$D\$Nom.ids.txt" -Encoding UTF8
}

Add-Type -TypeDefinition 'using System.Runtime.InteropServices;public static class PestoRecettePointer{[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);}' -ErrorAction SilentlyContinue

function Set-Max($w) {
    # Fenêtre agrandie par son motif Window (le geste du bouton Agrandir), au premier plan.
    Set-Premier $w
    $p = $null
    if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$p)) { $p.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized) }
    Start-Sleep -Seconds 2
}

function Save-Vue($w, [string]$Nom) {
    # Capture sans infobulle : curseur écarté, fenêtre au premier plan.
    [void][PestoRecettePointer]::SetCursorPos(1919, 1199)
    Start-Sleep -Milliseconds 700
    Save-Etape $w $Nom
}

function Get-Valeur($w, [string]$Id) {
    $e = Find-Id $w $Id; $v = $null
    if ($e -and $e.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$v)) { return [string]$v.Current.Value }
    if ($e) { return [string]$e.Current.Name }
    ''
}

function Wait-Panel($w, [int]$Delai = 180) {
    $fin = (Get-Date).AddSeconds($Delai)
    while ((Get-Date) -lt $fin) { if (Find-Id $w 'PanelBody') { Start-Sleep -Seconds 1; return $true }; Start-Sleep -Milliseconds 800 }
    $false
}

function Get-EtatPoste {
    $cs = Get-CimInstance Win32_ComputerSystem
    $n = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
    $a = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
    "nom actif=$a nom configuré=$n domaine=$($cs.Domain) dans le domaine=$($cs.PartOfDomain)"
}

function Get-RecusRecents([int]$N = 4) {
    Get-ChildItem 'C:\ProgramData\GP\Interventions' -File | Sort-Object LastWriteTime -Descending | Select-Object -First $N | ForEach-Object {
        $r = [IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json
        '{0:HH:mm:ss} {1} {2}->{3} phase={4} code={5} renommage={6} déplacement={7}' -f $_.LastWriteTime, $_.BaseName.Substring(0, 8), $r.Plan.Nom_du_PC, $r.Plan.Nouveau_Nom, $r.Phase, $r.ResultCode, $r.Rename, $r.Move
    }
}

function Set-Formulaire($w, [string]$Site, [string]$Service = '765', [string]$Type = 'Portable') {
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 2
    $c = Find-Id $w 'ChkRemote'; $t = $null
    if ($c -and $c.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$t) -and [string]$t.Current.ToggleState -eq 'On') { $t.Toggle(); Start-Sleep -Seconds 2 }
    Click-Id $w 'BtnReadComputer'
    $fin = (Get-Date).AddSeconds(90); while ((Get-Date) -lt $fin -and -not (Find-Id $w 'CbOrg').Current.IsEnabled) { Start-Sleep -Seconds 1 }
    Start-Sleep -Seconds 3
    Set-Combo $w 'CbOrg' ''
    Set-Combo $w 'CbSite' $Site
    Start-Sleep -Seconds 6
    Set-Combo $w 'CbService' $Service
    Set-Combo $w 'CbType' $Type
    Start-Sleep -Seconds 5
}
