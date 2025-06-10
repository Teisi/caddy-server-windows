@echo off
echo Checking ports 80 and 443...
echo.
echo Port 80:
netstat -ano | findstr :80
echo.
echo Port 443:
netstat -ano | findstr :443
echo.
pause
