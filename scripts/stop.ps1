$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$pidFile = Join-Path $project '.cache\server.pid'
if (Test-Path -LiteralPath $pidFile) {
    $serverProcessId = [int](Get-Content -LiteralPath $pidFile)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$serverProcessId"
    $expectedScript = Join-Path $project 'server.mjs'
    if ($process -and $process.Name -eq 'node.exe' -and $process.CommandLine.Contains($expectedScript)) {
        Stop-Process -Id $serverProcessId
        Write-Host 'WonkyCalc stopped.'
    } else { Write-Host 'The recorded WonkyCalc server is no longer running.' }
    Remove-Item -LiteralPath $pidFile
} else { Write-Host 'No background server was recorded. If you used npm start, press Ctrl+C in its terminal.' }
