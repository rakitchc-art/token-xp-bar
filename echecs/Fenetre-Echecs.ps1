# ============================================================================
#  Fenetre-Echecs.ps1 — la fenêtre de jeu.
#
#  Tout est peint à la main sur un seul panneau : plateau, liste des coups,
#  boutons. Raison : la fenêtre doit pouvoir être agrandie librement (Nisse
#  voit mal), et des contrôles WinForms classiques auraient gardé leur taille
#  de police pendant que le plateau grandit. Ici chaque dimension est
#  recalculée depuis la taille de la fenêtre, donc tout grandit ensemble.
#
#  Tout est accessible à la souris : sélectionner, jouer, promouvoir,
#  retourner le plateau. Aucun raccourci clavier obligatoire.
#
#  PIÈGE ÉVITÉ ICI, à ne pas réintroduire : les gestionnaires d'événement
#  PowerShell sont créés avec .GetNewClosure(), qui les rattache à un module
#  neuf. Dans une telle fermeture, $script:MaVariable vaut $null — silence
#  total à l'écriture, exception au premier usage. Toute la logique vit donc
#  dans de vraies fonctions (qui, elles, gardent leur portée), et les
#  gestionnaires ne font que les appeler. Bénéfice : la fenêtre entière se
#  dessine hors écran, donc se teste sans être ouverte.
#
#  Dépend de Moteur-Echecs.ps1, Rendu-Echiquier.ps1 et Partie-Echecs.ps1.
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------------
#  État de vue
# ---------------------------------------------------------------------------

function New-VueEchecs {
    param($Partie, [string]$Journal = '')
    return @{
        Partie    = $Partie
        Retourne  = ($Partie.MaCouleur -eq 'b')   # on se voit toujours en bas
        Selection = -1
        Cibles    = @()
        Promo     = $null        # @{ Depart; Arrivee; Candidats; Cases }
        Boutons   = @()
        Polices   = @{}
        Journal   = $Journal
        Erreur    = ''
        Marge = 0; BarreH = 0; PanneauX = 0; PanneauL = 0
        PlateauX = 0; PlateauY = 0; Case = 0; Plateau = 0
    }
}

function Update-DispositionEchecs {
    param($Vue, [int]$Largeur, [int]$Hauteur)
    if ($Largeur -le 0 -or $Hauteur -le 0) { return }

    $Vue.Marge    = [int][math]::Max(12, $Largeur * 0.014)
    $Vue.BarreH   = [int][math]::Max(46, $Hauteur * 0.085)
    $panneauVoulu = [int][math]::Max(210, $Largeur * 0.27)

    $largeurDispo = $Largeur - $panneauVoulu - 3 * $Vue.Marge
    $hauteurDispo = $Hauteur - $Vue.BarreH - 2 * $Vue.Marge

    # Côté multiple de 8 : sinon les cases tombent sur des demi-pixels et le
    # damier prend des lignes de largeur inégale, très visible en grand.
    $cote = [int][math]::Min($largeurDispo, $hauteurDispo)
    $Vue.Case    = [int][math]::Max(24, [math]::Floor($cote / 8))
    $Vue.Plateau = $Vue.Case * 8

    $Vue.PlateauX = $Vue.Marge
    $Vue.PlateauY = $Vue.BarreH + [int](($Hauteur - $Vue.BarreH - $Vue.Plateau) / 2)
    $Vue.PanneauX = $Vue.PlateauX + $Vue.Plateau + $Vue.Marge
    $Vue.PanneauL = $Largeur - $Vue.PanneauX - $Vue.Marge

    foreach ($p in $Vue.Polices.Values) { $p.Dispose() }
    $base = [math]::Max(9.0, $Vue.Case * 0.20)
    $Vue.Polices = @{
        Titre  = (New-Object System.Drawing.Font 'Segoe UI', ($base * 1.25), ([System.Drawing.FontStyle]::Bold))
        Normal = (New-Object System.Drawing.Font 'Segoe UI', $base)
        Gras   = (New-Object System.Drawing.Font 'Segoe UI', $base, ([System.Drawing.FontStyle]::Bold))
        Petit  = (New-Object System.Drawing.Font 'Segoe UI', ($base * 0.85))
        Score  = (New-Object System.Drawing.Font 'Segoe UI', ($base * 1.5), ([System.Drawing.FontStyle]::Bold))
    }
}

# ---------------------------------------------------------------------------
#  Dessin
# ---------------------------------------------------------------------------

function Draw-FenetreEchecs {
    param($G, $Vue)

    $partie = $Vue.Partie
    $G.Clear($script:Palette.Fond)
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $encre = New-Object System.Drawing.SolidBrush $script:Palette.Texte
    $pale  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, $script:Palette.Texte))

    # --- bandeau : l'adversaire, et de quelle couleur on joue --------------
    $G.DrawString($partie.NomAdversaire, $Vue.Polices.Titre, $encre,
                  [single]$Vue.Marge, [single]($Vue.Marge * 0.6))
    $couleurTexte = $(if ($partie.MaCouleur -eq 'w') { 'tu joues les blancs' } else { 'tu joues les noirs' })
    $G.DrawString($couleurTexte, $Vue.Polices.Petit, $pale,
                  [single]$Vue.Marge, [single]($Vue.Marge * 0.6 + $Vue.Polices.Titre.Height))

    # --- plateau ----------------------------------------------------------
    Draw-Echiquier $G $Vue.PlateauX $Vue.PlateauY $Vue.Case $partie.Pos @{
        Retourne       = $Vue.Retourne
        Selection      = $Vue.Selection
        CoupsPossibles = $Vue.Cibles
        DernierDepart  = $partie.DernierDepart
        DernierArrivee = $partie.DernierArrivee
        CaseEchec      = (Get-CaseRoiEnEchec $partie)
    }

    # --- panneau latéral ---------------------------------------------------
    $px = $Vue.PanneauX
    $pl = $Vue.PanneauL
    $py = $Vue.PlateauY

    $fond = New-Object System.Drawing.SolidBrush $script:Palette.Cadre
    $G.FillRectangle($fond, $px, $py, $pl, $Vue.Plateau)
    $fond.Dispose()

    $pad = [int]($Vue.Case * 0.22)
    $y   = $py + $pad

    # Ligne d'état : la seule chose qu'on lit vraiment en revenant après
    # plusieurs heures. Elle change de couleur selon qu'on doit agir ou non.
    $etat = Get-TexteEtat $partie
    $couleurEtat = $script:Palette.Texte
    if (Test-PartieTerminee $partie) { $couleurEtat = $script:Palette.Echec }
    elseif (Test-MonTour $partie)    { $couleurEtat = $script:Palette.Selection }

    $bEtat = New-Object System.Drawing.SolidBrush $couleurEtat
    $hEtat = [single]($Vue.Polices.Gras.Height * 2.4)
    $rectEtat = New-Object System.Drawing.RectangleF(
        [single]($px + $pad), [single]$y, [single]($pl - 2 * $pad), $hEtat)
    $G.DrawString($etat, $Vue.Polices.Gras, $bEtat, $rectEtat)
    $bEtat.Dispose()
    $y += [int]$hEtat + $pad

    # --- score cumulé ------------------------------------------------------
    $G.DrawString('Score', $Vue.Polices.Petit, $pale, [single]($px + $pad), [single]$y)
    $y += [int]$Vue.Polices.Petit.Height
    $score = ('{0} — {1}' -f (Format-Point $partie.MesPoints), (Format-Point $partie.SesPoints))
    $G.DrawString($score, $Vue.Polices.Score, $encre, [single]($px + $pad), [single]$y)
    $y += [int]$Vue.Polices.Score.Height + $pad

    # --- liste des coups ---------------------------------------------------
    $ligneH   = [int]($Vue.Polices.Normal.Height * 1.15)
    $hautListe = $y
    $bh       = [int]($Vue.Case * 0.62)
    $basListe = $py + $Vue.Plateau - $pad - $bh - $pad
    $visibles = [math]::Max(1, [math]::Floor(($basListe - $hautListe) / $ligneH))

    $paires   = [int][math]::Ceiling($partie.San.Count / 2.0)
    $premiere = [int][math]::Max(0, $paires - $visibles)

    $colNum = $px + $pad
    $colB   = $px + $pad + [int]($pl * 0.20)
    $colN   = $px + $pad + [int]($pl * 0.55)

    for ($i = $premiere; $i -lt $paires; $i++) {
        $ly = $hautListe + ($i - $premiere) * $ligneH
        $G.DrawString(([string]($i + 1) + '.'), $Vue.Polices.Petit, $pale, [single]$colNum, [single]$ly)
        if ((2 * $i) -lt $partie.San.Count) {
            $G.DrawString($partie.San[2 * $i], $Vue.Polices.Normal, $encre, [single]$colB, [single]$ly)
        }
        if ((2 * $i + 1) -lt $partie.San.Count) {
            $G.DrawString($partie.San[2 * $i + 1], $Vue.Polices.Normal, $encre, [single]$colN, [single]$ly)
        }
    }

    # --- boutons -----------------------------------------------------------
    $Vue.Boutons = @()
    $libelles = @('Retourner le plateau', 'Nouvelle partie')
    $bw = [int](($pl - 3 * $pad) / 2)
    $by = $py + $Vue.Plateau - $pad - $bh
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'

    for ($i = 0; $i -lt $libelles.Count; $i++) {
        $bx = $px + $pad + $i * ($bw + $pad)
        $rect = New-Object System.Drawing.Rectangle $bx, $by, $bw, $bh
        $Vue.Boutons += @{ Nom = $libelles[$i]; Rect = $rect }

        $chemin = New-RectangleArrondi $rect ([int]([math]::Max(3, $bh * 0.26)))
        $bf = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(32, 255, 255, 255))
        $G.FillPath($bf, $chemin)
        $bf.Dispose(); $chemin.Dispose()

        $rectF = New-Object System.Drawing.RectangleF(
            [single]$rect.X, [single]$rect.Y, [single]$rect.Width, [single]$rect.Height)
        $G.DrawString($libelles[$i], $Vue.Polices.Petit, $encre, $rectF, $sf)
    }
    $sf.Dispose()

    # --- choix de promotion, par-dessus tout -------------------------------
    if ($Vue.Promo) { Draw-ChoixPromotion $G $Vue }

    $encre.Dispose(); $pale.Dispose()
}

function Draw-ErreurFenetre {
    # Une exception pendant le dessin ne doit ni ouvrir une boîte système ni
    # disparaître en silence : elle s'écrit à l'écran ET dans le journal.
    param($G, $Vue, $Erreur)

    $Vue.Erreur = $Erreur.Exception.Message
    if ($Vue.Journal) {
        $texte = ('--- ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ---`r`n" +
                  $Erreur.Exception.ToString() + "`r`n" + $Erreur.ScriptStackTrace + "`r`n")
        try { [System.IO.File]::AppendAllText($Vue.Journal, $texte) } catch { }
    }
    try {
        $G.Clear([System.Drawing.Color]::FromArgb(60, 20, 20))
        $police = New-Object System.Drawing.Font 'Segoe UI', 11
        $encre  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $G.DrawString(("Erreur d'affichage :`r`n" + $Vue.Erreur + "`r`n`r`nDétail : " + $Vue.Journal),
                      $police, $encre, 14.0, 14.0)
        $police.Dispose(); $encre.Dispose()
    } catch { }
}

# ---------------------------------------------------------------------------
#  Interaction
# ---------------------------------------------------------------------------

function Invoke-ClicEchecs {
    # Traite un clic. Renvoie $true si l'affichage doit être redessiné.
    param($Vue, [int]$PX, [int]$PY, [scriptblock]$SurCoup)

    $partie = $Vue.Partie

    # Un choix de promotion ouvert capte le clic, ou se referme.
    if ($Vue.Promo) {
        foreach ($choix in $Vue.Promo.Cases) {
            if ($choix.Rect.Contains($PX, $PY)) {
                $coup = $choix.Coup
                $Vue.Promo = $null
                Invoke-CoupEchecs $Vue $coup $SurCoup
                return $true
            }
        }
        $Vue.Promo = $null
        return $true
    }

    foreach ($b in $Vue.Boutons) {
        if ($b.Rect.Contains($PX, $PY)) {
            switch ($b.Nom) {
                'Retourner le plateau' { $Vue.Retourne = -not $Vue.Retourne }
                'Nouvelle partie'      { Reset-PartieEchecs $Vue }
            }
            $Vue.Selection = -1; $Vue.Cibles = @()
            return $true
        }
    }

    $case = Get-CaseDepuisPoint $Vue $PX $PY
    if ($case -lt 0 -or -not (Test-MonTour $partie)) {
        $Vue.Selection = -1; $Vue.Cibles = @()
        return $true
    }

    # Deuxième clic sur une case pointée : on joue.
    if ($Vue.Selection -ge 0 -and ($Vue.Cibles -contains $case)) {
        $candidats = @(Get-CoupVers $partie $Vue.Selection $case)
        $Vue.Selection = -1; $Vue.Cibles = @()
        if ($candidats.Count -eq 1) {
            Invoke-CoupEchecs $Vue $candidats[0] $SurCoup
        } elseif ($candidats.Count -gt 1) {
            # Plusieurs coups pour un même trajet : c'est une promotion.
            $Vue.Promo = @{ Depart = ($candidats[0] -band 63); Arrivee = $case
                            Candidats = $candidats; Cases = @() }
        }
        return $true
    }

    # Sinon : sélection d'une de ses propres pièces.
    $piece = $partie.Pos.B[$case]
    $aMoi = $(if ($partie.Local) { $partie.Pos.Trait -eq 'w' } else { $partie.MaCouleur -eq 'w' })
    if ($piece -ne ' ' -and ([char]::IsUpper($piece) -eq $aMoi)) {
        $Vue.Selection = $case
        $Vue.Cibles = @(Get-CoupsDepuis $partie $case)
    } else {
        $Vue.Selection = -1
        $Vue.Cibles = @()
    }
    return $true
}

function Invoke-CoupEchecs {
    param($Vue, [int]$Coup, [scriptblock]$SurCoup)
    if (-not (Add-CoupPartie $Vue.Partie $Coup)) { return }
    [void](Add-ResultatAuScore $Vue.Partie)
    if ($SurCoup) { & $SurCoup $Vue.Partie $Coup }
}

function Reset-PartieEchecs {
    param($Vue)
    $p = $Vue.Partie
    $neuf = New-Partie -Id $p.Id -MaCouleur $p.MaCouleur -MonNom $p.MonNom `
                       -NomAdversaire $p.NomAdversaire -Depart $p.Depart
    foreach ($cle in @('Pos','Coups','San','Positions','DernierDepart','DernierArrivee',
                       'Etat','Resultat','ScoreCompte','Version')) {
        $p[$cle] = $neuf[$cle]
    }
    $Vue.Retourne = ($p.MaCouleur -eq 'b')
}

# ---------------------------------------------------------------------------
#  Aides géométriques
# ---------------------------------------------------------------------------

function Format-Point {
    # Un score d'échecs ne s'écrit pas avec des décimales : 2.5 devient « 2½ ».
    param([double]$Valeur)
    $entier = [int][math]::Floor($Valeur)
    if (($Valeur - $entier) -ge 0.25) {
        return $(if ($entier -eq 0) { '½' } else { [string]$entier + '½' })
    }
    return [string]$entier
}

function New-RectangleArrondi {
    param([System.Drawing.Rectangle]$Rect, [int]$Rayon)
    $c = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $Rayon
    $c.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $c.AddArc(($Rect.Right - $d), $Rect.Y, $d, $d, 270, 90)
    $c.AddArc(($Rect.Right - $d), ($Rect.Bottom - $d), $d, $d, 0, 90)
    $c.AddArc($Rect.X, ($Rect.Bottom - $d), $d, $d, 90, 90)
    $c.CloseFigure()
    return $c
}

function Get-CaseDepuisPoint {
    param($Vue, [int]$PX, [int]$PY)
    if ($Vue.Case -le 0) { return -1 }
    $cx = [math]::Floor(($PX - $Vue.PlateauX) / $Vue.Case)
    $cy = [math]::Floor(($PY - $Vue.PlateauY) / $Vue.Case)
    if ($cx -lt 0 -or $cx -gt 7 -or $cy -lt 0 -or $cy -gt 7) { return -1 }
    # Exactement l'inverse de la projection utilisée par Draw-Echiquier.
    if ($Vue.Retourne) { $col = 7 - $cx; $rng = $cy } else { $col = $cx; $rng = 7 - $cy }
    return [int]($rng * 8 + $col)
}

function Get-PointDepuisCase {
    param($Vue, [int]$Case)
    $col = $script:COL_DE[$Case]; $rng = $script:RNG_DE[$Case]
    $cx = $(if ($Vue.Retourne) { 7 - $col } else { $col })
    $cy = $(if ($Vue.Retourne) { $rng } else { 7 - $rng })
    return New-Object System.Drawing.Point ($Vue.PlateauX + $cx * $Vue.Case), ($Vue.PlateauY + $cy * $Vue.Case)
}

function Draw-ChoixPromotion {
    param($G, $Vue)

    $partie = $Vue.Partie
    $blanc  = ($partie.Pos.Trait -eq 'w')
    $c = $Vue.Case
    $p = Get-PointDepuisCase $Vue $Vue.Promo.Arrivee

    # La pile descend depuis la case d'arrivée, sauf si elle sortirait du
    # plateau — auquel cas elle monte.
    $versLeBas = ($p.Y + 4 * $c) -le ($Vue.PlateauY + $Vue.Plateau)

    # Dame en premier : c'est le choix dans la quasi-totalité des cas.
    $ordre = @('q', 'r', 'b', 'n')
    $Vue.Promo.Cases = @()

    for ($i = 0; $i -lt 4; $i++) {
        $y = $(if ($versLeBas) { $p.Y + $i * $c } else { $p.Y - $i * $c })
        $rect = New-Object System.Drawing.Rectangle $p.X, $y, $c, $c

        $fond = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(252, 250, 250, 246))
        $G.FillRectangle($fond, $rect)
        $fond.Dispose()
        $stylo = New-Object System.Drawing.Pen ($script:Palette.Cadre), ([single][math]::Max(1, $c * 0.03))
        $G.DrawRectangle($stylo, $rect)
        $stylo.Dispose()

        $lettre = $(if ($blanc) { [char]$ordre[$i].ToUpper() } else { [char]$ordre[$i] })
        Draw-Piece $G $lettre $rect.X $rect.Y $c

        $coup = -1
        foreach ($cand in $Vue.Promo.Candidats) {
            if ($script:PROMO_LETTRE[(($cand -shr 12) -band 7)] -eq $ordre[$i]) { $coup = $cand; break }
        }
        if ($coup -ge 0) { $Vue.Promo.Cases += @{ Rect = $rect; Coup = $coup } }
    }
}

# ---------------------------------------------------------------------------
#  La fenêtre elle-même
# ---------------------------------------------------------------------------

function Show-FenetreEchecs {
    param(
        $Partie,
        [scriptblock]$SurCoup = $null,       # appelé après chaque coup joué ici
        [scriptblock]$SurFermeture = $null,
        [string]$CheminIcone = '',
        [string]$Journal = '',
        [switch]$BoucleAutonome              # vrai quand la fenêtre est lancée seule
    )

    if (-not $Journal) {
        $Journal = Join-Path $env:LOCALAPPDATA 'TokenBar\echecs-erreurs.log'
    }
    $vue = New-VueEchecs -Partie $Partie -Journal $Journal

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Échecs — ' + $Partie.NomAdversaire
    $form.StartPosition = 'CenterScreen'
    $form.MinimumSize = New-Object System.Drawing.Size 760, 560
    $form.Size = New-Object System.Drawing.Size 940, 680
    $form.BackColor = $script:Palette.Fond
    if ($CheminIcone -and (Test-Path $CheminIcone)) {
        try { $form.Icon = New-Object System.Drawing.Icon $CheminIcone } catch { }
    }

    $panneau = New-Object System.Windows.Forms.Panel
    $panneau.Dock = 'Fill'
    $panneau.BackColor = $script:Palette.Fond
    # Sans double tampon, le redimensionnement fait clignoter tout le plateau.
    # La propriété n'est pas publique : on passe par la réflexion.
    $panneau.GetType().GetProperty('DoubleBuffered',
        [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($panneau, $true, $null)
    $form.Controls.Add($panneau)

    Update-DispositionEchecs $vue $panneau.ClientSize.Width $panneau.ClientSize.Height

    # Les gestionnaires ne contiennent QUE des appels de fonction : voir la
    # note sur GetNewClosure en tête de fichier.
    $panneau.Add_Paint({
        param($s, $e)
        try { Draw-FenetreEchecs $e.Graphics $vue }
        catch { Draw-ErreurFenetre $e.Graphics $vue $_ }
    }.GetNewClosure())

    $panneau.Add_MouseDown({
        param($s, $e)
        try { [void](Invoke-ClicEchecs $vue $e.X $e.Y $SurCoup) } catch { }
        $s.Invalidate()
    }.GetNewClosure())

    $panneau.Add_Resize({
        param($s, $e)
        Update-DispositionEchecs $vue $s.ClientSize.Width $s.ClientSize.Height
        $s.Invalidate()
    }.GetNewClosure())

    $form.Add_FormClosed({
        foreach ($p in $vue.Polices.Values) { $p.Dispose() }
        if ($SurFermeture) { & $SurFermeture }
    }.GetNewClosure())

    if ($BoucleAutonome) {
        [System.Windows.Forms.Application]::Run($form)
    } else {
        $form.Show()
    }
    return @{ Form = $form; Vue = $vue; Panneau = $panneau }
}
