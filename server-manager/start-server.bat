@echo off
setlocal EnableDelayedExpansion

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Starte Script mit Administrator-Rechten...
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c cd /d %CD% && %~nx0'"
    exit /b
)

echo Starting PHP and Caddy Server...
echo Current time: %date% %time%
echo User: %USERNAME%
echo.

:: Create a windows scheduled task für PHP 8.2
echo Starting PHP 8.2...
schtasks /query /tn "PHP82_CGI" >nul 2>&1
if !errorlevel! equ 0 (
    schtasks /end /tn "PHP82_CGI"
    schtasks /delete /tn "PHP82_CGI" /f
)
schtasks /create /tn "PHP82_CGI" /tr "\"%~dp0IIS-Config\PHP\php-8.2\php-cgi.exe\" -b 127.0.0.1:9082" /sc onstart /ru System /rl HIGHEST /f
schtasks /run /tn "PHP82_CGI"
if !errorlevel! neq 0 (
    echo Error starting PHP 8.2
) else (
    echo PHP 8.2 started successfully
)
timeout /t 2 > nul
echo.

:: Create a windows scheduled task für PHP 8.4
echo Starting PHP 8.4...
schtasks /query /tn "PHP84_CGI" >nul 2>&1
if !errorlevel! equ 0 (
    schtasks /end /tn "PHP84_CGI"
    schtasks /delete /tn "PHP84_CGI" /f
)
schtasks /create /tn "PHP84_CGI" /tr "\"%~dp0IIS-Config\PHP\php-8.4\php-cgi.exe\" -b 127.0.0.1:9084" /sc onstart /ru System /rl HIGHEST /f
schtasks /run /tn "PHP84_CGI"
if !errorlevel! neq 0 (
    echo Error starting PHP 8.4
) else (
    echo PHP 8.4 started successfully
)
timeout /t 2 > nul
echo.

:: Start Caddy in the background with PowerShell
echo Starting Caddy...
powershell -Command "Start-Process '%~dp0caddy-server\caddy.exe' -ArgumentList 'run --config %~dp0caddy-server\Caddyfile' -WorkingDirectory '%~dp0caddy-server' -WindowStyle Hidden -Verb RunAs"
if !errorlevel! neq 0 (
    echo Error starting Caddy
) else (
    echo Caddy started successfully
)
echo.

:: Save the Caddy PID für späteres Beenden
for /f "tokens=2" %%a in ('tasklist /fi "imagename eq caddy.exe" /nh') do (
    echo %%a > "%~dp0caddy-server\caddy.pid"
)

echo All services have been started!
echo The services will continue running even after closing this window.
echo.
echo To stop the services, use the stop-server.bat script.
echo.
pause
