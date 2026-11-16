$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -Force
$project = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $project '.cache'
$runtime = Join-Path $project '.runtimes'
New-Item -ItemType Directory -Force -Path $cache,$runtime | Out-Null
$downloads = @(
    @{Url='https://rakudo.org/dl/rakudo/rakudo-moar-2026.09-01-win-x86_64-msvc.zip'; File='raku.zip'; Hash='BB09665F1CC5442E31AC611F78B2DB54B34D4EB904FA6B685569B43240529099'},
    @{Url='https://github.com/jsoftware/jsource/releases/download/build96/w64.zip'; File='j.zip'; Hash='CF21BEA9A8E7CD0672CB210AF31955401755CC4C44B6781CC5D61DB101A12504'},
    @{Url='https://github.com/Oldes/Rebol3/releases/download/3.22.1/rebol3-bulk-windows-x64.exe'; File='rebol.exe'; Hash='964E8FEC5F730AE79CCD0C5E474EB1680F570678068FD67030D4885295699424'},
    @{Url='https://static.red-lang.org/dl/win/red-cli-066.exe'; File='red.exe'; Hash='B6CD3D3F1F21583DAB2FF573707FF4C6DD50305B0CC2FE676629709420DC32FD'},
    @{Url='https://www.swi-prolog.org/download/stable/bin/swipl-10.0.2-1.x64.exe'; File='swipl.exe'; Hash='2EC1F25BE0EAFB92E559004782B130774C12573FB4B7E8A917E534754A641AD6'},
    @{Url='https://github.com/ip7z/7zip/releases/download/26.06/7z2606-x64.msi'; File='7zip.msi'; Hash='6DC822569E777D9A3ECD5FFCBC22B55600AF87E6C5D9810A64E8566CF5A4AF9F'}
)
foreach ($download in $downloads) {
    $destination = Join-Path $cache $download.File
    if (!(Test-Path -LiteralPath $destination)) {
        Write-Host "Downloading $($download.File)..."
        Invoke-WebRequest -UseBasicParsing -Uri $download.Url -OutFile "$destination.partial"
        Move-Item -LiteralPath "$destination.partial" -Destination $destination
    }
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($actual -ne $download.Hash) { throw "Checksum mismatch for $($download.File). Expected $($download.Hash), got $actual. Stop and inspect the download; do not run it." }
    Write-Host "Verified $($download.File)"
}
