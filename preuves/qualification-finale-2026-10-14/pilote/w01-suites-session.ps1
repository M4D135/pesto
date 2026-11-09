# Suites à jouer dans la session console (bureau réel 1920x1200) : mise en page large (UX) et variantes WPF des bancs 120.
. 'C:\PestoFinal_20261014\pilot\commun.ps1'
$T = "$R\dev\DEV\tests"
Set-Location $T
"utilisateur=$([Security.Principal.WindowsIdentity]::GetCurrent().Name) session=$((Get-Process -Id $PID).SessionId) écran=$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds)"
foreach ($s in @(@('Run-UxTests.ps1', @()), @('Run-Workbench120Tests.ps1', @('-Wpf')), @('Run-BatchNames120Tests.ps1', @('-Wpf')))) {
    "=== $($s[0]) $($s[1] -join ' ')"
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $T $s[0]) @($s[1]) 2>&1 | ForEach-Object { "$_" }
    "code=$LASTEXITCODE"
}
Copy-Item "$T\windows-ui-results.json" "$D\w01-windows-ui-results.json" -Force -ErrorAction SilentlyContinue
