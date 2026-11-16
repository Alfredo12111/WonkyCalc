$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -Force
$project = Split-Path $PSScriptRoot -Parent
Push-Location -LiteralPath $project
try {
    $extractor = Join-Path $project '.runtimes/extractor/Files/7-Zip/7z.exe'
    foreach ($item in (Get-Content "$PSScriptRoot/extra-runtimes.json" -Raw | ConvertFrom-Json)) {
        $file = Join-Path $project ('.cache/' + $item.file)
        if (!(Test-Path -LiteralPath $file)) {
            Write-Host "Downloading $($item.file)..."
            Invoke-WebRequest -UseBasicParsing $item.url -OutFile "$file.partial"
            Move-Item -LiteralPath "$file.partial" -Destination $file
        }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.sha256) { throw "Checksum mismatch: $($item.file)." }
    }
    $packages = @(
        @('factor.zip','factor','factor/factor/factor.exe'),
        @('haxe.zip','haxe','haxe/haxe_20250509143529_e0b355c/haxe.exe'),
        @('gobo.7z','gobo','gobo/gobo/bin/gec.exe'),
        @('bqn.zip','bqn','bqn/bqn/BQN.exe'),
        @('innoextract.zip','innoextract','innoextract/innoextract.exe'),
        @('regina-source.zip','regina-source','regina-source/regina-9ad07276c9846f0f23a27512eabca1cc8a7b857b/makefile.win64.vc')
    )
    foreach ($p in $packages) {
        if (!(Test-Path ('.runtimes/'+$p[2]))) {
            & $extractor x ('.cache/'+$p[0]) ('-o.runtimes/'+$p[1]) -y -bso0
            if ($LASTEXITCODE -ne 0) { throw "Extraction failed: $($p[0])" }
        }
    }
    if (!(Test-Path '.runtimes/icon/app/bin/icont.exe')) {
        & '.runtimes/innoextract/innoextract.exe' --silent --extract --output-dir '.runtimes/icon' '.cache/unicon.exe'
        if ($LASTEXITCODE -ne 0) { throw 'Icon extraction failed.' }
    }
    if (!(Test-Path '.runtimes/rexx/rexx.exe')) {
        New-Item -ItemType Directory -Force '.runtimes/rexx' | Out-Null
        & "$PSScriptRoot/build-rexx.cmd" > '.cache/rexx-build.log' 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Rexx build failed. Install Visual Studio Build Tools with Desktop development with C++, then inspect .cache/rexx-build.log.' }
    }
    if (!(Test-Path '.runtimes/msys64/usr/bin/bash.exe')) {
        tar -xf '.cache/msys2-stable.tar.xz' -C '.runtimes'
        if ($LASTEXITCODE -ne 0) { throw 'MSYS2 extraction failed.' }
    }
    $env:MSYSTEM='UCRT64'
    $env:CHERE_INVOKING='1'
    if (!(Test-Path '.runtimes/msys64/opt/mercury/.wonky-ready')) {
        Write-Host 'Building Mercury for the first time. This can take 10-30 minutes or more; logs are in .cache/mercury-*.log.'
        & '.runtimes/msys64/usr/bin/bash.exe' -lc 'pacman -Syu --noconfirm'
        & '.runtimes/msys64/usr/bin/bash.exe' -lc 'pacman -Syu --noconfirm && pacman -S --noconfirm --needed make diffutils perl tar flex bison binutils mingw-w64-ucrt-x86_64-gcc'
        if ($LASTEXITCODE -ne 0) { throw 'Project-local compiler dependencies failed to install.' }
        & '.runtimes/msys64/usr/bin/bash.exe' -lc 'bash scripts/build-mercury.sh'
        if ($LASTEXITCODE -ne 0) { throw 'Mercury build failed; inspect .cache/mercury-configure.log, mercury-build.log and mercury-install.log.' }
    }
    & "$PSScriptRoot/build.ps1"
} finally { Pop-Location }
