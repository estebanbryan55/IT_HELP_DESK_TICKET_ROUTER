@echo off
rem Week 15: starts the Laravel API (port 8015) and the Flutter Web app (port 5015) in two windows.
rem Uses different ports from Week 14 (8000/5000) so both weeks can run side by side.
cd /d "%~dp0"

start "Week 15 Help Desk API (keep open)" cmd /k "cd /d "%~dp0backend" && php artisan serve --port=8015"

timeout /t 3 /nobreak >nul

start "Week 15 Help Desk Web App (keep open)" cmd /k "cd /d "%~dp0frontend" && flutter run -d chrome --web-port 5015 --dart-define=API_BASE_URL=http://127.0.0.1:8015/api/v1"

echo.
echo Two windows were opened. Chrome will open at http://localhost:5015 in about a minute.
echo Login: student@example.test   Password: Demo-Pass-2026!
echo Health check: http://127.0.0.1:8015/api/v1/health
echo.
pause
