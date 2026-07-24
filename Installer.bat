@echo off
chcp 65001 >nul
title Installation de la barre de tokens Claude
set "DEST=%LOCALAPPDATA%\TokenBar"

echo.
echo   ============================================
echo     Installation de la barre de tokens Claude
echo   ============================================
echo.
echo   Copie des fichiers vers :
echo   %DEST%
echo.

if not exist "%DEST%" mkdir "%DEST%"
copy /Y "%~dp0Get-TokenUsage.ps1"    "%DEST%\" >nul
copy /Y "%~dp0TokenBar.ps1"          "%DEST%\" >nul
copy /Y "%~dp0Start-TokenBar.vbs"    "%DEST%\" >nul
copy /Y "%~dp0Install-Autostart.ps1" "%DEST%\" >nul
if not exist "%DEST%\config.json" copy /Y "%~dp0config.json" "%DEST%\" >nul

echo   Activation du demarrage automatique...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\Install-Autostart.ps1" >nul

echo   Lancement de la barre...
start "" wscript.exe "%DEST%\Start-TokenBar.vbs"

echo.
echo   ============================================
echo     Termine !
echo   ============================================
echo.
echo   - La barre se lancera toute seule avec Windows.
echo   - Elle apparait EN HAUT A DROITE quand VS Code
echo     est la fenetre active.
echo   - Ouvre VS Code (avec Claude Code) pour la voir.
echo.
echo   Astuce : clic droit sur la barre = menu (Fermer).
echo            Tu peux la deplacer en la glissant.
echo.
pause
