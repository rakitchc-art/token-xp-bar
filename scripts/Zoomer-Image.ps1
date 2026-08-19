# Zoomer-Image.ps1 -- agrandit une image au plus proche voisin, pour juger du
# pixel. Un agrandissement lisse (le defaut) inventerait des degrades et
# masquerait exactement ce qu'on cherche a verifier.
#
#   .\Zoomer-Image.ps1 -Entree ..\scripts\barre.png -Facteur 6

param(
    [Parameter(Mandatory = $true)][string]$Entree,
    [int]$Facteur = 6,
    [string]$Sortie = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $Sortie) {
    $Sortie = [System.IO.Path]::ChangeExtension($Entree, $null) + 'x' + $Facteur + '.png'
}

$src = [System.Drawing.Image]::FromFile((Resolve-Path $Entree).Path)
$img = New-Object System.Drawing.Bitmap ($src.Width * $Facteur), ($src.Height * $Facteur)
$g = [System.Drawing.Graphics]::FromImage($img)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.DrawImage($src, 0, 0, $img.Width, $img.Height)
$img.Save($Sortie, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $img.Dispose(); $src.Dispose()
Write-Host ("Image ecrite : " + $Sortie + "  (" + ($src.Width * $Facteur) + " x " + ($src.Height * $Facteur) + ")")
