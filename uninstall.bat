@echo off
setlocal
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\HabitWidget.lnk"

if exist "%LNK%" (
    del "%LNK%"
    echo Removed: %LNK%
) else (
    echo Not found: %LNK%
)

echo.
echo Autostart removed.
echo If the widget is currently running, right-click it and choose "Close widget"
echo (or log out / reboot).
pause
