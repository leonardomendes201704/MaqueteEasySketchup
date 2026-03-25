param(
  [string]$SketchUpPath = 'C:\Program Files\SketchUp\SketchUp 2020\SketchUp.exe',
  [string]$ModelPath = 'C:\Program Files\SketchUp\SketchUp 2020\resources\en-US\Templates\Temp02a - Arch.skp',
  [int]$TimeoutSeconds = 240,
  [string[]]$Files = @(
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\main.rb',
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\geometry_builder.rb',
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\room_regenerator.rb',
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\parametric_editor.rb',
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\ui.rb',
    'C:\Leonardo\Labs\Sketchup Plugins\releases\0.6.0\planforge_builder\smoke_test.rb'
  )
)

$ErrorActionPreference = 'Stop'

$triggerPath = Join-Path $env:TEMP 'planforge_builder_smoke_test.json'
$resultPath = Join-Path $env:TEMP 'planforge_builder_smoke_test_result.json'
$startedAt = Get-Date
$quotedModelPath = '"{0}"' -f $ModelPath

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if (Test-Path $resultPath) {
  Remove-Item $resultPath -Force
}

$payload = @{
  compile_probe = $true
  files = $Files
  quit_after = $true
  quit_delay = 1.5
} | ConvertTo-Json -Depth 4

[System.IO.File]::WriteAllText($triggerPath, $payload, [System.Text.Encoding]::UTF8)
Start-Process -FilePath $SketchUpPath -ArgumentList $quotedModelPath

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  if ((Test-Path $resultPath) -and ((Get-Item $resultPath).LastWriteTime -gt $startedAt)) {
    Get-Content $resultPath
    exit 0
  }

  Start-Sleep -Seconds 2
}

throw 'Compile probe nao gerou resultado no tempo limite.'
