@echo off
chcp 65001 >nul
title Desinstallation de la barre de tokens Claude
set "DEST=%LOCALAPPDATA%\TokenBar"

echo.
echo   Retrait du demarrage automatique...
if exist "%DEST%\Install-Autostart.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\Install-Autostart.ps1" -Remove
) else (
    echo   (fichiers introuvables, rien a faire)
)

echo.
echo   C'est fait. Pour fermer la barre maintenant :
echo   clic droit dessus  ^>  Fermer.
echo.
echo   Pour tout supprimer, efface ce dossier :
echo   %DEST%
echo.
pause
