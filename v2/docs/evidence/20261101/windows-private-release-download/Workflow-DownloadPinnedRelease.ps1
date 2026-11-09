$ErrorActionPreference = 'Stop'
$version = $env:UI_UPDATE_FROM_VERSION
$repository = $env:GITHUB_REPOSITORY
if ($repository -cne 'M4D135/pesto' -or $version -cnotmatch '^2\.[0-9]+\.[0-9]+$' -or -not $env:GITHUB_TOKEN) { throw 'Unexpected published release inputs.' }
$headers = @{ Authorization="Bearer $env:GITHUB_TOKEN"; Accept='application/vnd.github+json'; 'X-GitHub-Api-Version'='2022-11-28' }
try { $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/tags/v$version" -Headers $headers }
catch { throw 'Cannot read the pinned published release metadata.' }
if ($release.tag_name -cne "v$version" -or $release.draft -or $release.prerelease) { throw 'The pinned release is not published and stable.' }
$expected = @{ PROD=$env:UI_UPDATE_FROM_PROD_SHA256; DEV=$env:UI_UPDATE_FROM_DEV_SHA256 }
foreach ($channel in @('PROD','DEV')) {
  $name = "Pesto_V2_${channel}_${version}.zip"
  $assets = @($release.assets | Where-Object { $_.name -ceq $name })
  if ($assets.Count -ne 1) { throw "Missing or ambiguous published $channel archive." }
  $asset = $assets[0]
  if ([string]$asset.id -cnotmatch '^[1-9][0-9]*$' -or $asset.state -cne 'uploaded' -or
      $asset.size -le 0 -or $expected[$channel] -cnotmatch '^[0-9a-f]{64}$' -or
      $asset.digest -cne ('sha256:' + $expected[$channel])) { throw "Published $channel metadata differs from the pinned archive." }
  $destination = Join-Path (Resolve-Path 'out').Path $name
  if (Test-Path -LiteralPath $destination) { throw "Published $channel destination already exists." }
  $headers.Accept = 'application/octet-stream'
  # PowerShell drops Authorization on redirects; never preserve it for the signed asset host.
  try { Invoke-WebRequest -Uri "https://api.github.com/repos/$repository/releases/assets/$($asset.id)" -Headers $headers -OutFile $destination }
  catch { throw "Cannot download the pinned published $channel archive." }
  if ((Get-Item -LiteralPath $destination).Length -ne $asset.size -or
      (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected[$channel]) { throw "Published $channel archive bytes differ from the pinned release." }
}
