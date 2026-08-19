# Capture-Echecs.ps1 -- ouvre la VRAIE fenetre et la photographie.
#
# Le rendu hors ecran (Apercu-Fenetre.ps1) prouve que le dessin est juste ;
# il ne prouve pas que la fenetre s'ouvre, se met en page toute seule, et
# survit a la boucle de messages. Ce script-ci fait ce second travail.
#
# Garde-fou : un chien de garde ferme tout au bout de 30 s, quoi qu'il arrive.
# Sans lui, une exception non geree ouvre une boite modale Windows qui bloque
# le processus indefiniment -- exactement ce qui est arrive une fois.
#
# Sortie : scripts\vraie-fenetre.png

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Fenetre-Echecs.ps1')

$journal = Join-Path $PSScriptRoot 'capture-erreurs.log'
if (Test-Path $journal) { Remove-Item $journal -Force }

$partie = New-Partie -MaCouleur 'w' -MonNom 'Dova' -NomAdversaire 'Nisse' `
                     -MesPoints 2.5 -SesPoints 1.5 -Local
$ouverture = @('e2e4','e7e5','g1f3','b8c6','f1c4','f8c5','b2b4','c5b4',
               'c2c3','b4a5','d2d4','e5d4')
if (-not (Set-PartieDepuisCoups $partie $ouverture)) { throw 'Ouverture refusee.' }

$h = Show-FenetreEchecs -Partie $partie -Journal $journal `
                        -CheminIcone (Join-Path $racine 'TokenBar.ico')

# On simule un clic reel sur le cavalier f3 : c'est le chemin d'interaction
# complet (coordonnees ecran -> case -> coups possibles) qui est eprouve,
# pas seulement l'affectation directe des champs de la vue.
$ptF3 = Get-PointDepuisCase $h.Vue (ConvertTo-CaseIndex 'f3')
[void](Invoke-ClicEchecs $h.Vue ($ptF3.X + 10) ($ptF3.Y + 10) $null)
if ($h.Vue.Selection -ne (ConvertTo-CaseIndex 'f3')) {
    Write-Host 'ECHEC : le clic sur f3 n a pas selectionne la case.' -ForegroundColor Red
} else {
    Write-Host ("Clic sur f3 : " + @($h.Vue.Cibles).Count + " coups possibles pointes.")
}
$h.Panneau.Invalidate()

$sortie = Join-Path $PSScriptRoot 'vraie-fenetre.png'

$chrono = New-Object System.Windows.Forms.Timer
$chrono.Interval = 900
$chrono.Add_Tick({
    $chrono.Stop()
    $img = New-Object System.Drawing.Bitmap $h.Form.Width, $h.Form.Height
    $h.Form.DrawToBitmap($img, (New-Object System.Drawing.Rectangle 0, 0, $h.Form.Width, $h.Form.Height))
    $img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)

    # Une capture peut « reussir » en ne contenant qu'un aplat gris : on
    # compte les couleurs distinctes plutot que de croire le Save().
    $teintes = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($x = 0; $x -lt $img.Width; $x += 7) {
        for ($y = 0; $y -lt $img.Height; $y += 7) { [void]$teintes.Add($img.GetPixel($x, $y).ToArgb()) }
    }
    Write-Host ("Capture : " + $img.Width + " x " + $img.Height + ", " + $teintes.Count + " teintes distinctes")
    if ($teintes.Count -lt 40) { Write-Host 'ECHEC : capture quasi vide.' -ForegroundColor Red }
    $img.Dispose()

    $h.Form.Close()
    [System.Windows.Forms.Application]::ExitThread()
}.GetNewClosure())
$chrono.Start()

$chienDeGarde = New-Object System.Windows.Forms.Timer
$chienDeGarde.Interval = 30000
$chienDeGarde.Add_Tick({
    $chienDeGarde.Stop()
    Write-Host 'CHIEN DE GARDE : fermeture forcee au bout de 30 s.' -ForegroundColor Red
    try { $h.Form.Close() } catch { }
    [System.Windows.Forms.Application]::ExitThread()
}.GetNewClosure())
$chienDeGarde.Start()

[System.Windows.Forms.Application]::Run()

if (Test-Path $journal) {
    Write-Host 'ATTENTION : des erreurs ont ete journalisees pendant l affichage.' -ForegroundColor Red
    Write-Host (Get-Content $journal -Raw)
} else {
    Write-Host 'Aucune erreur pendant l affichage.'
}
Write-Host ("Image ecrite : " + $sortie)
