param(
  [string]$SketchUpPath = 'C:\Program Files\SketchUp\SketchUp 2020\SketchUp.exe',
  [string]$ModelPath = 'C:\Program Files\SketchUp\SketchUp 2020\resources\en-US\Templates\Temp02a - Arch.skp',
  [int]$TimeoutSeconds = 240,
  [double]$QuitDelaySeconds = 1.5,
  [double]$SnapStepCm = 25,
  [double]$WallThicknessCm = 20,
  [double]$WallHeightCm = 320,
  [double]$FloorThicknessCm = 12,
  [string]$Alignment = 'center'
)

$ErrorActionPreference = 'Stop'

$triggerPath = Join-Path $env:TEMP 'planforge_builder_smoke_test.json'
$resultPath = Join-Path $env:TEMP 'planforge_builder_smoke_test_result.json'
$logPath = Join-Path $env:LOCALAPPDATA 'PlanForgeBuilder\planforge_builder.log'
$startedAt = Get-Date
$quotedModelPath = '"{0}"' -f $ModelPath

Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

if (Test-Path $resultPath) {
  Remove-Item $resultPath -Force
}

$payload = @{
  settings = @{
    snap_step_cm = $SnapStepCm
    wall_thickness_cm = $WallThicknessCm
    wall_height_cm = $WallHeightCm
    floor_thickness_cm = $FloorThicknessCm
    alignment = $Alignment
    ortho_mode = $true
    create_floor_on_close = $true
  }
  quit_after = $true
  quit_delay = $QuitDelaySeconds
} | ConvertTo-Json -Depth 4

[System.IO.File]::WriteAllText($triggerPath, $payload, [System.Text.Encoding]::UTF8)
Start-Process -FilePath $SketchUpPath -ArgumentList $quotedModelPath
Start-Sleep -Seconds 10

$shell = New-Object -ComObject WScript.Shell
if ($shell.AppActivate('Bem-vindo ao SketchUp') -or $shell.AppActivate('Welcome to SketchUp')) {
  Start-Sleep -Milliseconds 800
  $shell.SendKeys('{ENTER}')
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  if ((Test-Path $resultPath) -and ((Get-Item $resultPath).LastWriteTime -gt $startedAt)) {
    Get-Content $resultPath
    exit 0
  }

  Start-Sleep -Seconds 2
}

if (Test-Path $logPath) {
  Write-Output '--- LOG ---'
  Get-Content $logPath -Tail 80
}

throw 'Smoke test nao gerou resultado no tempo limite.'
