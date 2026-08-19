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
        M 50 11
        C 60.5 11 69 19.5 69 30
        C 69 35.2 66.6 40 62.7 43.1
        C 70 48.4 74.5 57 74.5 66
        L 65 66
        L 77 87
        L 23 87
        L 35 66
        L 25.5 66
        C 25.5 57 30 48.4 37.3 43.1
        C 33.4 40 31 35.2 31 30
        C 31 19.5 39.5 11 50 11
        Z
'@

    'R' = @'
        M 19 15
        L 32.5 15
        L 32.5 26
        L 43.5 26
        L 43.5 15
        L 56.5 15
        L 56.5 26
        L 67.5 26
        L 67.5 15
        L 81 15
        L 81 40
        L 71.5 48
        L 71.5 64
        L 81 74
        L 81 88
        L 19 88
        L 19 74
        L 28.5 64
        L 28.5 48
        L 19 40
        Z
'@

    'B' = @'
        M 50 9
        C 54.8 9 58.8 13 58.8 17.8
        C 58.8 20.6 57.4 23.1 55.2 24.7
        C 63.6 30.8 73 42.1 73 54.2
        C 73 62.4 66.9 68.8 58.4 70.8
        L 41.6 70.8
        C 33.1 68.8 27 62.4 27 54.2
        C 27 42.1 36.4 30.8 44.8 24.7
        C 42.6 23.1 41.2 20.6 41.2 17.8
        C 41.2 13 45.2 9 50 9
        Z
        M 44 30.5
        L 60.5 47
        L 56 51.5
        L 39.5 35
        Z
        M 22 75
        L 78 75
        L 84 88
        L 16 88
        Z
'@

    # Le cavalier est la seule pièce qu'on reconnaît à sa SILHOUETTE et non à
    # sa géométrie : il lui faut une oreille pointue, un chanfrein creusé, un
    # museau carré et une encolure épaisse. Sans ces quatre traits il devient
    # une tache ronde qui ne dit plus « cheval ».
    'N' = @'
        M 23 88
        L 84 88
        C 84 68 81 51.5 75 40.5
        C 70.5 32 64 25.5 58 21
        L 59.5 12
        L 66 4
        L 51.5 13.5
        C 45 9.5 38 10.5 32 16
        C 25 22 19 31.5 14.8 41.5
        C 12.6 46.5 12.2 51.3 14.8 54.6
        C 17.6 58.2 23.4 58.2 26.4 54.4
        L 30.5 47.5
        L 39.5 51
        C 34.5 60 30.8 70.5 29.3 78.5
        C 28.6 82.5 27.6 86 26 88
        Z
        E 36.5 29.5 3.9 3.9
'@

    'Q' = @'
        E 50 22 8 8
        E 18 29 7.2 7.2
        E 82 29 7.2 7.2
        E 32.5 31 6.8 6.8
        E 67.5 31 6.8 6.8
        M 18 37
        L 28 62
        L 34 40
        L 44.5 66
        L 50 32
        L 55.5 66
        L 66 40
        L 72 62
        L 82 37
        L 76.5 72
        L 23.5 72
        Z
        M 21 76
        L 79 76
        L 85 89
        L 15 89
        Z
'@

    'K' = @'
        M 43.5 3
        L 56.5 3
        L 56.5 14
        L 68 14
        L 68 26.5
        L 56.5 26.5
        L 56.5 38
        L 43.5 38
        L 43.5 26.5
        L 32 26.5
        L 32 14
        L 43.5 14
        Z
        M 50 40
        C 64.5 40 76 49.5 76 60.5
        C 76 67.5 70 72.8 60.5 74.5
        L 39.5 74.5
        C 30 72.8 24 67.5 24 60.5
        C 24 49.5 35.5 40 50 40
        Z
        M 21 78
        L 79 78
        L 85 90
        L 15 90
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

        # Roi en échec : la case est teintée à plat et cernée d'un trait plus
        # soutenu. Un halo dégradé faisait une tache floue peu nette ; ici le
        # rouge reste franc et la pièce dessus reste lisible.
        if ($case -eq $caseEchec) {
            $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120, $script:Palette.Echec))
            $G.FillRectangle($b, $x, $y, $TailleCase, $TailleCase)
            $b.Dispose()
            $ep = [single][math]::Max(2.0, $TailleCase * 0.075)
            $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(225, $script:Palette.Echec)), $ep
            $d = $ep / 2.0
            $G.DrawRectangle($p, ($x + $d), ($y + $d), ($TailleCase - $ep), ($TailleCase - $ep))
            $p.Dispose()
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

        # Opacite volontairement soutenue : a 60/255 sur un petit plateau, les
        # pastilles etaient si pales qu'on croyait certaines absentes.
        if ($Pos.B[$ti] -eq ' ') {
            $r = $TailleCase * 0.175
            $b = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(105, $script:Palette.Possible))
            $G.FillEllipse($b, ($x + $TailleCase / 2 - $r), ($y + $TailleCase / 2 - $r), (2 * $r), (2 * $r))
            $b.Dispose()
        } else {
            $ep = $TailleCase * 0.10
            $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(120, $script:Palette.Possible)), $ep
            $G.DrawEllipse($p, ($x + $ep / 2), ($y + $ep / 2), ($TailleCase - $ep), ($TailleCase - $ep))
            $p.Dispose()
        }
    }

    $police.Dispose()
}
