param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [string]$SourcePath
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$distFolder = Join-Path $projectRoot 'dist'
$stagingFolder = Join-Path $env:TEMP 'planforge_builder_rbz'
$zipPath = Join-Path $distFolder ("planforge_builder-{0}.zip" -f $Version)
$rbzPath = Join-Path $distFolder ("planforge_builder-{0}.rbz" -f $Version)
$releaseSource = Join-Path $projectRoot ("releases\{0}" -f $Version)

if (-not $SourcePath) {
  if (Test-Path $releaseSource) {
    $SourcePath = $releaseSource
  } else {
    $SourcePath = $projectRoot
  }
}

if (-not (Test-Path $SourcePath)) {
  throw "SourcePath nao encontrado: $SourcePath"
}

if (Test-Path $stagingFolder) {
  Remove-Item -Recurse -Force $stagingFolder
}

New-Item -ItemType Directory -Force -Path $stagingFolder, $distFolder | Out-Null

Copy-Item -Path (Join-Path $SourcePath 'planforge_builder.rb') -Destination $stagingFolder
Copy-Item -Path (Join-Path $SourcePath 'planforge_builder') -Destination $stagingFolder -Recurse

if (Test-Path $zipPath) {
  Remove-Item -Force $zipPath
}

if (Test-Path $rbzPath) {
  Remove-Item -Force $rbzPath
}

Compress-Archive -Path (Join-Path $stagingFolder '*') -DestinationPath $zipPath -Force
Move-Item -Path $zipPath -Destination $rbzPath -Force

Write-Output "RBZ gerado em: $rbzPath"
Write-Output "Fonte empacotada: $SourcePath"
