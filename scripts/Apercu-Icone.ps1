# Apercu-Icone.ps1 -- dessine les candidats d'icone en pixels, taille reelle
# et agrandie, pour choisir celle qui reste lisible a 18 x 16.
#
# Sortie : scripts\apercu-icone.png

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 0 = vide (transparent), 1 = contour sombre, 2 = corps clair, 3 = oeil
$candidats = @(
    @{ Nom = 'Cavalier'; Motif = @(
        '000110000',
        '001222100',
        '012222210',
        '122322221',
        '121222221',
        '011122221',
        '000122221',
        '001222221') },
    @{ Nom = 'Cavalier trapu'; Motif = @(
        '000011000',
        '000122100',
        '001222210',
        '012232221',
        '122222221',
        '112222221',
        '000122221',
        '001222211') },
    @{ Nom = 'Pion'; Motif = @(
        '000111000',
        '001222100',
        '001222100',
        '000121000',
        '000121000',
        '001222100',
        '012222210',
        '122222221') },
    @{ Nom = 'Damier'; Motif = @(
        '111111111',
        '122112211',
        '122112211',
        '112211221',
        '112211221',
        '122112211',
        '122112211',
        '111111111') }
)

$COUL = @{
    '1' = [System.Drawing.Color]::FromArgb(14, 14, 16)
    '2' = [System.Drawing.Color]::FromArgb(245, 245, 245)
    '3' = [System.Drawing.Color]::FromArgb(226, 36, 42)
}

function Write-Motif {
    param($G, $Motif, [single]$OX, [single]$OY, [single]$Cell, [bool]$Point)
    $G.SmoothingMode = 'None'
    for ($r = 0; $r -lt $Motif.Count; $r++) {
        $ligne = $Motif[$r]
        for ($c = 0; $c -lt $ligne.Length; $c++) {
            $ch = [string]$ligne[$c]
            if ($ch -eq '0') { continue }
            $b = New-Object System.Drawing.SolidBrush $COUL[$ch]
            $G.FillRectangle($b, ($OX + $c * $Cell), ($OY + $r * $Cell), $Cell, $Cell)
            $b.Dispose()
        }
    }
    if ($Point) {
        # Pastille « c'est a toi » : un carre rouge cercle de noir, colle en
        # haut a droite. En pixels, pas en rond antialiase : le fond de la
        # barre est une couleur de transparence, un bord adouci y ferait un halo.
        $n = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(14, 14, 16))
        $rg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 45, 50))
        $G.FillRectangle($n, ($OX + 6 * $Cell), $OY, (3 * $Cell), (3 * $Cell))
        $G.FillRectangle($rg, ($OX + 6.5 * $Cell), ($OY + 0.5 * $Cell), (2 * $Cell), (2 * $Cell))
        $n.Dispose(); $rg.Dispose()
    }
}

$largeur = 620
$hauteur = 40 + $candidats.Count * 130
$img = New-Object System.Drawing.Bitmap $largeur, $hauteur
$g = [System.Drawing.Graphics]::FromImage($img)
$g.Clear([System.Drawing.Color]::FromArgb(31, 31, 34))

$police = New-Object System.Drawing.Font 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold)
$petite = New-Object System.Drawing.Font 'Segoe UI', 8
$encre  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(230, 230, 230))

for ($i = 0; $i -lt $candidats.Count; $i++) {
    $y = 30 + $i * 130
    $g.DrawString($candidats[$i].Nom, $police, $encre, 20.0, [single]($y - 4))

    # taille reelle dans la barre : cellule de 2 px
    $g.DrawString('taille reelle (18 x 16)', $petite, $encre, 20.0, [single]($y + 22))
    Write-Motif $g $candidats[$i].Motif 30.0 ([single]($y + 44)) 2.0 $false
    Write-Motif $g $candidats[$i].Motif 80.0 ([single]($y + 44)) 2.0 $true

    # agrandissement x8 pour juger la forme
    $g.DrawString('agrandi 8x, avec et sans pastille', $petite, $encre, 160.0, [single]($y + 22))
    Write-Motif $g $candidats[$i].Motif 160.0 ([single]($y + 40)) 8.0 $false
    Write-Motif $g $candidats[$i].Motif 260.0 ([single]($y + 40)) 8.0 $true
}

$police.Dispose(); $petite.Dispose(); $encre.Dispose()
$sortie = Join-Path $PSScriptRoot 'apercu-icone.png'
$img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $img.Dispose()
Write-Host ("Image ecrite : " + $sortie)
