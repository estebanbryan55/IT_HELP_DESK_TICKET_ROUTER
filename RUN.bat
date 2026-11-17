@echo off
rem Starts the Laravel API and the Flutter Web app in two windows.
cd /d "%~dp0"

start "Help Desk API (keep open)" cmd /k "cd /d "%~dp0backend" && php artisan serve --port=8010"

timeout /t 3 /nobreak >nul

start "Help Desk Web App (keep open)" cmd /k "cd /d "%~dp0frontend" && flutter run -d chrome --web-port 5000"

echo.
echo Two windows were opened. Chrome will open at http://localhost:5000 in about a minute.
echo Login: student@example.test   Password: Demo-Pass-2026!
echo.
pause
