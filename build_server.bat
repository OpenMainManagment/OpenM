@echo off
setlocal
cd /d "%~dp0"

:: Builds a self-contained server package in dist\openm-server
:: (Flutter web build + backend source + Docker/nginx configuration).
for /d %%D in ("%~dp0*backend*") do set "BACKEND_DIR=%%~fD"
for /d %%D in ("%~dp0*frontend*") do set "FRONTEND_DIR=%%~fD"
set "OUT=%~dp0dist\openm-server"

echo Building Flutter web (API at /api)...
pushd "%FRONTEND_DIR%"
call flutter build web --release --dart-define=API_BASE_URL=/api
if errorlevel 1 (
    popd
    echo Flutter build failed.
    exit /b 1
)
popd

echo Assembling %OUT% ...
if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%\backend"

robocopy "%FRONTEND_DIR%\build\web" "%OUT%\web" /E /NFL /NDL /NJH /NJS >nul
if errorlevel 8 exit /b 1

:: Backend source only: no venv, databases, uploads, caches or tests.
robocopy "%BACKEND_DIR%" "%OUT%\backend" /E /NFL /NDL /NJH /NJS ^
    /XD .venv .git .pytest_cache __pycache__ database storage tests ais ^
    /XF *.db *.pyc .gitignore .gitattributes >nul
if errorlevel 8 exit /b 1

copy /y "%~dp0deploy\backend.Dockerfile" "%OUT%\" >nul
copy /y "%~dp0deploy\docker-compose.yml" "%OUT%\" >nul
copy /y "%~dp0deploy\nginx.conf" "%OUT%\" >nul
copy /y "%~dp0deploy\README.md" "%OUT%\" >nul
copy /y "%~dp0deploy\.env.example" "%OUT%\" >nul

echo.
echo Done: %OUT%
echo Copy this folder to the server and run: docker compose up -d --build
endlocal
