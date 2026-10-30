@echo off
setlocal
rem PsExec is not bundled. Get it from Microsoft and place it beside this script.
if not exist "%~dp0PsExec.exe" (
  echo Missing PsExec.exe. Download it from https://learn.microsoft.com/en-us/sysinternals/downloads/psexec and accept Microsoft's terms. 1>&2
  exit /b 2
)
if not defined MMS_KIOSK_URL (
  echo Set MMS_KIOSK_URL to your own absolute HTTPS URL before running this kiosk demo. 1>&2
  exit /b 2
)
"%~dp0PsExec.exe" -accepteula -i -d -s PowerShell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0Configure-AA-WMIBridge-V2.ps1" -KioskUrl "%MMS_KIOSK_URL%" 2> "%~dp0AALog.txt"
exit /b %errorlevel%
