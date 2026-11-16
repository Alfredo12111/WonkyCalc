$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $project
if (![Environment]::Is64BitOperatingSystem) { throw 'WonkyCalc requires 64-bit Windows.' }
if (!(Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 20 or newer from https://nodejs.org first.' }
$python = if ($env:WONKYCALC_PYTHON) { $env:WONKYCALC_PYTHON } else { 'python' }
if (!$env:WONKYCALC_TCL) {
    & $python -c "import tkinter; print('Using Tcl', tkinter.Tcl().eval('info patchlevel'))"
    if ($LASTEXITCODE -ne 0) { throw 'Install Python 3 with Tcl/Tk from https://python.org, or set WONKYCALC_TCL to a tclsh executable.' }
}
& (Join-Path $PSScriptRoot 'download-runtimes.ps1')

if (!(Test-Path '.runtimes\raku\rakudo-moar-2026.09-01-win-x86_64-msvc\bin\raku.exe')) {
    Write-Host 'Extracting Raku...'
    Expand-Archive -LiteralPath '.cache\raku.zip' -DestinationPath '.runtimes\raku' -Force
}
if (!(Test-Path '.runtimes\j\j64\jconsole.exe')) {
    Write-Host 'Extracting J...'
    Expand-Archive -LiteralPath '.cache\j.zip' -DestinationPath '.runtimes\j' -Force
}
Copy-Item -LiteralPath '.cache\rebol.exe' -Destination '.runtimes\rebol.exe' -Force
Copy-Item -LiteralPath '.cache\red.exe' -Destination '.runtimes\red.exe' -Force
if (!(Test-Path '.runtimes\prolog\bin\swipl.exe')) {
    $extractor = Join-Path $project '.runtimes\extractor\Files\7-Zip\7z.exe'
    if (!(Test-Path -LiteralPath $extractor)) {
        Write-Host 'Extracting the archive tool (administrative image only; no system installation)...'
        $msi = Join-Path $project '.cache\7zip.msi'
        $target = Join-Path $project '.runtimes\extractor'
        $arguments = '/a "' + $msi + '" /qn TARGETDIR="' + $target + '"'
        $process = Start-Process msiexec.exe -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "Archive tool extraction failed ($($process.ExitCode)). Windows Installer must be available." }
    }
    Write-Host 'Extracting SWI-Prolog (no system installation)...'
    & $extractor x '.cache\swipl.exe' '-o.runtimes\prolog' -y -bso0
    if ($LASTEXITCODE -ne 0) { throw 'SWI-Prolog extraction failed.' }
}
Write-Host 'Checking every runtime...'
node scripts/doctor.mjs
if ($LASTEXITCODE -ne 0) { throw 'A runtime did not pass the smoke test. See the error above.' }
Write-Host 'Ready! Run npm start, or double-click WonkyCalc.cmd.'
