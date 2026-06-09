@echo off
setlocal
set "HERE=%~dp0"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "LNK=%STARTUP%\HabitWidget.lnk"

echo Creating startup shortcut:
echo   %LNK%
echo Target:
echo   %HERE%HabitWidget.vbs
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = New-Object -ComObject WScript.Shell; $l = $s.CreateShortcut('%LNK%'); $l.TargetPath = '%HERE%HabitWidget.vbs'; $l.WorkingDirectory = '%HERE%'; $l.Save()"

if errorlevel 1 (
    echo.
    echo FAILED to create shortcut.
    pause
    exit /b 1
)

echo Starting widget now...
start "" "%HERE%HabitWidget.vbs"
echo.
echo Installed. Widget will auto-start on next login.
pause
