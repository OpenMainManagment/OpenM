@echo off
setlocal
cd /d "%~dp0"
echo Starting OpenM Backend and Frontend...

set "BACKEND_DIR=%~dp0OpenM_backend_python"
set "FRONTEND_DIR=%~dp0OpenM_frontend_flutter"
set "VENV_DIR=%~dp0.venv"
if not exist "%BACKEND_DIR%\." (
    echo Backend folder not found: "%BACKEND_DIR%"
    exit /b 1
)
if not exist "%FRONTEND_DIR%\." (
    echo Frontend folder not found: "%FRONTEND_DIR%"
    exit /b 1
)
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo Python virtual environment not found: %VENV_DIR%
    exit /b 1
)
if /I "%~1"=="--with-env" goto configured
"%VENV_DIR%\Scripts\python.exe" "%BACKEND_DIR%\launch_local.py"
exit /b %errorlevel%
:configured
if not defined PGCONNECT_TIMEOUT set "PGCONNECT_TIMEOUT=5"
echo Checking PostgreSQL connection and initial setup...
pushd "%BACKEND_DIR%"
if errorlevel 1 (
    echo Cannot access the backend folder.
    exit /b 1
)
"%VENV_DIR%\Scripts\python.exe" -m app.check_initial_setup
if errorlevel 1 (
    popd
    echo PostgreSQL connection or setup status check failed. Check the error above, the server, database and credentials.
    echo Configure OPENM_DATABASE_URL or OPENM_DB_HOST, OPENM_DB_PORT, OPENM_DB_NAME, OPENM_DB_USER and OPENM_DB_PASSWORD.
    echo OpenM was not started.
    exit /b 1
)
"%VENV_DIR%\Scripts\python.exe" -m app.startup_readiness check-port
if errorlevel 1 (
    popd
    echo OpenM was not started. Check the existing process using port 8002.
    exit /b 1
)
popd

:: Start LM Studio's local server for the optional AI chat assistant.
where lms >nul 2>nul
if %errorlevel%==0 (
    echo Starting LM Studio server...
    start "LM Studio Server" cmd /k "lms server start"
) else (
    echo LM Studio CLI ^(lms^) not found on PATH — skipping AI chat server startup.
)

:: Prepare the chat assistant's separate uv project before activating the backend environment.
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

:: Wait for the backend to finish database initialization before launching Flutter.
pushd "%BACKEND_DIR%"
"%VENV_DIR%\Scripts\python.exe" -m app.startup_readiness wait
if errorlevel 1 (
    popd
    echo Backend did not become ready. Check the Backend Server window for errors.
    echo Frontend was not started.
    exit /b 1
)
popd

:: Start Frontend in web mode
echo Starting Frontend...
start "Frontend App" /D "%FRONTEND_DIR%" cmd /k "flutter run -d chrome"



echo.
echo Backend is ready and the frontend launch was requested:
echo Backend: http://localhost:8002

pause