param(
  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = Join-Path $projectRoot ("releases\{0}" -f $Version)
$changelogPath = Join-Path $projectRoot 'CHANGELOG.md'

if (-not (Test-Path $changelogPath)) {
  throw "CHANGELOG.md nao encontrado em: $changelogPath"
}

if (Test-Path $releaseRoot) {
  Remove-Item $releaseRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

Copy-Item (Join-Path $projectRoot 'planforge_builder.rb') -Destination $releaseRoot -Force
Copy-Item (Join-Path $projectRoot 'planforge_builder') -Destination $releaseRoot -Recurse -Force
Copy-Item $changelogPath -Destination (Join-Path $releaseRoot 'CHANGELOG.md') -Force

& (Join-Path $PSScriptRoot 'export-release-notes.ps1') -Version $Version -DestinationPath (Join-Path $releaseRoot 'RELEASE_NOTES.md')

& (Join-Path $PSScriptRoot 'package.ps1') -Version $Version -SourcePath $releaseRoot

Write-Output "Release capturada em: $releaseRoot"
