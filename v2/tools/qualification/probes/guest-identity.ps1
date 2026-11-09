# Sonde d'identité et d'environnement de la VM de qualification (lecture seule, bornée, sans secret).
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$roots = @(Get-ChildItem C:\ -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'Pesto*' -or $_.Name -eq 'ADCC-Lab' } |
    ForEach-Object {
        $cfg = Join-Path $_.FullName 'cfg.json'
        $exe = Join-Path $_.FullName 'Pesto.exe'
        $ver = $null
        if (Test-Path -LiteralPath $exe) { try { $ver = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } catch { } }
        [ordered]@{ Path = $_.FullName; HasCfg = (Test-Path -LiteralPath $cfg); ExeVersion = $ver }
    })
$wv2 = @(Get-ChildItem 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
$dotnet = @(foreach ($p in 'C:\Program Files\dotnet\dotnet.exe','C:\Program Files (x86)\dotnet\dotnet.exe') {
    if (Test-Path -LiteralPath $p) { [ordered]@{ Path = $p; ProductVersion = (Get-Item -LiteralPath $p).VersionInfo.ProductVersion } }
})
$result = [ordered]@{
    ComputerName = $env:COMPUTERNAME
    Identity = $id.Name
    IsAdmin = [bool]$admin
    SessionId = (Get-Process -Id $PID).SessionId
    Domain = [string]$cs.Domain
    PartOfDomain = [bool]$cs.PartOfDomain
    Os = ('{0} {1} (build {2})' -f $os.Caption.Trim(), $os.Version, $os.BuildNumber)
    PsVersion = $PSVersionTable.PSVersion.ToString()
    PsPath = (Get-Process -Id $PID).Path
    Utc = (Get-Date).ToUniversalTime().ToString('o')
    LabRoots = $roots
    WebView2FixedVersions = $wv2
    Dotnet = $dotnet
    QualFolderExists = (Test-Path -LiteralPath 'C:\ADCC-Lab\validation\pesto-v2-20261024')
}
