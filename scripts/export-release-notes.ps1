param(
  [Parameter(Mandatory = $true)]
  [string]$Version,
  [string]$DestinationPath
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$changelogPath = Join-Path $projectRoot 'CHANGELOG.md'

if (-not (Test-Path $changelogPath)) {
  throw "CHANGELOG.md nao encontrado em: $changelogPath"
}

$content = Get-Content $changelogPath -Raw
$escapedVersion = [regex]::Escape($Version)
$pattern = "(?ms)^##\s+\[?$escapedVersion\]?[^\r\n]*\r?\n(?<section>.*?)(?=^##\s+\[?\d|\z)"
$match = [regex]::Match($content, $pattern)

if (-not $match.Success) {
  throw "Versao $Version nao encontrada no CHANGELOG.md"
}

if (-not $DestinationPath) {
  $DestinationPath = Join-Path $projectRoot ("releases\{0}\RELEASE_NOTES.md" -f $Version)
}

$destinationFolder = Split-Path -Parent $DestinationPath
New-Item -ItemType Directory -Force -Path $destinationFolder | Out-Null

$headerPattern = "(?ms)^##\s+\[?$escapedVersion\]?[^\r\n]*"
$headerMatch = [regex]::Match($content, $headerPattern)
$header = $headerMatch.Value.Trim()
$body = $match.Groups['section'].Value.Trim()

$releaseNotes = @(
  '# PlanForge Builder Release Notes'
  ''
  $header
  ''
  $body
  ''
) -join [Environment]::NewLine

[System.IO.File]::WriteAllText($DestinationPath, $releaseNotes, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "Release notes gerado em: $DestinationPath"
