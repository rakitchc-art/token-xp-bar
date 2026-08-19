# ============================================================================
#  Plateau-Barre.ps1 — le plateau qui se déplie SOUS la barre.
#
#  Il n'y a plus de fenêtre séparée : le jeu vit dans la fenêtre de TokenBar,
#  qui s'agrandit vers le bas quand on clique sur la flèche et retrouve sa
#  taille quand on reclique. Rien n'apparaît dans la barre des tâches, rien
#  ne vole le premier plan, et il n'y a aucun temps d'ouverture.
#
#  Le plateau est volontairement NU : aucun texte, aucun bouton. Ce qu'il
#  faudrait des boutons pour faire (nouvelle partie, retourner, abandonner,
#  réglages) se trouve dans le menu du clic droit, qui n'occupe aucune place.
#
#  Le coin bas-droit se tire à la souris pour agrandir ; la taille choisie est
#  retenue d'une ouverture à l'autre.
#
#  Ces fonctions sont appelées par les gestionnaires de TokenBar.ps1, qui ne
#  sont PAS des fermetures : $script: y fonctionne normalement.
# ============================================================================

# ---------------------------------------------------------------------------
#  Géométrie
# ---------------------------------------------------------------------------

$script:PLATEAU_MIN    = 160     # côté minimal du damier, en pixels
$script:PLATEAU_MAX    = 1200
$script:PLATEAU_DEFAUT = 232     # « un carré un peu plus large que la barre »
$script:POIGNEE        = 13      # côté de la zone de redimensionnement

$script:echecsOuvert    = $false
$script:echecsTaille    = $script:PLATEAU_DEFAUT
$script:flecheEtat      = 'normal'    # normal | survol | enfonce
$script:plateauSelection = -1
$script:plateauCibles   = @()
$script:plateauPromo    = $null
$script:plateauRetourne = $false
$script:redimEnCours    = $false
$script:redimDepart     = $null

function Get-GeometrieEchecs {
    # Tout ce dont le dessin ET les clics ont besoin, calculé au même endroit :
    # c'est ce qui garantit que la zone cliquable colle exactement à ce qui est
    # peint. Toutes les coordonnées sont celles de la FENÊTRE.
    param([int]$LargeurBarre, [int]$HauteurBarre)

    $g = @{ Ouvert = $script:echecsOuvert }

    if ($script:echecsOuvert) {
        # Le damier doit tomber sur des cases entières : sinon ses lignes n'ont
        # pas toutes la même épaisseur, ce qui saute aux yeux.
        $case = [int][math]::Max(20, [math]::Floor($script:echecsTaille / 8))
        $cote = $case * 8
        $lFen = [int][math]::Max($LargeurBarre, $cote)
    } else {
        $case = 0; $cote = 0; $lFen = $LargeurBarre
    }

    # La barre reste collée au bord DROIT de la fenêtre : quand le plateau
    # s'ouvre et que la fenêtre s'élargit, c'est le bord gauche qui avance et
    # la barre ne bouge pas d'un pixel à l'écran.
    $ox = $lFen - $LargeurBarre

    $lf = 22; $hf = 15
    $g.OX     = $ox
    $g.Fleche = New-Object System.Drawing.Rectangle `
        ($ox + [int]($LargeurBarre - 44 + (42 - $lf) / 2)), ($HauteurBarre + 2), $lf, $hf
    $g.HauteurFerme   = $g.Fleche.Bottom + 2
    $g.LargeurFenetre = $lFen

    if (-not $script:echecsOuvert) {
        $g.HauteurFenetre = $g.HauteurFerme
        return $g
    }

    # Aucun cadre : la fenêtre fait exactement la taille du damier. On ne voit
    # que le plateau. L'état de la partie est porté par un liseré peint SUR le
    # bord du damier, pas par une bande autour.
    $g.Case           = $case
    $g.Cote           = $cote
    $g.HauteurFenetre = $g.HauteurFerme + $cote
    $g.PlateauX       = $lFen - $cote
    $g.PlateauY       = $g.HauteurFerme
    $g.Cadre = New-Object System.Drawing.Rectangle $g.PlateauX, $g.PlateauY, $cote, $cote
    # Poignée dans le coin bas-GAUCHE du damier : le plateau ne peut grandir
    # que vers la gauche et vers le bas, puisque la barre est ancrée au bord
    # droit de l'écran.
    $g.Poignee = New-Object System.Drawing.Rectangle `
        $g.Cadre.X, ($g.Cadre.Bottom - $script:POIGNEE), $script:POIGNEE, $script:POIGNEE
    return $g
}

# ---------------------------------------------------------------------------
#  Dessin
# ---------------------------------------------------------------------------

function Draw-FlecheEchecs {
    # Un chevron, pas un pictogramme en pixels : vers le bas quand le plateau
    # est replié, vers le haut quand il est ouvert.
    param($G, $Rect, [bool]$Ouvert, [string]$Etat, [bool]$Pastille, [bool]$Souci = $false)

    $ancien = $G.SmoothingMode
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $fond = switch ($Etat) {
        'survol'  { [System.Drawing.Color]::FromArgb(255, 68, 68, 76) }
        'enfonce' { [System.Drawing.Color]::FromArgb(255, 26, 26, 30) }
        default   { [System.Drawing.Color]::FromArgb(255, 47, 47, 53) }
    }
    $bord = switch ($Etat) {
        'survol'  { [System.Drawing.Color]::FromArgb(255, 120, 120, 132) }
        default   { [System.Drawing.Color]::FromArgb(255, 86, 86, 96) }
    }

    $chemin = New-RoundedPath ([single]$Rect.X) ([single]$Rect.Y) `
                              ([single]$Rect.Width) ([single]$Rect.Height) 3.5
    $b = New-Object System.Drawing.SolidBrush $fond
    $G.FillPath($b, $chemin); $b.Dispose()
    $p = New-Object System.Drawing.Pen $bord, 1.0
    $G.DrawPath($p, $chemin); $p.Dispose()
    $chemin.Dispose()

    # Le chevron. Enfoncé, il descend d'un pixel : c'est ce petit décalage qui
    # donne la sensation d'un vrai bouton.
    $dy = $(if ($Etat -eq 'enfonce') { 1 } else { 0 })
    $cx = $Rect.X + $Rect.Width / 2.0
    $cy = $Rect.Y + $Rect.Height / 2.0 + $dy
    $lg = $Rect.Width * 0.26
    $ht = $Rect.Height * 0.17

    # Chevron eteint quand le serveur ne repond pas : le probleme se signale
    # ainsi, sans une seule boite de dialogue.
    $encre = $(if ($Souci) { [System.Drawing.Color]::FromArgb(255, 122, 122, 130) }
               else        { [System.Drawing.Color]::FromArgb(255, 232, 232, 238) })
    $stylo = New-Object System.Drawing.Pen $encre, 1.8
    $stylo.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $stylo.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $stylo.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    if ($Ouvert) {
        $G.DrawLines($stylo, @(
            (New-Object System.Drawing.PointF (($cx - $lg), ($cy + $ht))),
            (New-Object System.Drawing.PointF ($cx,         ($cy - $ht))),
            (New-Object System.Drawing.PointF (($cx + $lg), ($cy + $ht)))))
    } else {
        $G.DrawLines($stylo, @(
            (New-Object System.Drawing.PointF (($cx - $lg), ($cy - $ht))),
            (New-Object System.Drawing.PointF ($cx,         ($cy + $ht))),
            (New-Object System.Drawing.PointF (($cx + $lg), ($cy - $ht)))))
    }
    $stylo.Dispose()

    if ($Pastille) {
        # « C'est à toi. » Cerclée de sombre pour rester lisible quelle que
        # soit la couleur du bouton dessous.
        $d = 7.0
        $x = $Rect.Right - $d + 1.5
        $y = $Rect.Y - 1.5
        $n = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 20, 22))
        $r = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 240, 55, 60))
        $G.FillEllipse($n, ($x - 1), ($y - 1), ($d + 2), ($d + 2))
        $G.FillEllipse($r, $x, $y, $d, $d)
        $n.Dispose(); $r.Dispose()
    }

    $G.SmoothingMode = $ancien
}

function Get-CouleurCadre {
    # Le plateau ne porte aucun texte : c'est la couleur du cadre qui dit où en
    # est la partie. Le code, du plus calme au plus fort :
    #
    #   gris sombre  : rien à signaler, c'est à l'adversaire
    #   ambre        : c'est à toi de jouer
    #   orange       : échec
    #   vert         : tu as gagné
    #   rouge        : tu as perdu
    #   bleu-gris    : partie nulle
    #
    # Les états de fin de partie ont EN PLUS un liseré clair à l'intérieur :
    # une information portée par la seule couleur serait invisible pour qui
    # distingue mal le rouge du vert.
    param($Partie)

    # Rien a signaler = AUCUN liseré : on ne voit que le plateau.
    $neutre = @{ Cadre = $null; Lisere = $null }
    if (-not $Partie) { return $neutre }

    if (Test-PartieTerminee $Partie) {
        $mien = $(if ($Partie.MaCouleur -eq 'w') { '1-0' } else { '0-1' })
        if ($Partie.Resultat -eq '1/2-1/2') {
            return @{ Cadre  = [System.Drawing.Color]::FromArgb(255, 84, 108, 132)
                      Lisere = [System.Drawing.Color]::FromArgb(255, 168, 194, 216) }
        }
        if ($Partie.Resultat -eq $mien) {
            return @{ Cadre  = [System.Drawing.Color]::FromArgb(255, 62, 142, 72)
                      Lisere = [System.Drawing.Color]::FromArgb(255, 154, 224, 160) }
        }
        return @{ Cadre  = [System.Drawing.Color]::FromArgb(255, 172, 52, 44)
                  Lisere = [System.Drawing.Color]::FromArgb(255, 240, 158, 150) }
    }

    if ($Partie.Etat -eq 'echec') {
        return @{ Cadre = [System.Drawing.Color]::FromArgb(255, 214, 128, 42); Lisere = $null }
    }
    if (Test-MonTour $Partie) {
        return @{ Cadre = [System.Drawing.Color]::FromArgb(255, 226, 190, 74); Lisere = $null }
    }
    return $neutre
}

function Draw-PlateauBarre {
    param($G, $Geo, $Partie)

    if (-not $Geo.Ouvert -or -not $Partie) { return }

    Draw-Echiquier $G $Geo.PlateauX $Geo.PlateauY $Geo.Case $Partie.Pos @{
        Retourne       = $script:plateauRetourne
        Selection      = $script:plateauSelection
        CoupsPossibles = $script:plateauCibles
        DernierDepart  = $Partie.DernierDepart
        DernierArrivee = $Partie.DernierArrivee
        CaseEchec      = (Get-CaseRoiEnEchec $Partie)
        Coordonnees    = ($Geo.Case -ge 28)   # illisibles en dessous
    }

    if ($script:plateauPromo) { Draw-PromoBarre $G $Geo $Partie }

    $ancien = $G.SmoothingMode
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # L'état de la partie, peint EN LISERÉ sur le bord du damier. Rien autour :
    # on ne voit que le plateau tant qu'il n'y a rien à signaler.
    $etat = Get-CouleurCadre $Partie
    if ($etat.Cadre) {
        $ep = [single][math]::Max(2.0, $Geo.Case * 0.10)
        $p = New-Object System.Drawing.Pen $etat.Cadre, $ep
        $d = [int]($ep / 2)
        $G.DrawRectangle($p, ($Geo.Cadre.X + $d), ($Geo.Cadre.Y + $d),
                             ($Geo.Cadre.Width - 2 * $d - 1), ($Geo.Cadre.Height - 2 * $d - 1))
        $p.Dispose()
        if ($etat.Lisere) {
            $p2 = New-Object System.Drawing.Pen $etat.Lisere, 1.6
            $e2 = [int]($ep + 1)
            $G.DrawRectangle($p2, ($Geo.Cadre.X + $e2), ($Geo.Cadre.Y + $e2),
                                  ($Geo.Cadre.Width - 2 * $e2 - 1), ($Geo.Cadre.Height - 2 * $e2 - 1))
            $p2.Dispose()
        }
    }

    # Poignée : trois traits en biais, le langage universel du coin qu'on tire.
    # Orientés vers le bas-gauche, dans le sens où le plateau peut grandir.
    $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(130, 40, 40, 44)), 1.6
    for ($i = 0; $i -lt 3; $i++) {
        $d = 3 + $i * 4
        $G.DrawLine($p, ($Geo.Poignee.X + $d), ($Geo.Poignee.Bottom - 2),
                        ($Geo.Poignee.X + 1), ($Geo.Poignee.Bottom - 1 - $d))
    }
    $p.Dispose()
    $G.SmoothingMode = $ancien
}

function Draw-PromoBarre {
    param($G, $Geo, $Partie)

    $blanc = ($Partie.Pos.Trait -eq 'w')
    $c = $Geo.Case
    $pt = Get-PointCaseBarre $Geo $script:plateauPromo.Arrivee
    $versLeBas = ($pt.Y + 4 * $c) -le ($Geo.PlateauY + $Geo.Cote)

    $ordre = @('q', 'r', 'b', 'n')
    $script:plateauPromo.Cases = @()

    for ($i = 0; $i -lt 4; $i++) {
        $y = $(if ($versLeBas) { $pt.Y + $i * $c } else { $pt.Y - $i * $c })
        $rect = New-Object System.Drawing.Rectangle $pt.X, $y, $c, $c

        $f = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(252, 250, 250, 246))
        $G.FillRectangle($f, $rect); $f.Dispose()
        $s = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 27, 26, 23)),
                                           ([single][math]::Max(1, $c * 0.04))
        $G.DrawRectangle($s, $rect); $s.Dispose()

        $lettre = $(if ($blanc) { [char]$ordre[$i].ToUpper() } else { [char]$ordre[$i] })
        Draw-Piece $G $lettre $rect.X $rect.Y $c

        $coup = -1
        foreach ($cand in $script:plateauPromo.Candidats) {
            if ($script:PROMO_LETTRE[(($cand -shr 12) -band 7)] -eq $ordre[$i]) { $coup = $cand; break }
        }
        if ($coup -ge 0) { $script:plateauPromo.Cases += @{ Rect = $rect; Coup = $coup } }
    }
}

# ---------------------------------------------------------------------------
#  Repérage
# ---------------------------------------------------------------------------

function Get-CaseDepuisPointBarre {
    param($Geo, [int]$PX, [int]$PY)
    if (-not $Geo.Ouvert) { return -1 }
    $cx = [math]::Floor(($PX - $Geo.PlateauX) / $Geo.Case)
    $cy = [math]::Floor(($PY - $Geo.PlateauY) / $Geo.Case)
    if ($cx -lt 0 -or $cx -gt 7 -or $cy -lt 0 -or $cy -gt 7) { return -1 }
    # Exactement l'inverse de la projection de Draw-Echiquier.
    if ($script:plateauRetourne) { $col = 7 - $cx; $rng = $cy } else { $col = $cx; $rng = 7 - $cy }
    return [int]($rng * 8 + $col)
}

function Get-PointCaseBarre {
    param($Geo, [int]$Case)
    $col = $script:COL_DE[$Case]; $rng = $script:RNG_DE[$Case]
    $cx = $(if ($script:plateauRetourne) { 7 - $col } else { $col })
    $cy = $(if ($script:plateauRetourne) { $rng } else { 7 - $rng })
    return New-Object System.Drawing.Point `
        ($Geo.PlateauX + $cx * $Geo.Case), ($Geo.PlateauY + $cy * $Geo.Case)
}
