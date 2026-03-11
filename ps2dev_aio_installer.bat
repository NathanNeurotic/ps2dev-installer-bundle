@echo off
setlocal

title PS2DEV Installer Bundle
echo ============================================================
echo PS2DEV Installer Bundle
echo Windows launcher for Ubuntu on WSL
echo ============================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ps2dev_aio_installer.ps1" %*
set "exit_code=%ERRORLEVEL%"

echo.
if "%exit_code%"=="0" (
  echo Installer finished. Review the summary above, then press any key to close.
) else (
  echo Launcher exited with code %exit_code%. Review the error above, then press any key to close.
)

if not "%PS2DEV_NO_PAUSE%"=="1" (
  pause >nul
)

exit /b %exit_code%
