# Vérification de la copie WebView2 Fixed Version présente + inventaire borné des racines V1 de référence (lecture seule).
$wv2Root = 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application'
$wv2 = @()
foreach ($v in (Get-ChildItem $wv2Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.' })) {
    $exe = Join-Path $v.FullName 'msedgewebview2.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $wv2 += [ordered]@{ Version = $v.Name; Exists = $false }; continue }
    $item = Get-Item -LiteralPath $exe
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    $files = @(Get-ChildItem $v.FullName -Recurse -File -ErrorAction SilentlyContinue)
    $wv2 += [ordered]@{
        Version = $v.Name
        Exists = $true
        FileVersion = $item.VersionInfo.FileVersion
        ProductVersion = $item.VersionInfo.ProductVersion
        SignatureStatus = [string]$sig.Status
        StatusMessage = $sig.StatusMessage
        SignerSubject = [string]$sig.SignerCertificate.Subject
        SignerIssuer = [string]$sig.SignerCertificate.Issuer
        Thumbprint = [string]$sig.SignerCertificate.Thumbprint
        FileCount = $files.Count
        TotalBytes = [int64](($files | Measure-Object Length -Sum).Sum)
        ExeSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    }
}
$refRoots = 'C:\PestoQual_20261018','C:\PestoQualPersonal_20261018','C:\PestoVerify_20261018','C:\PestoVM_20261016'
$refs = @()
foreach ($r in $refRoots) {
    if (-not (Test-Path -LiteralPath $r)) { $refs += [ordered]@{ Root = $r; Exists = $false }; continue }
    $cfgs = @(Get-ChildItem $r -Recurse -Filter cfg.json -File -ErrorAction SilentlyContinue | Select-Object -First 4 | ForEach-Object { $_.FullName })
    $exe = Join-Path $r 'Pesto.exe'
    $exeInfo = $null
    if (Test-Path -LiteralPath $exe) {
        $ei = Get-Item -LiteralPath $exe
        $exeInfo = [ordered]@{ Version = $ei.VersionInfo.ProductVersion; Size = $ei.Length; Sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash }
    }
    $top = @(Get-ChildItem $r -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object { $_.Name })
    $refs += [ordered]@{ Root = $r; Exists = $true; Top = $top; CfgPaths = $cfgs; Exe = $exeInfo }
}
$result = [ordered]@{ Utc = (Get-Date).ToUniversalTime().ToString('o'); WebView2 = $wv2; RefRoots = $refs }
