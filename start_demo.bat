@echo off
echo ===============================================
echo   Smart Traffic Alert System - Demo Starter
echo ===============================================
echo.
echo NOTE: Pehle Pixel 6 emulator start kar lo (Android Studio se),
echo aur home screen aane tak ruko. Phir yahan koi bhi key dabao.
echo.
pause

echo Backend start ho raha hai...
start "Flask Backend" /d "C:\MyApps\SMART TRAFFIC\backend" cmd /k "venv\Scripts\activate.bat && python app.py"

echo 5 second ruko, backend ko start hone do...
timeout /t 5 /nobreak >nul

echo Flutter app start ho rahi hai...
start "Flutter App" /d "C:\MyApps\SMART TRAFFIC\traffic_alert_app" cmd /k "flutter run -d emulator-5554"

echo.
echo Done! Dono windows khul gayi hain. Inhe band mat karna.
timeout /t 5 >nul
