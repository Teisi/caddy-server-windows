@echo off
echo Checking service status...
echo.

echo PHP 8.2:
schtasks /query /tn "PHP82_CGI" >nul 2>&1
if !errorlevel! equ 0 (
    echo Running
) else (
    echo Stopped
)
echo.

echo PHP 8.4:
schtasks /query /tn "PHP84_CGI" >nul 2>&1
if !errorlevel! equ 0 (
    echo Running
) else (
    echo Stopped
)
echo.

echo Caddy:
sc query "CaddyServer" >nul 2>&1
if !errorlevel! equ 0 (
    echo Running
) else (
    echo Stopped
)
echo.

pause
