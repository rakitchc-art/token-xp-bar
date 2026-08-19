# Apercu-Fenetre.ps1 -- dessine la fenetre de jeu HORS ECRAN, sans l'ouvrir.
#
# Possible parce que tout le dessin vit dans Draw-FenetreEchecs, une vraie
# fonction, et pas dans le gestionnaire Paint. On peut donc juger le rendu
# (et voir peter une exception) sans boucle de messages ni fenetre a tuer.
#
# Trois vues :
#   1. taille par defaut, milieu de partie, cavalier selectionne
#   2. la MEME chose en grand -- c'est le controle qui compte pour Nisse :
#      tout doit grandir ensemble, pas seulement le plateau
#   3. le choix de promotion ouvert
#
# Sortie : scripts\fenetre-1-normale.png, -2-grande.png, -3-promotion.png

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Fenetre-Echecs.ps1')

function Save-Vue {
    param($Vue, [int]$L, [int]$H, [string]$Nom)
    Update-DispositionEchecs $Vue $L $H
    $img = New-Object System.Drawing.Bitmap $L, $H
    $g = [System.Drawing.Graphics]::FromImage($img)
    Draw-FenetreEchecs $g $Vue
    $chemin = Join-Path $PSScriptRoot $Nom
    $img.Save($chemin, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $img.Dispose()
    Write-Host ("  " + $Nom + "   (" + $L + " x " + $H + ", case de " + $Vue.Case + " px)")
}

# --- Partie 1 : gambit Evans, cavalier f3 selectionne ---------------------
$partie = New-Partie -MaCouleur 'w' -MonNom 'Dova' -NomAdversaire 'Nisse' `
                     -MesPoints 2.5 -SesPoints 1.5 -Local
$ouverture = @('e2e4','e7e5','g1f3','b8c6','f1c4','f8c5','b2b4','c5b4',
               'c2c3','b4a5','d2d4','e5d4')
if (-not (Set-PartieDepuisCoups $partie $ouverture)) {
    throw 'La sequence d ouverture a ete refusee par le moteur.'
}
Write-Host ("Coups rejoues : " + ($partie.San -join ' '))

$vue = New-VueEchecs -Partie $partie -Journal (Join-Path $PSScriptRoot 'apercu-erreurs.log')
$vue.Selection = ConvertTo-CaseIndex 'f3'
$vue.Cibles    = @(Get-CoupsDepuis $partie ($vue.Selection))

Write-Host 'Rendus :'
Save-Vue $vue 924 641  'fenetre-1-normale.png'
Save-Vue $vue 1520 1040 'fenetre-2-grande.png'

# --- Partie 2 : promotion ouverte ----------------------------------------
$p2 = New-Partie -MaCouleur 'w' -MonNom 'Dova' -NomAdversaire 'Nisse' `
                 -MesPoints 2.5 -SesPoints 1.5 -Local `
                 -Depart '4k2r/1P6/8/8/8/6n1/5PPP/4K2R w Kk - 0 30'
$vue2 = New-VueEchecs -Partie $p2 -Journal (Join-Path $PSScriptRoot 'apercu-erreurs.log')
Update-DispositionEchecs $vue2 924 641

$depart  = ConvertTo-CaseIndex 'b7'
$arrivee = ConvertTo-CaseIndex 'b8'
$cands   = @(Get-CoupVers $p2 $depart $arrivee)
if ($cands.Count -ne 4) { throw ("Promotion attendue en 4 choix, obtenu " + $cands.Count) }
$vue2.Promo = @{ Depart = $depart; Arrivee = $arrivee; Candidats = $cands; Cases = @() }

Save-Vue $vue2 924 641 'fenetre-3-promotion.png'

$log = Join-Path $PSScriptRoot 'apercu-erreurs.log'
if (Test-Path $log) {
    Write-Host 'ATTENTION : des erreurs de dessin ont ete journalisees.' -ForegroundColor Red
    Write-Host (Get-Content $log -Raw)
} else {
    Write-Host 'Aucune erreur de dessin.'
}
