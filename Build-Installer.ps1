# ============================================================================
#  Build-Installer.ps1
#  ---------------------------------------------------------------------------
#  Empaquette TokenBar.ps1, Get-TokenUsage.ps1, Start-TokenBar.vbs et
#  TokenBar.ico dans UN SEUL fichier : TokenBar-Installer.bat.
#
#  Technique : polyglotte batch/PowerShell. Les toutes premieres lignes sont
#  un script .bat valide qui s'auto-extrait (via "more +N") a partir de sa
#  propre ligne N+1 vers un .ps1 temporaire, puis l'execute. Tout ce qui suit
#  ces lignes d'en-tete est du PowerShell pur (jamais lu par cmd.exe, qui
#  quitte avant via "exit /b"). Le contenu des 4 fichiers sources est
#  embarque en base64 (aucun souci d'echappement : uniquement des
#  caracteres A-Z/a-z/0-9/+//=).
#
#  A relancer a chaque fois que les fichiers sources changent -- ce script
#  est la seule chose a maintenir a la main, TokenBar-Installer.bat est un
#  ARTEFACT GENERE, jamais edite directement.
# ============================================================================

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Get-B64Text([string]$path) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Path $path))
    return [Convert]::ToBase64String($bytes)
}
function Get-B64Bin([string]$path) {
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
}

$b64TokenBar  = Get-B64Text (Join-Path $dir 'TokenBar.ps1')
$b64Usage     = Get-B64Text (Join-Path $dir 'Get-TokenUsage.ps1')
$b64Vbs       = Get-B64Text (Join-Path $dir 'Start-TokenBar.vbs')
$b64Autostart = Get-B64Text (Join-Path $dir 'Install-Autostart.ps1')
$b64Ico       = Get-B64Bin  (Join-Path $dir 'TokenBar.ico')

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

function Write-EmbeddedText([string]$relPath, [string]$b64) {
    $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [IO.File]::WriteAllText((Join-Path $dest $relPath), $text, $utf8Bom)
}
function Write-EmbeddedBinary([string]$relPath, [string]$b64) {
    [IO.File]::WriteAllBytes((Join-Path $dest $relPath), [Convert]::FromBase64String($b64))
}

Write-EmbeddedText   'TokenBar.ps1'          '__B64_TOKENBAR__'
Write-EmbeddedText   'Get-TokenUsage.ps1'    '__B64_USAGE__'
Write-EmbeddedText   'Start-TokenBar.vbs'    '__B64_VBS__'
Write-EmbeddedText   'Install-Autostart.ps1' '__B64_AUTOSTART__'
Write-EmbeddedBinary 'TokenBar.ico'          '__B64_ICO__'

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

$payload = $payload.Replace('__B64_TOKENBAR__', $b64TokenBar)
$payload = $payload.Replace('__B64_USAGE__', $b64Usage)
$payload = $payload.Replace('__B64_VBS__', $b64Vbs)
$payload = $payload.Replace('__B64_AUTOSTART__', $b64Autostart)
$payload = $payload.Replace('__B64_ICO__', $b64Ico)

$payloadLines = $payload -split "`r?`n"
$allLines = @($header) + @($payloadLines)
$outPath = Join-Path $dir 'TokenBar-Installer.bat'
[IO.File]::WriteAllText($outPath, ($allLines -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $false))

Write-Output "Installateur genere : $outPath"
Write-Output ("Taille : {0:N0} Ko" -f ((Get-Item $outPath).Length / 1KB))
