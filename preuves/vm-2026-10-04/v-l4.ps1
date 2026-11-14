# L4 : codes de sortie du lanceur (copies jetables sous C:\PC\L4, jamais C:\PestoTest).
$ErrorActionPreference = 'Continue'
$B = 'C:\PC\L4'
function Copie([string]$n) { $d = Join-Path $B $n; if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }; New-Item -ItemType Directory -Force -Path $d | Out-Null; Copy-Item C:\PestoTest\Pesto.exe $d; Copy-Item C:\PestoTest\wad (Join-Path $d 'wad') -Recurse; $d }
function Code([string]$exe, [string[]]$a) { $p = Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -WindowStyle Hidden; $p.ExitCode }
$r = [ordered]@{}
$d = Copie 'ok'; $r['0 --check-json neuf'] = Code "$d\Pesto.exe" @('--check-json', "$d\c.json")
$r['120 argument inconnu (--unknown --check --quiet)'] = Code "$d\Pesto.exe" @('--unknown', '--check', '--quiet')
$d = Copie 'verrou'; Set-Content -LiteralPath "$d\.pesto-update.lock" -Value 'test'; $r['126 verrou de mise a jour present'] = Code "$d\Pesto.exe" @('--check', '--quiet')
$d = Copie 'absent'; Remove-Item -LiteralPath "$d\wad\Pesto-Join.xaml"; $r['124 ou 125 composant Pesto-Join.xaml absent'] = Code "$d\Pesto.exe" @('--check', '--quiet')
$d = Copie 'modifie'; Add-Content -LiteralPath "$d\wad\Pesto-Names.ps1" -Value '# x'; $r['125 empreinte refusee'] = Code "$d\Pesto.exe" @('--check', '--quiet')
Copy-Item C:\PestoTest\Pesto.exe C:\Pesto-L4-racine.exe; $r['123 lance depuis la racine d un lecteur'] = Code 'C:\Pesto-L4-racine.exe' @('--check', '--quiet'); Remove-Item C:\Pesto-L4-racine.exe -Force
$r.GetEnumerator() | ForEach-Object { '{0} -> code {1}' -f $_.Key, $_.Value }
