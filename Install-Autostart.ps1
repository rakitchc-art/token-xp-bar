# ============================================================================
#  Install-Autostart.ps1
#  ---------------------------------------------------------------------------
#  Fait demarrer la barre automatiquement a l'ouverture de ta session Windows.
#  La barre reste discrete (cachee) et ne s'affiche que si VS Code est ouvert.
#
#  Pour ACTIVER    :  powershell -File Install-Autostart.ps1
#  Pour DESACTIVER :  powershell -File Install-Autostart.ps1 -Remove
# ============================================================================
param([switch] $Remove)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$vbs       = Join-Path $scriptDir 'Start-TokenBar.vbs'
$startup   = [Environment]::GetFolderPath('Startup')          # dossier Demarrage
$lnkPath   = Join-Path $startup 'TokenBar.lnk'

if ($Remove) {
    if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force; "Demarrage automatique DESACTIVE." }
    else { "Il n'y avait pas de demarrage automatique." }
    return
}

# Cree le raccourci .lnk dans le dossier Demarrage
$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnkPath)
$sc.TargetPath       = 'wscript.exe'
$sc.Arguments        = '"' + $vbs + '"'
$sc.WorkingDirectory = $scriptDir
$sc.Description       = 'Barre de tokens Claude Code'
$sc.Save()

"Demarrage automatique ACTIVE."
"Raccourci cree ici : $lnkPath"
