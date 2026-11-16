@echo off
setlocal
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "WONKY_VS=%%i"
if not defined WONKY_VS exit /b 1
call "%WONKY_VS%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
cd /d "%~dp0..\.runtimes\regina-source\regina-9ad07276c9846f0f23a27512eabca1cc8a7b857b"
set "REGINA_SRCDIR=."
nmake /nologo /f makefile.win64.vc rexx.exe GCI=N
if errorlevel 1 exit /b 1
copy /y rexx.exe "%~dp0..\.runtimes\rexx\rexx.exe" >nul
