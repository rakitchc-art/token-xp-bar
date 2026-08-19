# Apercu-Echiquier.ps1 -- fabrique une image du plateau pour la regarder.
#
# Sert a juger le rendu AVANT de construire la fenetre : on voit le damier,
# les douze silhouettes en grand, et les etats speciaux (dernier coup joue,
# case selectionnee, coups possibles, roi en echec) sur une seule image.
#
# Sortie : scripts\apercu-echiquier.png

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')

$marge   = 30
$caseA   = 70.0
$plateau = 8 * $caseA
$bandeH  = 210
$largeur = [int](2 * $plateau + 3 * $marge)
$hauteur = [int]($marge + $plateau + $marge + $bandeH + $marge)

$img = New-Object System.Drawing.Bitmap $largeur, $hauteur
$g   = [System.Drawing.Graphics]::FromImage($img)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear($script:Palette.Fond)

# --- Plateau de gauche : position de depart, sans decoration -------------
$depart = New-Position
Draw-Echiquier $g $marge $marge $caseA $depart

# --- Plateau de droite : le mat du berger, avec tous les etats -----------
# Blancs viennent de jouer Dxf7 mat : dernier coup surligne (h5 -> f7),
# halo rouge sur le roi noir, et pastilles autour d'un cavalier selectionne.
$mat = New-Position 'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4'
$x2 = $marge + $plateau + $marge

# Cases visees par le cavalier c6, pour montrer disques et anneaux.
$selection = ConvertTo-CaseIndex 'c6'
$vues = @((ConvertTo-CaseIndex 'b4'), (ConvertTo-CaseIndex 'd4'),
          (ConvertTo-CaseIndex 'a5'), (ConvertTo-CaseIndex 'b8'),
          (ConvertTo-CaseIndex 'd8'), (ConvertTo-CaseIndex 'e7'))

Draw-Echiquier $g $x2 $marge $caseA $mat @{
    DernierDepart  = (ConvertTo-CaseIndex 'h5')
    DernierArrivee = (ConvertTo-CaseIndex 'f7')
    CaseEchec      = (ConvertTo-CaseIndex 'e8')
    Selection      = $selection
    CoupsPossibles = $vues
}

# --- Bandeau du bas : les douze pieces en grand --------------------------
# Chaque piece est posee sur une case de chaque couleur, pour verifier
# qu'aucune ne disparait sur son fond.
$pieces = @('K','Q','R','B','N','P','k','q','r','b','n','p')
$caseB  = 100.0
$y0     = $marge + $plateau + $marge
$x0     = ($largeur - 12 * $caseB) / 2

for ($i = 0; $i -lt 12; $i++) {
    $x = $x0 + $i * $caseB
    # Alternance des fonds, et inversion sur la seconde moitie pour que
    # chaque piece soit vue une fois sur clair et une fois sur sombre.
    $claire = ((($i % 2) -eq 0) -ne ($i -ge 6))
    $fond = $(if ($claire) { $script:Palette.CaseClaire } else { $script:Palette.CaseSombre })
    $b = New-Object System.Drawing.SolidBrush $fond
    $g.FillRectangle($b, $x, $y0, $caseB, $caseB)
    $b.Dispose()
    Draw-Piece $g ([char]$pieces[$i]) $x $y0 $caseB
}

# Legende
$police = New-Object System.Drawing.Font 'Segoe UI', 13
$encre  = New-Object System.Drawing.SolidBrush $script:Palette.Texte
$g.DrawString('Douze silhouettes, chacune sur clair et sur sombre', $police, $encre,
              $x0, ($y0 + $caseB + 12))
$police.Dispose(); $encre.Dispose()

# --- Controle d'orientation ----------------------------------------------
# Une regle du jeu, pas une preference : a1 est une case SOMBRE et h1 une
# case claire. Une parite inversee est invisible a l'oeil sur un damier, mais
# fausse tout le plateau. On lit donc les pixels reellement peints.
function Test-CouleurCase {
    param([string]$Case, [bool]$SombreAttendu)
    $i = ConvertTo-CaseIndex $Case
    $x = [int]($marge + $script:COL_DE[$i] * $caseA + 3)
    $y = [int]($marge + (7 - $script:RNG_DE[$i]) * $caseA + 3)
    $p = $img.GetPixel($x, $y)
    $ref = $(if ($SombreAttendu) { $script:Palette.CaseSombre } else { $script:Palette.CaseClaire })
    $ok = ($p.R -eq $ref.R -and $p.G -eq $ref.G -and $p.B -eq $ref.B)
    $mot = $(if ($SombreAttendu) { 'sombre' } else { 'claire' })
    Write-Host ("  " + $Case + " attendue " + $mot + " -> " + $(if ($ok) { 'OK' } else { 'FAUX (' + $p.Name + ')' }))
    return $ok
}

Write-Host 'Controle de l orientation du damier :'
$oriOk = (Test-CouleurCase 'a1' $true)
$oriOk = (Test-CouleurCase 'h1' $false) -and $oriOk
$oriOk = (Test-CouleurCase 'a8' $false) -and $oriOk
$oriOk = (Test-CouleurCase 'h8' $true) -and $oriOk
if (-not $oriOk) { Write-Host 'ORIENTATION FAUSSE' -ForegroundColor Red }

$sortie = Join-Path $PSScriptRoot 'apercu-echiquier.png'
$img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $img.Dispose()

Write-Host ("Image ecrite : " + $sortie)
