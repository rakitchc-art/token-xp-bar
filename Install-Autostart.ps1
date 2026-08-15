# ============================================================================
#  Install-Autostart.ps1
#  ---------------------------------------------------------------------------
#  Fait demarrer la barre automatiquement a l'ouverture de ta session Windows,
#  et pose un raccourci sur le Bureau (les deux avec l'icone TokenBar.ico).
#  La barre reste discrete (cachee) et ne s'affiche que si VS Code est ouvert.
#
#  Pour ACTIVER    :  powershell -File Install-Autostart.ps1
#  Pour DESACTIVER :  powershell -File Install-Autostart.ps1 -Remove
# ============================================================================
param([switch] $Remove)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$vbs       = Join-Path $scriptDir 'Start-TokenBar.vbs'
$icoPath   = Join-Path $scriptDir 'TokenBar.ico'
$startup   = [Environment]::GetFolderPath('Startup')          # dossier Demarrage
$desktop   = [Environment]::GetFolderPath('Desktop')
$lnkStartup   = Join-Path $startup 'TokenBar.lnk'
$lnkDesktop   = Join-Path $desktop 'TokenBar.lnk'

if ($Remove) {
    if (Test-Path $lnkStartup) { Remove-Item $lnkStartup -Force; "Demarrage automatique DESACTIVE." }
    else { "Il n'y avait pas de demarrage automatique." }
    if (Test-Path $lnkDesktop) { Remove-Item $lnkDesktop -Force; "Raccourci Bureau retire." }
    return
}

function New-TokenBarShortcut($lnkPath) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath       = 'wscript.exe'
    $sc.Arguments        = '"' + $vbs + '"'
    $sc.WorkingDirectory = $scriptDir
    $sc.Description      = 'TokenBar - Barre de tokens Claude Code'
    if (Test-Path $icoPath) { $sc.IconLocation = $icoPath }
    $sc.Save()
}

New-TokenBarShortcut $lnkStartup
New-TokenBarShortcut $lnkDesktop

"Demarrage automatique ACTIVE."
"Raccourci Demarrage : $lnkStartup"
"Raccourci Bureau    : $lnkDesktop"
