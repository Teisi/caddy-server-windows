@echo off
setlocal EnableDelayedExpansion

:: Prüfe auf Administrator-Rechte
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Starte Script mit Administrator-Rechten...
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c cd /d %CD% && %~nx0'"
    exit /b
)

echo Stopping services...
echo.

:: Stoppe PHP 8.2
echo Stopping PHP 8.2...
schtasks /end /tn "PHP82_CGI" >nul 2>&1
schtasks /delete /tn "PHP82_CGI" /f >nul 2>&1
echo PHP 8.2 stopped
echo.

:: Stoppe PHP 8.4
echo Stopping PHP 8.4...
schtasks /end /tn "PHP84_CGI" >nul 2>&1
schtasks /delete /tn "PHP84_CGI" /f >nul 2>&1
echo PHP 8.4 stopped
echo.

:: Stoppe Caddy
echo Stopping Caddy...
if exist "%~dp0caddy-server\caddy.pid" (
    for /f %%a in (%~dp0caddy-server\caddy.pid) do (
        taskkill /PID %%a /F >nul 2>&1
    )
    del "%~dp0caddy-server\caddy.pid"
)
taskkill /IM caddy.exe /F >nul 2>&1
echo Caddy stopped
echo.

echo All services have been stopped!
pause
