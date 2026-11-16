$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location -LiteralPath $project
try {
    & '.runtimes/haxe/haxe_20250509143529_e0b355c/haxe.exe' build.hxml
    if ($LASTEXITCODE -ne 0) { throw 'Haxe compilation failed.' }
    & "$PSScriptRoot/build-workers.ps1"
} finally { Pop-Location }
