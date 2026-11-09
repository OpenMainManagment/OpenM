@echo off
cd /d "%~dp0"
echo Starting OpenM Backend and Frontend...

:: Start LM Studio's local server for the AI chat assistant (optional —
:: only runs if the LM Studio CLI ("lms") is installed and on PATH).
where lms >nul 2>nul
if %errorlevel%==0 (
    echo Starting LM Studio server...
    start "LM Studio Server" cmd /k "lms server start"
) else (
    echo LM Studio CLI ^(lms^) not found on PATH — skipping AI chat server startup.
)

:: Prepare the ais/chat AI assistant's own uv project/venv (separate from
:: OpenM's root .venv). Done before activating the backend environment.
for /d %%D in ("%~dp0*backend*") do set "BACKEND_DIR=%%~fD"
for /d %%D in ("%~dp0*frontend*") do set "FRONTEND_DIR=%%~fD"
for %%D in ("%~dp0.venv") do set "VENV_DIR=%%~fD"
if not defined BACKEND_DIR (
    echo Backend folder not found.
    exit /b 1
)
if not defined FRONTEND_DIR (
    echo Frontend folder not found.
    exit /b 1
)
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo Python virtual environment not found: %VENV_DIR%
    exit /b 1
)

where uv >nul 2>nul
if errorlevel 1 (
    echo uv not found on PATH — skipping AI chat assistant environment setup.
) else (
    echo Preparing AI chat assistant environment...
    pushd "%BACKEND_DIR%\ais\chat"
    call uv sync
    popd
)

:: Use the project-root Python environment for the backend.
if /I "%VIRTUAL_ENV%"=="%VENV_DIR%" (
    echo Python environment already active: %VENV_DIR%
) else (
    echo Activating Python environment: %VENV_DIR%
    if exist "%VENV_DIR%\Scripts\activate.bat" (
        call "%VENV_DIR%\Scripts\activate.bat"
        if errorlevel 1 (
            echo Failed to activate Python environment.
            exit /b 1
        )
    ) else (
        set "VIRTUAL_ENV=%VENV_DIR%"
        set "PATH=%VENV_DIR%\Scripts;%PATH%"
    )
)

:: Start Backend on port 8002
echo Starting Backend...
start "Backend Server" /D "%BACKEND_DIR%" cmd /k "python -m uvicorn app.main:app --host 0.0.0.0 --port 8002 --reload"
cd /d "%~dp0"

:: Wait a moment for backend to start
timeout /t 3 /nobreak >nul

:: Start Frontend in web mode
echo Starting Frontend...
start "Frontend App" cmd /k "cd /d %FRONTEND_DIR% && flutter run -d chrome"



echo.
echo Both applications are now running:
echo Backend: http://localhost:8002

pause