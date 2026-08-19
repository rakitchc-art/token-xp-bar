# Apercu-Palettes.ps1 -- la meme position dans quatre habillages, pour choisir.
#
# Sortie : scripts\apercu-palettes.png

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')

# Position de milieu de partie : des pieces des deux couleurs sur les deux
# teintes de cases, c'est ce qui juge vraiment un habillage.
$fen = 'r2q1rk1/pp2bppp/2n1bn2/3pp3/3PP3/2N1BN2/PP2BPPP/R2Q1RK1 w - - 0 10'
$pos = New-Position $fen

$habillages = @(
    @{ Nom = 'Vert (chess.com)'; Claire = '#EDEED3'; Sombre = '#739552'
       Note = 'la reference, celle que tout le monde reconnait' },
    @{ Nom = 'Bleu ardoise';     Claire = '#DEE3E6'; Sombre = '#8CA2AD'
       Note = 'plus doux, moins fatigant sur de longues sessions' },
    @{ Nom = 'Bois classique';   Claire = '#F0D9B5'; Sombre = '#B58863'
       Note = 'le damier en bois des clubs' },
    @{ Nom = 'Fort contraste';   Claire = '#FFFFFF'; Sombre = '#6C7A89'
       Note = 'le plus lisible : cases tres separees, pieces franches' }
)

$marge   = 26
$caseA   = 52.0
$plateau = 8 * $caseA
$titreH  = 46
$largeur = [int](4 * $plateau + 5 * $marge)
$hauteur = [int]($marge + $titreH + $plateau + $marge)

$img = New-Object System.Drawing.Bitmap $largeur, $hauteur
$g   = [System.Drawing.Graphics]::FromImage($img)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.Clear($script:Palette.Fond)

$policeTitre = New-Object System.Drawing.Font 'Segoe UI', 12, ([System.Drawing.FontStyle]::Bold)
$policeNote  = New-Object System.Drawing.Font 'Segoe UI', 9
$encre       = New-Object System.Drawing.SolidBrush $script:Palette.Texte
$encreNote   = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, $script:Palette.Texte))

$claireOrigine = $script:Palette.CaseClaire
$sombreOrigine = $script:Palette.CaseSombre

for ($i = 0; $i -lt $habillages.Count; $i++) {
    $h = $habillages[$i]
    $x = $marge + $i * ($plateau + $marge)

    $g.DrawString(([string]($i + 1) + '.  ' + $h.Nom), $policeTitre, $encre, $x, $marge)
    $g.DrawString($h.Note, $policeNote, $encreNote, $x, ($marge + 21))

    $script:Palette.CaseClaire = New-Couleur $h.Claire
    $script:Palette.CaseSombre = New-Couleur $h.Sombre
    Draw-Echiquier $g $x ($marge + $titreH) $caseA $pos
}

$script:Palette.CaseClaire = $claireOrigine
$script:Palette.CaseSombre = $sombreOrigine

$policeTitre.Dispose(); $policeNote.Dispose(); $encre.Dispose(); $encreNote.Dispose()

$sortie = Join-Path $PSScriptRoot 'apercu-palettes.png'
$img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $img.Dispose()
Write-Host ("Image ecrite : " + $sortie)
