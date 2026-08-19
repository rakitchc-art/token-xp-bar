# ============================================================================
#  Rendu-Echiquier.ps1 — le dessin, et rien que le dessin.
#
#  Tout est vectoriel : chaque pièce est décrite une seule fois dans un carré
#  de 100 × 100 unités, puis mise à l'échelle de la case au moment du tracé.
#  Conséquence : le plateau reste net à n'importe quelle taille de fenêtre —
#  c'est la contrainte posée par Nisse, qui doit pouvoir agrandir à sa guise.
#  Une image, même en haute définition, aurait fini par baver.
#
#  Ce fichier ne connaît ni les règles ni le réseau : on lui donne une
#  position et il la peint. Il se teste donc en produisant une image, sans
#  ouvrir la moindre fenêtre.
# ============================================================================

Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------------
#  Palette
# ---------------------------------------------------------------------------

function New-Couleur { param([string]$Hex) [System.Drawing.ColorTranslator]::FromHtml($Hex) }

$script:Palette = @{
    CaseClaire   = (New-Couleur '#EDEED3')
    CaseSombre   = (New-Couleur '#739552')
    Fond         = (New-Couleur '#262421')
    Cadre        = (New-Couleur '#1B1A17')
    Texte        = (New-Couleur '#E8E6E1')

    PieceBlanche = (New-Couleur '#FCFCF8')
    TraitBlanche = (New-Couleur '#1F1D1A')
    PieceNoire   = (New-Couleur '#302E2B')
    TraitNoire   = (New-Couleur '#0E0D0B')

    Dernier      = (New-Couleur '#F5F26F')   # surlignage du dernier coup
    Selection    = (New-Couleur '#FFD24A')   # case sélectionnée
    Possible     = (New-Couleur '#1F1D1A')   # pastilles des coups possibles
    Echec        = (New-Couleur '#E24B3A')   # halo rouge sur le roi en échec
}

# ---------------------------------------------------------------------------
#  Silhouettes des pièces
#
#  Mini-langage de tracé, volontairement proche du SVG pour rester lisible :
#     M x y                     aller à
#     L x y                     ligne jusqu'à
#     C x1 y1 x2 y2 x y         courbe de Bézier
#     E cx cy rx ry             ellipse complète (sous-tracé fermé)
#     Z                         fermer le tracé
#
#  Les sous-tracés qui se chevauchent créeraient des trous (mode de
#  remplissage alterné) : les formes sont donc dessinées jointives, jamais
#  superposées — sauf le trait du fou, qui EST un trou volontaire.
# ---------------------------------------------------------------------------

$script:Silhouettes = @{

    'P' = @'
        M 50 13
        C 59.4 13 67 20.6 67 30
        C 67 34.6 65.2 38.7 62.2 41.8
        C 68.5 46.5 72 54 72 62
        L 66 62
        L 74 84
        L 26 84
        L 34 62
        L 28 62
        C 28 54 31.5 46.5 37.8 41.8
        C 34.8 38.7 33 34.6 33 30
        C 33 20.6 40.6 13 50 13
        Z
'@

    'R' = @'
        M 22 17
        L 34 17
        L 34 26
        L 44 26
        L 44 17
        L 56 17
        L 56 26
        L 66 26
        L 66 17
        L 78 17
        L 78 38
        L 70 46
        L 70 66
        L 78 75
        L 78 86
        L 22 86
        L 22 75
        L 30 66
        L 30 46
        L 22 38
        Z
'@

    'B' = @'
        M 50 11
        C 54.4 11 58 14.6 58 19
        C 58 21.6 56.7 23.9 54.8 25.4
        C 62.5 31 71 41.5 71 53
        C 71 61 65.5 67 57.5 69
        L 42.5 69
        C 34.5 67 29 61 29 53
        C 29 41.5 37.5 31 45.2 25.4
        C 43.3 23.9 42 21.6 42 19
        C 42 14.6 45.6 11 50 11
        Z
        M 45 32
        L 60 47
        L 56 51
        L 41 36
        Z
        M 25 73
        L 75 73
        L 80 87
        L 20 87
        Z
'@

    'N' = @'
        M 27 87
        L 81 87
        C 81 70 79 55 74.5 45
        C 70 34.5 62.5 27 56 22
        L 60.5 11
        L 49 17
        C 43 14.5 37 15.5 32 20.5
        C 27 25.5 22.5 32.5 19 40.5
        C 16.5 46.5 16 51.5 18 55
        C 20.2 58.8 25.5 58.5 28.5 55
        L 34.5 47.5
        L 42 51.5
        C 37.5 60 34 70 32.5 78
        C 31.8 82 31 85 30 87
        Z
        E 38 32 3.4 3.4
'@

    'Q' = @'
        E 50 25 7 7
        E 22 30 6.5 6.5
        E 78 30 6.5 6.5
        E 34 33 6 6
        E 66 33 6 6
        M 22 38
        L 30 60
        L 36 39
        L 45 63
        L 50 34
        L 55 63
        L 64 39
        L 70 60
        L 78 38
        L 74 70
        L 26 70
        Z
        M 24 74
        L 76 74
        L 81 87
        L 19 87
        Z
'@

    'K' = @'
        M 44 4
        L 56 4
        L 56 14
        L 67 14
        L 67 26
        L 56 26
        L 56 36
        L 44 36
        L 44 26
        L 33 26
        L 33 14
        L 44 14
        Z
        M 50 37
        C 63 37 73 45.5 73 57
        C 73 64.5 67.5 70 59 71.5
        L 41 71.5
        C 32.5 70 27 64.5 27 57
        C 27 45.5 37 37 50 37
        Z
        M 24 75
        L 76 75
        L 81 88
        L 19 88
        Z
'@
}

function New-CheminDepuisTexte {
    param([string]$Trace)

    $chemin = New-Object System.Drawing.Drawing2D.GraphicsPath
    $chemin.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate

    $mots = @($Trace -split '[\s\r\n]+' | Where-Object { $_ -ne '' })
    $i = 0
    $cx = 0.0; $cy = 0.0     # point courant
    $dx = 0.0; $dy = 0.0     # début du sous-tracé courant

    while ($i -lt $mots.Count) {
        switch ($mots[$i]) {
            'M' {
                $chemin.StartFigure()
                $cx = [single]$mots[$i + 1]; $cy = [single]$mots[$i + 2]
                $dx = $cx; $dy = $cy
                $i += 3
            }
            'L' {
                $nx = [single]$mots[$i + 1]; $ny = [single]$mots[$i + 2]
                $chemin.AddLine($cx, $cy, $nx, $ny)
                $cx = $nx; $cy = $ny
                $i += 3
            }
            'C' {
                $x1 = [single]$mots[$i + 1]; $y1 = [single]$mots[$i + 2]
                $x2 = [single]$mots[$i + 3]; $y2 = [single]$mots[$i + 4]
                $nx = [single]$mots[$i + 5]; $ny = [single]$mots[$i + 6]
                $chemin.AddBezier($cx, $cy, $x1, $y1, $x2, $y2, $nx, $ny)
                $cx = $nx; $cy = $ny
                $i += 7
            }
            'E' {
                $ex = [single]$mots[$i + 1]; $ey = [single]$mots[$i + 2]
                $rx = [single]$mots[$i + 3]; $ry = [single]$mots[$i + 4]
                $chemin.StartFigure()
                $chemin.AddEllipse(($ex - $rx), ($ey - $ry), (2 * $rx), (2 * $ry))
                $chemin.CloseFigure()
                $i += 5
            }
            'Z' {
                $chemin.CloseFigure()
                $cx = $dx; $cy = $dy
                $i += 1
            }
            default { throw ("Commande de trace inconnue : '" + $mots[$i] + "'") }
        }
    }
    return $chemin
}

# Les silhouettes sont converties une seule fois, puis clonées et mises à
# l'échelle à chaque tracé : reconstruire un GraphicsPath par case et par
# rafraîchissement coûterait cher au redimensionnement.
$script:CheminsPiece = @{}
foreach ($cle in $script:Silhouettes.Keys) {
    $script:CheminsPiece[$cle] = New-CheminDepuisTexte $script:Silhouettes[$cle]
}

function Draw-Piece {
    param($G, [char]$Piece, [single]$X, [single]$Y, [single]$Taille)

    $lettre = [string][char]::ToUpper($Piece)
    if (-not $script:CheminsPiece.ContainsKey($lettre)) { return }
    $blanche = [char]::IsUpper($Piece)

    # La pièce n'occupe pas toute la case : une marge laisse respirer le damier.
    $marge  = $Taille * 0.06
    $utile  = $Taille - 2 * $marge
    $facteur = $utile / 100.0

    $chemin = $script:CheminsPiece[$lettre].Clone()
    $m = New-Object System.Drawing.Drawing2D.Matrix
    $m.Translate(($X + $marge), ($Y + $marge))
    $m.Scale($facteur, $facteur)
    $chemin.Transform($m)

    $remplissage = $(if ($blanche) { $script:Palette.PieceBlanche } else { $script:Palette.PieceNoire })
    $trait       = $(if ($blanche) { $script:Palette.TraitBlanche } else { $script:Palette.TraitNoire })

    $brosse = New-Object System.Drawing.SolidBrush $remplissage
    # Épaisseur proportionnelle : un contour fixe deviendrait un fil invisible
    # en grand, et un trait épais qui mange la pièce en petit.
    $stylo  = New-Object System.Drawing.Pen $trait, ($Taille * 0.035)
    $stylo.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $G.FillPath($brosse, $chemin)
    $G.DrawPath($stylo, $chemin)

    $stylo.Dispose(); $brosse.Dispose(); $m.Dispose(); $chemin.Dispose()
}

# ---------------------------------------------------------------------------
#  Plateau
# ---------------------------------------------------------------------------

function Draw-Echiquier {
    param(
        $G,
        [single]$OX, [single]$OY, [single]$TailleCase,
        $Pos,
        $Options = @{}
    )

    $retourne  = [bool]$Options.Retourne          # vue côté noirs
    $selection = $(if ($null -ne $Options.Selection) { [int]$Options.Selection } else { -1 })
    $possibles = @($Options.CoupsPossibles)       # cases d'arrivée à pointer
    $depart    = $(if ($null -ne $Options.DernierDepart) { [int]$Options.DernierDepart } else { -1 })
    $arrivee   = $(if ($null -ne $Options.DernierArrivee) { [int]$Options.DernierArrivee } else { -1 })
    $caseEchec = $(if ($null -ne $Options.CaseEchec) { [int]$Options.CaseEchec } else { -1 })
    $coords    = ($Options.Coordonnees -ne $false)

    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $police = New-Object System.Drawing.Font 'Segoe UI', ($TailleCase * 0.17), ([System.Drawing.FontStyle]::Bold)

    for ($case = 0; $case -lt 64; $case++) {
        $col = $script:COL_DE[$case]
        $rng = $script:RNG_DE[$case]

        # Position à l'écran. Vue blancs : la rangée 8 est en haut.
        $cx = $(if ($retourne) { 7 - $col } else { $col })
        $cy = $(if ($retourne) { $rng } else { 7 - $rng })
        $x = $OX + $cx * $TailleCase
        $y = $OY + $cy * $TailleCase

        $claire = ((($col + $rng) % 2) -eq 1)
        $fond = $(if ($claire) { $script:Palette.CaseClaire } else { $script:Palette.CaseSombre })
        $brosse = New-Object System.Drawing.SolidBrush $fond
        $G.FillRectangle($brosse, $x, $y, $TailleCase, $TailleCase)
        $brosse.Dispose()

        # Dernier coup joué : les deux cases teintées, pour retrouver d'un
        # coup d'œil ce que l'adversaire vient de faire après plusieurs heures.
        if ($case -eq $depart -or $case -eq $arrivee) {
            $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, $script:Palette.Dernier))
            $G.FillRectangle($b, $x, $y, $TailleCase, $TailleCase)
            $b.Dispose()
        }

        if ($case -eq $selection) {
            $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(150, $script:Palette.Selection))
            $G.FillRectangle($b, $x, $y, $TailleCase, $TailleCase)
            $b.Dispose()
        }

        # Roi en échec : halo rouge dégradé, visible sans lire les pièces.
        if ($case -eq $caseEchec) {
            $chemin = New-Object System.Drawing.Drawing2D.GraphicsPath
            $chemin.AddEllipse($x, $y, $TailleCase, $TailleCase)
            $degrade = New-Object System.Drawing.Drawing2D.PathGradientBrush $chemin
            $degrade.CenterColor = [System.Drawing.Color]::FromArgb(215, $script:Palette.Echec)
            $degrade.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $script:Palette.Echec))
            $G.FillRectangle($degrade, $x, $y, $TailleCase, $TailleCase)
            $degrade.Dispose(); $chemin.Dispose()
        }

        # Coordonnées dans le coin, comme sur un vrai échiquier : lettre en
        # bas, chiffre à gauche, dans la couleur opposée à la case.
        if ($coords) {
            $encre = $(if ($claire) { $script:Palette.CaseSombre } else { $script:Palette.CaseClaire })
            $b = New-Object System.Drawing.SolidBrush $encre
            if ($cx -eq 0) {
                $chiffre = [string]($rng + 1)
                $G.DrawString($chiffre, $police, $b, ($x + $TailleCase * 0.04), ($y + $TailleCase * 0.03))
            }
            if ($cy -eq 7) {
                $lettre = [string][char]([int][char]'a' + $col)
                # MeasureString rend une hauteur qui inclut l'interligne de la
                # police : la soustraire telle quelle collerait la lettre au
                # bord. On remonte de la marge d'interligne.
                $t = $G.MeasureString($lettre, $police)
                $G.DrawString($lettre, $police, $b,
                    ($x + $TailleCase - $t.Width - $TailleCase * 0.02),
                    ($y + $TailleCase - $t.Height * 0.88 - $TailleCase * 0.03))
            }
            $b.Dispose()
        }

        $piece = $Pos.B[$case]
        if ($piece -ne ' ') { Draw-Piece $G $piece $x $y $TailleCase }
    }

    # Pastilles des coups possibles, tracées après les pièces pour rester
    # lisibles : un disque sur case vide, un anneau autour d'une prise.
    foreach ($t in $possibles) {
        if ($null -eq $t) { continue }
        $ti = [int]$t
        $col = $script:COL_DE[$ti]; $rng = $script:RNG_DE[$ti]
        $cx = $(if ($retourne) { 7 - $col } else { $col })
        $cy = $(if ($retourne) { $rng } else { 7 - $rng })
        $x = $OX + $cx * $TailleCase
        $y = $OY + $cy * $TailleCase

        if ($Pos.B[$ti] -eq ' ') {
            $r = $TailleCase * 0.16
            $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60, $script:Palette.Possible))
            $G.FillEllipse($b, ($x + $TailleCase / 2 - $r), ($y + $TailleCase / 2 - $r), (2 * $r), (2 * $r))
            $b.Dispose()
        } else {
            $ep = $TailleCase * 0.09
            $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, $script:Palette.Possible)), $ep
            $G.DrawEllipse($p, ($x + $ep / 2), ($y + $ep / 2), ($TailleCase - $ep), ($TailleCase - $ep))
            $p.Dispose()
        }
    }

    $police.Dispose()
}
