param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $project '.cache/bin' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$contracts = Join-Path $OutputDirectory 'eiffel-build'
New-Item -ItemType Directory -Force -Path $contracts | Out-Null
Copy-Item "$project/workers/contracts/*" $contracts -Force
$env:GOBO = Join-Path $project '.runtimes/gobo/gobo'
$env:ZIG = 'zig'
$env:PATH = "$env:GOBO/tool/gec/backend/c/zig;$project/.runtimes/msys64/ucrt64/bin;$env:PATH"
Push-Location -LiteralPath $contracts
try {
    & "$env:GOBO/bin/gec.exe" --gc=no --no-benchmark system.ecf
    if ($LASTEXITCODE -ne 0) { throw 'Eiffel compilation failed.' }
    Copy-Item contracts.exe $OutputDirectory -Force
} finally { Pop-Location }
Copy-Item "$project/workers/explain.icn" $OutputDirectory -Force
Copy-Item "$project/workers/units.m" $OutputDirectory -Force
Push-Location -LiteralPath $OutputDirectory
try {
    & "$project/.runtimes/icon/app/bin/icont.exe" -o explain.exe explain.icn
    if ($LASTEXITCODE -ne 0) { throw 'Icon compilation failed.' }
} finally { Pop-Location }
$env:MSYSTEM = 'UCRT64'
$env:CHERE_INVOKING = '1'
$env:WONKYCALC_BUILD_OUTPUT = $OutputDirectory
Push-Location -LiteralPath $project
try {
    & "$project/.runtimes/msys64/usr/bin/bash.exe" -lc 'bash scripts/compile-units.sh'
    if ($LASTEXITCODE -ne 0) { throw 'Mercury compilation failed.' }
} finally { Pop-Location }
Write-Host 'Compiled Eiffel, Icon, and Mercury.'
if (Test-Path "$project/.runtimes/msys64/ucrt64/bin/libwinpthread-1.dll") {
    Copy-Item "$project/.runtimes/msys64/ucrt64/bin/libwinpthread-1.dll" $OutputDirectory -Force
}
