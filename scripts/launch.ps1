param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $project
$port = if ($env:PORT) { $env:PORT } else { '3210' }
$url = "http://localhost:$port"
$healthUrl = "http://127.0.0.1:$port/api/health"
$connected = $false
try {
    $check = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    $connected = $check.languages.Count -eq 12
} catch {}
if (!$connected) {
    if (!(Test-Path '.cache\bin\units.exe')) { & (Join-Path $PSScriptRoot 'setup-windows.ps1') }
    $node = (Get-Command node -ErrorAction Stop).Source
    $script = Join-Path $project 'server.mjs'
    New-Item -ItemType Directory -Force -Path '.cache' | Out-Null
    $process = Start-Process -FilePath $node -ArgumentList ('"' + $script + '"') -WorkingDirectory $project -WindowStyle Hidden -PassThru -RedirectStandardOutput '.cache\server.log' -RedirectStandardError '.cache\server-error.log'
    $process.Id | Set-Content -LiteralPath '.cache\server.pid'
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try { $check = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2; if ($check.languages.Count -eq 12) { $connected = $true; break } } catch {}
        if ($process.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
}
if (!$connected) { throw 'WonkyCalc could not start. Check .cache\server-error.log or run npm start in a terminal.' }
if (!$NoBrowser) { Start-Process $url }
Write-Host "WonkyCalc is running at $url"
Write-Host 'To stop its background server, run scripts\stop.ps1.'
