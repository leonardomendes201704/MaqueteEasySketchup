param(
  [string]$Version,
  [string]$PluginsPath = "$env:APPDATA\SketchUp\SketchUp 2020\SketchUp\Plugins",
  [switch]$List
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releasesRoot = Join-Path $projectRoot 'releases'
$backupsRoot = Join-Path $projectRoot 'installed_backups'

function Get-AvailableVersions {
  if (-not (Test-Path $releasesRoot)) {
    return @()
  }

  Get-ChildItem $releasesRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
}

if ($List -or -not $Version) {
  $versions = Get-AvailableVersions
  if (-not $versions -or $versions.Count -eq 0) {
    Write-Output 'Nenhuma release versionada encontrada.'
    exit 0
  }

  Write-Output 'Releases disponiveis:'
  $versions | ForEach-Object { Write-Output " - $_" }
  exit 0
}

$sourceRoot = Join-Path $releasesRoot $Version
if (-not (Test-Path $sourceRoot)) {
  throw "Release nao encontrada: $sourceRoot"
}

$releaseNotes = Join-Path $sourceRoot 'RELEASE_NOTES.md'

New-Item -ItemType Directory -Force -Path $PluginsPath, $backupsRoot | Out-Null

$installedLoader = Join-Path $PluginsPath 'planforge_builder.rb'
$installedFolder = Join-Path $PluginsPath 'planforge_builder'

if ((Test-Path $installedLoader) -or (Test-Path $installedFolder)) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backupFolder = Join-Path $backupsRoot "$stamp-$Version"
  New-Item -ItemType Directory -Force -Path $backupFolder | Out-Null

  if (Test-Path $installedLoader) {
    Copy-Item $installedLoader -Destination $backupFolder -Force
  }

  if (Test-Path $installedFolder) {
    Copy-Item $installedFolder -Destination $backupFolder -Recurse -Force
  }
}

if (Test-Path $installedLoader) {
  Remove-Item $installedLoader -Force
}

if (Test-Path $installedFolder) {
  Remove-Item $installedFolder -Recurse -Force
}

Copy-Item (Join-Path $sourceRoot 'planforge_builder.rb') -Destination $installedLoader -Force
Copy-Item (Join-Path $sourceRoot 'planforge_builder') -Destination $installedFolder -Recurse -Force

Write-Output "Versao instalada: $Version"
Write-Output "Origem: $sourceRoot"
Write-Output "Destino: $PluginsPath"
if (Test-Path $releaseNotes) {
  Write-Output "Changelog da release: $releaseNotes"
}
