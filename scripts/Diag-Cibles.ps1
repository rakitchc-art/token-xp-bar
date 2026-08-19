# Diag-Cibles.ps1 -- verifie que les cases pointees sont bien TOUTES celles ou
# la piece peut aller, et rend l'image telle que la barre la dessine.
#
# Sortie : scripts\diag-cibles.png

param([string]$Case = 'd1')

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')

$partie = New-Partie -MonNom 'Dova'
if (-not (Set-PartieDepuisCoups $partie @('d2d4','d7d5','c2c4','e7e6','c4d5','e6d5'))) {
    throw 'sequence refusee'
}

$i = ConvertTo-CaseIndex $Case
Write-Host ("Piece sur " + $Case + " : '" + $partie.Pos.B[$i] + "'")

# Ce que le MOTEUR dit, sans passer par l'interface.
$tousLegaux = @(Get-CoupsLegaux $partie.Pos)
$depuisMoteur = @()
foreach ($c in $tousLegaux) {
    if (($c -band 63) -eq $i) { $depuisMoteur += (ConvertFrom-CaseIndex ((($c -shr 6) -band 63))) }
}
Write-Host ("Moteur  : " + ($depuisMoteur -join ' ') + "   (" + $depuisMoteur.Count + ")")

# Ce que l'INTERFACE demande au moteur.
$cibles = @(Get-CoupsDepuis $partie $i)
$depuisUI = @()
foreach ($t in $cibles) { $depuisUI += (ConvertFrom-CaseIndex $t) }
Write-Host ("Interface : " + ($depuisUI -join ' ') + "   (" + $depuisUI.Count + ")")

if ($depuisMoteur.Count -ne $depuisUI.Count) {
    Write-Host 'ECART ENTRE LE MOTEUR ET L INTERFACE' -ForegroundColor Red
} else {
    Write-Host 'moteur et interface d accord' -ForegroundColor Green
}

# Et ce qui est reellement PEINT : c'est la seule chose que Dova voit.
$case = 29
$img = New-Object System.Drawing.Bitmap (8 * $case), (8 * $case)
$g = [System.Drawing.Graphics]::FromImage($img)
Draw-Echiquier $g 0 0 $case $partie.Pos @{
    Retourne       = $false
    Selection      = $i
    CoupsPossibles = $cibles
    DernierDepart  = $partie.DernierDepart
    DernierArrivee = $partie.DernierArrivee
}
$sortie = Join-Path $PSScriptRoot 'diag-cibles.png'
$img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $img.Dispose()
Write-Host ("Image : " + $sortie)
