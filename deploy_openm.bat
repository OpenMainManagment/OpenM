@echo off
setlocal
set "MODE=%~1"
if not defined MODE set "MODE=deploy"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_openm.ps1" -Mode "%MODE%" -SourcePath "%~2"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" echo OpenM deployment failed. Exit code: %RESULT%
if "%~1"=="" pause
exit /b %RESULT%
