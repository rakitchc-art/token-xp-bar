# Test-BarreEchecs.ps1 -- eprouve la barre AVEC les echecs, dans un bac a sable.
#
# Rien de l'installation reelle n'est touche : le projet est recopie dans un
# dossier jetable, avec son propre config.json et son propre serveur sur un
# port libre. La barre de Dova qui tourne en ce moment n'est pas concernee.
#
# La copie est retouchee sur deux points, et deux seulement :
#   - la barre ne se cache plus quand VS Code n'est pas au premier plan
#     (sinon il n'y a rien a photographier) ;
#   - une minuterie photographie la fenetre puis ferme tout.
# Le fichier livre, lui, n'est pas modifie.
#
# Sortie : scripts\barre-avec-echecs.png

param(
    # Sans ce commutateur, le bac a sable est configure avec un serveur.
    # Avec, aucun reglage d'echecs n'est ecrit : c'est le controle qui prouve
    # que la barre reste EXACTEMENT celle d'avant quand le jeu dort.
    [switch]$SansEchecs,
    # Permet de faire tourner une AUTRE version de TokenBar.ps1 (typiquement
    # celle d'avant les echecs, sortie de git) pour comparer les deux rendus.
    [string]$SourceBarre = '',
    [string]$NomSortie = ''
)

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
if (-not $NomSortie) {
    $NomSortie = $(if ($SansEchecs) { 'barre-sans-echecs.png' } else { 'barre-avec-echecs.png' })
}
$sortie = Join-Path $PSScriptRoot $NomSortie
if (Test-Path $sortie) { Remove-Item $sortie -Force }

$bac = Join-Path $env:TEMP ('bac-echecs-' + (Get-Random))
New-Item -ItemType Directory -Path $bac -Force | Out-Null
Write-Host ("Bac a sable : " + $bac)

foreach ($n in @('TokenBar.ps1', 'Get-TokenUsage.ps1', 'TokenBar.ico')) {
    Copy-Item (Join-Path $racine $n) (Join-Path $bac $n) -Force
}
if ($SourceBarre) {
    Copy-Item $SourceBarre (Join-Path $bac 'TokenBar.ps1') -Force
    Write-Host ("Barre testee : " + $SourceBarre)
}
Copy-Item (Join-Path $racine 'echecs') (Join-Path $bac 'echecs') -Recurse -Force

# --- serveur de test ------------------------------------------------------
$ecouteur = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
$ecouteur.Start(); $port = $ecouteur.LocalEndpoint.Port; $ecouteur.Stop()

$etatFichier = Join-Path $bac 'etat-serveur.json'
$code = 'code-de-test-1234'
$env:ECHECS_CODE = $code
$env:ECHECS_PORT = [string]$port
$env:ECHECS_HOTE = '127.0.0.1'
$env:ECHECS_ETAT = $etatFichier

$srv = Start-Process -FilePath 'node' -ArgumentList (Join-Path $racine 'serveur\echecs-serveur.js') `
                     -PassThru -WindowStyle Hidden
$pret = $false
for ($i = 0; $i -lt 60; $i++) {
    try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $c.Close(); $pret = $true; break }
    catch { Start-Sleep -Milliseconds 150 }
}
if (-not $pret) { throw 'serveur de test non demarre' }
Write-Host ("Serveur de test : 127.0.0.1:" + $port)

# --- config du bac a sable ------------------------------------------------
$cfg = @{ PosRight = 700; PosY = 60; LiveFactor = 1.0 }
if (-not $SansEchecs) {
    $cfg['EchecsNom']     = 'Dova'
    $cfg['EchecsAdresse'] = '127.0.0.1:' + $port
    $cfg['EchecsCode']    = $code
}
$sansBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $bac 'config.json'), ($cfg | ConvertTo-Json), $sansBom)

# --- retouches de la copie ------------------------------------------------
$src = [System.IO.File]::ReadAllText((Join-Path $bac 'TokenBar.ps1'), [System.Text.Encoding]::UTF8)

$avant = $src
$src = $src.Replace('$visTimer.Add_Tick({ Sync-Visibility }); $visTimer.Start()',
                    '$visTimer.Add_Tick({ }); $visTimer.Start()')
if ($src -eq $avant) { throw 'retouche 1 (minuterie de visibilite) sans effet : le fichier a change' }

$avant = $src
$src = $src.Replace('$form.Add_Shown({ Sync-Visibility })', '$form.Add_Shown({ })')
if ($src -eq $avant) { throw 'retouche 2 (affichage initial) sans effet' }

$capture = @'
$form.Show()
$capTimer = New-Object System.Windows.Forms.Timer
$capTimer.Interval = 5000
$capTimer.Add_Tick({
    $capTimer.Stop()
    Write-Host ("hauteur fenetre : " + $form.Height)
    Write-Host ("mon tour : " + $script:echecsMonTour)
    Write-Host ("erreur echecs : '" + $script:echecsErreur + "'")
    $coups = 'aucun etat'
    if ($script:echecsEtat) { $coups = 'coups=' + @($script:echecsEtat.coups).Count + ' blancs=' + $script:echecsEtat.joueurs.w }
    Write-Host ("etat serveur : " + $coups)
    $img = New-Object System.Drawing.Bitmap $form.Width, $form.Height
    $form.DrawToBitmap($img, (New-Object System.Drawing.Rectangle 0, 0, $form.Width, $form.Height))
    $img.Save($env:TOKENBAR_CAPTURE, [System.Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()
    $form.Close()
})
$capTimer.Start()
$garde = New-Object System.Windows.Forms.Timer
$garde.Interval = 25000
$garde.Add_Tick({ $garde.Stop(); Write-Host 'CHIEN DE GARDE'; $form.Close() })
$garde.Start()
[System.Windows.Forms.Application]::Run($form)
'@

$avant = $src
$src = $src.Replace('[System.Windows.Forms.Application]::Run($form)', $capture)
if ($src -eq $avant) { throw 'retouche 3 (capture) sans effet' }

# BOM obligatoire : le fichier contient des accents et PowerShell 5.1 lirait
# de l'ANSI sans lui.
$avecBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText((Join-Path $bac 'TokenBar.ps1'), $src, $avecBom)

# --- lancement ------------------------------------------------------------
$env:TOKENBAR_CAPTURE = $sortie
Write-Host 'Lancement de la barre du bac a sable...'
[void](Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', (Join-Path $bac 'TokenBar.ps1')) `
    -PassThru -Wait -NoNewWindow -RedirectStandardOutput (Join-Path $bac 'sortie.txt') `
    -RedirectStandardError (Join-Path $bac 'erreurs.txt'))

Write-Host ''
Write-Host '--- Sortie de la barre ---'
if (Test-Path (Join-Path $bac 'sortie.txt')) { Get-Content (Join-Path $bac 'sortie.txt') | ForEach-Object { Write-Host ('  ' + $_) } }
$errFichier = Join-Path $bac 'erreurs.txt'
if ((Test-Path $errFichier) -and (Get-Item $errFichier).Length -gt 0) {
    Write-Host '--- ERREURS ---' -ForegroundColor Red
    Get-Content $errFichier | Select-Object -First 25 | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Red }
}

# --- menage ---------------------------------------------------------------
if ($srv -and -not $srv.HasExited) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
if (Get-Process -Id $srv.Id -ErrorAction SilentlyContinue) {
    Write-Host 'ATTENTION : le serveur de test tourne encore.' -ForegroundColor Red
} else { Write-Host 'Serveur de test arrete.' }

if (Test-Path $sortie) {
    Write-Host ("Image ecrite : " + $sortie)
} else {
    Write-Host 'AUCUNE IMAGE PRODUITE.' -ForegroundColor Red
}
Remove-Item $bac -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("Bac a sable supprime : " + (-not (Test-Path $bac)))
