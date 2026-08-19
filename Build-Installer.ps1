# ============================================================================
#  Build-Installer.ps1
#  ---------------------------------------------------------------------------
#  Empaquette tous les fichiers de TokenBar dans UN SEUL fichier :
#  TokenBar-Installer.bat.
#
#  Technique : polyglotte batch/PowerShell. Les toutes premieres lignes sont
#  un script .bat valide qui s'auto-extrait (via "more +N") a partir de sa
#  propre ligne N+1 vers un .ps1 temporaire, puis l'execute. Tout ce qui suit
#  ces lignes d'en-tete est du PowerShell pur (jamais lu par cmd.exe, qui
#  quitte avant via "exit /b").
#
#  Chaque fichier est embarque en base64 de ses OCTETS BRUTS, jamais de son
#  texte decode : c'est ce qui garantit que les accents et les marques d'ordre
#  d'octets (BOM) arrivent intacts. Un aller-retour decodage/reencodage
#  suffirait a transformer un "e" accentue en deux caracteres, ou a perdre le
#  BOM sans lequel PowerShell 5.1 lit un .ps1 accentue comme de l'ANSI.
#
#  A RELANCER a chaque fois qu'un fichier source change : TokenBar-Installer.bat
#  est un ARTEFACT GENERE, jamais edite a la main.
# ============================================================================

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Chemins RELATIFS : ils sont recrees tels quels dans le dossier d'installation.
$fichiers = @(
    'TokenBar.ps1',
    'Get-TokenUsage.ps1',
    'Start-TokenBar.vbs',
    'Install-Autostart.ps1',
    'TokenBar.ico',
    'echecs\Moteur-Echecs.ps1',
    'echecs\Rendu-Echiquier.ps1',
    'echecs\Partie-Echecs.ps1',
    'echecs\Client-Serveur.ps1',
    'echecs\Plateau-Barre.ps1',
    'echecs\Integration-TokenBar.ps1',
    'echecs\LISEZMOI-echecs.md',
    'serveur\echecs-serveur.js'
)

$lignesEcriture = @()
foreach ($rel in $fichiers) {
    $complet = Join-Path $dir $rel
    if (-not (Test-Path $complet)) { throw ("Fichier source introuvable : " + $rel) }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($complet))
    $lignesEcriture += ("Write-Fichier '" + $rel + "' '" + $b64 + "'")
}

# ---- En-tete .bat (nombre de lignes CONNU -> calcule le "more +N") --------
$header = @(
    '@echo off',
    'title Installation de TokenBar',
    'setlocal',
    'set "PS1=%TEMP%\tokenbar-install-%RANDOM%.ps1"',
    'more +__SKIP__ "%~f0" > "%PS1%"',
    'powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"',
    'set EC=%ERRORLEVEL%',
    'del "%PS1%" >nul 2>&1',
    'exit /b %EC%'
)
$skip = $header.Count
$header = $header -replace '__SKIP__', $skip

# ---- Charge utile PowerShell (tout ce qui suit l'en-tete) -----------------
$payload = @'
$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'TokenBar'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

function Write-Fichier([string]$relPath, [string]$b64) {
    $cible = Join-Path $dest $relPath
    $dossier = Split-Path -Parent $cible
    if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Force -Path $dossier | Out-Null }
    [IO.File]::WriteAllBytes($cible, [Convert]::FromBase64String($b64))
}

__ECRITURES__

$vbs = Join-Path $dest 'Start-TokenBar.vbs'
$ico = Join-Path $dest 'TokenBar.ico'
$startup = [Environment]::GetFolderPath('Startup')
$desktop = [Environment]::GetFolderPath('Desktop')

function New-TokenBarShortcut([string]$lnkPath) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath       = 'wscript.exe'
    $sc.Arguments        = '"' + $vbs + '"'
    $sc.WorkingDirectory  = $dest
    $sc.Description       = 'TokenBar - Barre de tokens Claude Code'
    if (Test-Path $ico) { $sc.IconLocation = $ico }
    $sc.Save()
}
New-TokenBarShortcut (Join-Path $startup 'TokenBar.lnk')
New-TokenBarShortcut (Join-Path $desktop 'TokenBar.lnk')

Start-Process wscript.exe -ArgumentList ('"' + $vbs + '"')

Write-Host ""
Write-Host "  TokenBar est installe et lance !"
Write-Host "  Ouvre VS Code (avec Claude Code connecte) pour la voir"
Write-Host "  apparaitre en haut a droite."
Write-Host ""
Read-Host "  Appuie sur Entree pour fermer cette fenetre"
'@

$payload = $payload.Replace('__ECRITURES__', ($lignesEcriture -join "`r`n"))

$payloadLines = $payload -split "`r?`n"
$allLines = @($header) + @($payloadLines)
$outPath = Join-Path $dir 'TokenBar-Installer.bat'
[IO.File]::WriteAllText($outPath, ($allLines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $false))

Write-Output ("Installateur genere : " + $outPath)
Write-Output ("Fichiers embarques  : " + $fichiers.Count)
Write-Output ("Taille              : {0:N0} Ko" -f ((Get-Item $outPath).Length / 1KB))
