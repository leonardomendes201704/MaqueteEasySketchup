param(
  [string]$SketchUpPath = 'C:\Program Files\SketchUp\SketchUp 2020\SketchUp.exe',
  [string]$ModelPath = 'C:\Program Files\SketchUp\SketchUp 2020\resources\en-US\Templates\Temp02a - Arch.skp',
  [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'

$resultPath = Join-Path $env:TEMP 'planforge_builder_startup_probe.json'
$startupScript = Join-Path $PSScriptRoot 'smoke_startup.rb'
$quotedModelPath = '"{0}"' -f $ModelPath
$quotedStartupScript = '"{0}"' -f $startupScript

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if (Test-Path $resultPath) {
  Remove-Item $resultPath -Force
}

Start-Process -FilePath $SketchUpPath -ArgumentList @($quotedModelPath, '-RubyStartup', $quotedStartupScript)

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  if (Test-Path $resultPath) {
    Get-Content $resultPath
    exit 0
  }

  Start-Sleep -Seconds 2
}

throw 'RubyStartup probe nao gerou resultado.'
