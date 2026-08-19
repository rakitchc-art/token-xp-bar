# ============================================================================
#  Moteur-Echecs.ps1 — les règles du jeu, et rien d'autre.
#
#  Aucune interface, aucun réseau : ce fichier sait uniquement répondre à
#  « quels coups sont légaux ici ? » et « à quoi ressemble la position après
#  ce coup ? ». Il se teste donc entièrement sans ouvrir une fenêtre.
#
#  Représentation d'un coup : un entier unique, pour que les listes de coups
#  restent légères (une partie en génère des centaines de milliers pendant
#  les tests de conformité).
#     bits  0-5   case de départ  (0 = a1, 7 = h1, 56 = a8, 63 = h8)
#     bits  6-11  case d'arrivée
#     bits 12-14  promotion : 0 aucune, 1 cavalier, 2 fou, 3 tour, 4 dame
#     bits 15-17  nature    : 0 normal, 1 double pas, 2 prise en passant,
#                             3 petit roque, 4 grand roque
# ============================================================================

$script:FEN_DEPART = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'

$script:MV_NORMAL = 0
$script:MV_DOUBLE = 1
$script:MV_EP     = 2
$script:MV_OO     = 3
$script:MV_OOO    = 4

# Lettre de la pièce obtenue par promotion, indexée par le code 1..4.
# Ces lettres sont celles de la notation UCI (langue neutre) : elles servent
# au stockage et aux échanges avec le serveur, jamais à l'affichage.
$script:PROMO_LETTRE = @('', 'n', 'b', 'r', 'q')

# Lettres AFFICHÉES, en français : Roi, Dame, Tour, Fou, Cavalier. La notation
# interne reste anglaise partout ailleurs — mélanger les deux ferait qu'une
# partie enregistrée ici deviendrait illisible par n'importe quel autre outil.
$script:SAN_FR = @{ 'K' = 'R'; 'Q' = 'D'; 'R' = 'T'; 'B' = 'F'; 'N' = 'C' }

# Fichier (colonne) et rangée de chaque case, précalculés : une division
# entière en PowerShell arrondit « au pair le plus proche » ([int](4/8) vaut 0
# mais [int](12/8) vaut 2, pas 1) — une table supprime le piège.
$script:COL_DE = New-Object 'int[]' 64
$script:RNG_DE = New-Object 'int[]' 64
for ($i = 0; $i -lt 64; $i++) {
    $script:COL_DE[$i] = $i % 8
    $script:RNG_DE[$i] = ($i - ($i % 8)) / 8
}

# Directions, en paires (colonne, rangée) séparées : deux tableaux plats sont
# nettement plus rapides qu'un tableau de tableaux.
$script:CAV_DC = @( 1, 2, 2, 1,-1,-2,-2,-1)
$script:CAV_DR = @( 2, 1,-1,-2,-2,-1, 1, 2)
$script:TOU_DC = @( 1,-1, 0, 0)
$script:TOU_DR = @( 0, 0, 1,-1)
$script:FOU_DC = @( 1, 1,-1,-1)
$script:FOU_DR = @( 1,-1, 1,-1)
$script:ROI_DC = @( 1,-1, 0, 0, 1, 1,-1,-1)
$script:ROI_DR = @( 0, 0, 1,-1, 1,-1, 1,-1)

# ---------------------------------------------------------------------------
#  Conversions case <-> notation
# ---------------------------------------------------------------------------

function ConvertTo-CaseIndex {
    param([string]$Case)
    if ($Case.Length -ne 2) { return -1 }
    $c = [int][char]$Case.ToLower()[0] - [int][char]'a'
    $r = [int][char]$Case[1] - [int][char]'1'
    if ($c -lt 0 -or $c -gt 7 -or $r -lt 0 -or $r -gt 7) { return -1 }
    return $r * 8 + $c
}

function ConvertFrom-CaseIndex {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -gt 63) { return '-' }
    return [string][char]([int][char]'a' + $script:COL_DE[$Index]) +
           [string][char]([int][char]'1' + $script:RNG_DE[$Index])
}

# ---------------------------------------------------------------------------
#  Position
# ---------------------------------------------------------------------------

function New-Position {
    param([string]$Fen = $script:FEN_DEPART)

    $parts = ($Fen.Trim() -split '\s+')
    if ($parts.Count -lt 4) { throw "FEN incomplete : '$Fen'" }

    $b = New-Object 'char[]' 64
    for ($i = 0; $i -lt 64; $i++) { $b[$i] = ' ' }

    $rng = 7
    $col = 0
    foreach ($ch in $parts[0].ToCharArray()) {
        if ($ch -eq '/') { $rng--; $col = 0; continue }
        if ($ch -ge '1' -and $ch -le '8') { $col += [int]::Parse([string]$ch); continue }
        if ($rng -lt 0 -or $rng -gt 7 -or $col -lt 0 -or $col -gt 7) {
            throw "FEN invalide (deborde l'echiquier) : '$Fen'"
        }
        $b[$rng * 8 + $col] = $ch
        $col++
    }

    return @{
        B      = $b
        Trait  = $parts[1]
        Roques = $(if ($parts[2] -eq '-') { '' } else { $parts[2] })
        Ep     = $(if ($parts[3] -eq '-') { -1 } else { ConvertTo-CaseIndex $parts[3] })
        Demi   = $(if ($parts.Count -gt 4) { [int]$parts[4] } else { 0 })
        Coup   = $(if ($parts.Count -gt 5) { [int]$parts[5] } else { 1 })
    }
}

function Copy-Position {
    param($Pos)
    return @{
        B      = $Pos.B.Clone()
        Trait  = $Pos.Trait
        Roques = $Pos.Roques
        Ep     = $Pos.Ep
        Demi   = $Pos.Demi
        Coup   = $Pos.Coup
    }
}

function ConvertTo-Fen {
    param($Pos)
    $b = $Pos.B
    $lignes = @()
    for ($rng = 7; $rng -ge 0; $rng--) {
        $ligne = ''
        $vides = 0
        for ($col = 0; $col -lt 8; $col++) {
            $p = $b[$rng * 8 + $col]
            if ($p -eq ' ') { $vides++; continue }
            if ($vides -gt 0) { $ligne += [string]$vides; $vides = 0 }
            $ligne += [string]$p
        }
        if ($vides -gt 0) { $ligne += [string]$vides }
        $lignes += $ligne
    }
    $roques = $(if ($Pos.Roques -eq '') { '-' } else { $Pos.Roques })
    $ep     = $(if ($Pos.Ep -lt 0) { '-' } else { ConvertFrom-CaseIndex $Pos.Ep })
    return ($lignes -join '/') + ' ' + $Pos.Trait + ' ' + $roques + ' ' + $ep +
           ' ' + $Pos.Demi + ' ' + $Pos.Coup
}

# ---------------------------------------------------------------------------
#  Cases attaquées
# ---------------------------------------------------------------------------

function Test-CaseAttaquee {
    param([char[]]$B, [int]$Case, [bool]$ParLesBlancs)

    # ATTENTION : toutes les comparaisons de pièces se font avec -ceq, pas -eq.
    # L'opérateur -eq de PowerShell ignore la casse ([char]'P' -eq 'p' vaut
    # True), or c'est justement la casse qui porte la couleur ici. Avec -eq,
    # un pion blanc en d2 serait vu comme un pion noir attaquant e1, et plus
    # aucun coup ne serait légal.
    $col = $script:COL_DE[$Case]
    $rng = $script:RNG_DE[$Case]

    # Pions. Un pion blanc en (c, r) attaque (c±1, r+1) : la case visée est
    # donc attaquée depuis la rangée du DESSOUS quand l'attaquant est blanc.
    $dr = $(if ($ParLesBlancs) { -1 } else { 1 })
    $pion = $(if ($ParLesBlancs) { [char]'P' } else { [char]'p' })
    $nr = $rng + $dr
    if ($nr -ge 0 -and $nr -lt 8) {
        if ($col -gt 0 -and $B[$nr * 8 + $col - 1] -ceq $pion) { return $true }
        if ($col -lt 7 -and $B[$nr * 8 + $col + 1] -ceq $pion) { return $true }
    }

    # Cavaliers.
    $cav = $(if ($ParLesBlancs) { [char]'N' } else { [char]'n' })
    for ($d = 0; $d -lt 8; $d++) {
        $nc = $col + $script:CAV_DC[$d]
        $nr = $rng + $script:CAV_DR[$d]
        if ($nc -lt 0 -or $nc -gt 7 -or $nr -lt 0 -or $nr -gt 7) { continue }
        if ($B[$nr * 8 + $nc] -ceq $cav) { return $true }
    }

    # Roi adverse.
    $roi = $(if ($ParLesBlancs) { [char]'K' } else { [char]'k' })
    for ($d = 0; $d -lt 8; $d++) {
        $nc = $col + $script:ROI_DC[$d]
        $nr = $rng + $script:ROI_DR[$d]
        if ($nc -lt 0 -or $nc -gt 7 -or $nr -lt 0 -or $nr -gt 7) { continue }
        if ($B[$nr * 8 + $nc] -ceq $roi) { return $true }
    }

    # Lignes droites : tour ou dame.
    $tou = $(if ($ParLesBlancs) { [char]'R' } else { [char]'r' })
    $dam = $(if ($ParLesBlancs) { [char]'Q' } else { [char]'q' })
    for ($d = 0; $d -lt 4; $d++) {
        $nc = $col + $script:TOU_DC[$d]
        $nr = $rng + $script:TOU_DR[$d]
        while ($nc -ge 0 -and $nc -lt 8 -and $nr -ge 0 -and $nr -lt 8) {
            $q = $B[$nr * 8 + $nc]
            if ($q -ne ' ') {
                if ($q -ceq $tou -or $q -ceq $dam) { return $true }
                break
            }
            $nc += $script:TOU_DC[$d]
            $nr += $script:TOU_DR[$d]
        }
    }

    # Diagonales : fou ou dame.
    $fou = $(if ($ParLesBlancs) { [char]'B' } else { [char]'b' })
    for ($d = 0; $d -lt 4; $d++) {
        $nc = $col + $script:FOU_DC[$d]
        $nr = $rng + $script:FOU_DR[$d]
        while ($nc -ge 0 -and $nc -lt 8 -and $nr -ge 0 -and $nr -lt 8) {
            $q = $B[$nr * 8 + $nc]
            if ($q -ne ' ') {
                if ($q -ceq $fou -or $q -ceq $dam) { return $true }
                break
            }
            $nc += $script:FOU_DC[$d]
            $nr += $script:FOU_DR[$d]
        }
    }

    return $false
}

function Get-CaseRoi {
    param([char[]]$B, [bool]$Blanc)
    $roi = $(if ($Blanc) { [char]'K' } else { [char]'k' })
    for ($i = 0; $i -lt 64; $i++) { if ($B[$i] -ceq $roi) { return $i } }   # -ceq : la casse porte la couleur
    return -1
}

function Test-EnEchec {
    param($Pos, [string]$Camp = $null)
    if (-not $Camp) { $Camp = $Pos.Trait }
    $blanc = ($Camp -eq 'w')
    $r = Get-CaseRoi $Pos.B $blanc
    if ($r -lt 0) { return $false }
    return (Test-CaseAttaquee $Pos.B $r (-not $blanc))
}

# ---------------------------------------------------------------------------
#  Génération des coups
# ---------------------------------------------------------------------------

function Add-CoupsGlissants {
    param([char[]]$B, $Liste, [int]$Case, [int]$Col, [int]$Rng,
          [int[]]$DC, [int[]]$DR, [bool]$Blanc)
    for ($d = 0; $d -lt $DC.Length; $d++) {
        $nc = $Col + $DC[$d]
        $nr = $Rng + $DR[$d]
        while ($nc -ge 0 -and $nc -lt 8 -and $nr -ge 0 -and $nr -lt 8) {
            $t = $nr * 8 + $nc
            $q = $B[$t]
            if ($q -eq ' ') {
                $Liste.Add($Case -bor ($t -shl 6))
            } else {
                if ([char]::IsUpper($q) -ne $Blanc) { $Liste.Add($Case -bor ($t -shl 6)) }
                break
            }
            $nc += $DC[$d]
            $nr += $DR[$d]
        }
    }
}

function Get-CoupsPseudoLegaux {
    param($Pos)

    $b = $Pos.B
    $blanc = ($Pos.Trait -eq 'w')
    $liste = New-Object 'System.Collections.Generic.List[int]'

    for ($sq = 0; $sq -lt 64; $sq++) {
        $p = $b[$sq]
        if ($p -eq ' ') { continue }
        if ([char]::IsUpper($p) -ne $blanc) { continue }

        $col = $script:COL_DE[$sq]
        $rng = $script:RNG_DE[$sq]

        switch ([char]::ToUpper($p)) {

            'P' {
                $dir      = $(if ($blanc) { 1 } else { -1 })
                $rngDepart = $(if ($blanc) { 1 } else { 6 })
                $rngPromo  = $(if ($blanc) { 7 } else { 0 })
                $nr = $rng + $dir

                if ($nr -ge 0 -and $nr -lt 8) {
                    # Avance simple.
                    $t = $nr * 8 + $col
                    if ($b[$t] -eq ' ') {
                        if ($nr -eq $rngPromo) {
                            for ($pp = 1; $pp -le 4; $pp++) {
                                $liste.Add($sq -bor ($t -shl 6) -bor ($pp -shl 12))
                            }
                        } else {
                            $liste.Add($sq -bor ($t -shl 6))
                            if ($rng -eq $rngDepart) {
                                $t2 = ($rng + 2 * $dir) * 8 + $col
                                if ($b[$t2] -eq ' ') {
                                    $liste.Add($sq -bor ($t2 -shl 6) -bor ($script:MV_DOUBLE -shl 15))
                                }
                            }
                        }
                    }
                    # Prises en diagonale, prise en passant comprise.
                    foreach ($dc in @(-1, 1)) {
                        $nc = $col + $dc
                        if ($nc -lt 0 -or $nc -gt 7) { continue }
                        $t = $nr * 8 + $nc
                        $q = $b[$t]
                        if ($q -ne ' ') {
                            if ([char]::IsUpper($q) -ne $blanc) {
                                if ($nr -eq $rngPromo) {
                                    for ($pp = 1; $pp -le 4; $pp++) {
                                        $liste.Add($sq -bor ($t -shl 6) -bor ($pp -shl 12))
                                    }
                                } else {
                                    $liste.Add($sq -bor ($t -shl 6))
                                }
                            }
                        } elseif ($Pos.Ep -ge 0 -and $t -eq $Pos.Ep) {
                            $liste.Add($sq -bor ($t -shl 6) -bor ($script:MV_EP -shl 15))
                        }
                    }
                }
            }

            'N' {
                for ($d = 0; $d -lt 8; $d++) {
                    $nc = $col + $script:CAV_DC[$d]
                    $nr = $rng + $script:CAV_DR[$d]
                    if ($nc -lt 0 -or $nc -gt 7 -or $nr -lt 0 -or $nr -gt 7) { continue }
                    $t = $nr * 8 + $nc
                    $q = $b[$t]
                    if ($q -eq ' ' -or ([char]::IsUpper($q) -ne $blanc)) {
                        $liste.Add($sq -bor ($t -shl 6))
                    }
                }
            }

            'B' { Add-CoupsGlissants $b $liste $sq $col $rng $script:FOU_DC $script:FOU_DR $blanc }
            'R' { Add-CoupsGlissants $b $liste $sq $col $rng $script:TOU_DC $script:TOU_DR $blanc }
            'Q' { Add-CoupsGlissants $b $liste $sq $col $rng $script:ROI_DC $script:ROI_DR $blanc }

            'K' {
                for ($d = 0; $d -lt 8; $d++) {
                    $nc = $col + $script:ROI_DC[$d]
                    $nr = $rng + $script:ROI_DR[$d]
                    if ($nc -lt 0 -or $nc -gt 7 -or $nr -lt 0 -or $nr -gt 7) { continue }
                    $t = $nr * 8 + $nc
                    $q = $b[$t]
                    if ($q -eq ' ' -or ([char]::IsUpper($q) -ne $blanc)) {
                        $liste.Add($sq -bor ($t -shl 6))
                    }
                }

                # Roques. Les trois cases traversées par le roi (départ,
                # passage, arrivée) doivent être hors d'échec, et les cases
                # intermédiaires vides.
                $advBlanc = (-not $blanc)
                if ($blanc -and $sq -eq 4) {
                    if ($Pos.Roques.Contains('K') -and $b[7] -ceq 'R' -and
                        $b[5] -eq ' ' -and $b[6] -eq ' ' -and
                        -not (Test-CaseAttaquee $b 4 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 5 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 6 $advBlanc)) {
                        $liste.Add(4 -bor (6 -shl 6) -bor ($script:MV_OO -shl 15))
                    }
                    if ($Pos.Roques.Contains('Q') -and $b[0] -ceq 'R' -and
                        $b[1] -eq ' ' -and $b[2] -eq ' ' -and $b[3] -eq ' ' -and
                        -not (Test-CaseAttaquee $b 4 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 3 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 2 $advBlanc)) {
                        $liste.Add(4 -bor (2 -shl 6) -bor ($script:MV_OOO -shl 15))
                    }
                } elseif ((-not $blanc) -and $sq -eq 60) {
                    if ($Pos.Roques.Contains('k') -and $b[63] -ceq 'r' -and
                        $b[61] -eq ' ' -and $b[62] -eq ' ' -and
                        -not (Test-CaseAttaquee $b 60 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 61 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 62 $advBlanc)) {
                        $liste.Add(60 -bor (62 -shl 6) -bor ($script:MV_OO -shl 15))
                    }
                    if ($Pos.Roques.Contains('q') -and $b[56] -ceq 'r' -and
                        $b[57] -eq ' ' -and $b[58] -eq ' ' -and $b[59] -eq ' ' -and
                        -not (Test-CaseAttaquee $b 60 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 59 $advBlanc) -and
                        -not (Test-CaseAttaquee $b 58 $advBlanc)) {
                        $liste.Add(60 -bor (58 -shl 6) -bor ($script:MV_OOO -shl 15))
                    }
                }
            }
        }
    }

    return $liste
}

function Invoke-Coup {
    param($Pos, [int]$Coup)

    $depart  = $Coup -band 63
    $arrivee = ($Coup -shr 6) -band 63
    $promo   = ($Coup -shr 12) -band 7
    $nature  = ($Coup -shr 15) -band 7

    $n = Copy-Position $Pos
    $b = $n.B
    $piece = $b[$depart]
    $prise = ($b[$arrivee] -ne ' ')
    $blanc = ($Pos.Trait -eq 'w')

    $b[$arrivee] = $piece
    $b[$depart]  = ' '

    if ($nature -eq $script:MV_EP) {
        # Le pion capturé n'est pas sur la case d'arrivée : il est juste
        # derrière, sur la rangée du pion qui vient de doubler.
        $capt = $script:RNG_DE[$depart] * 8 + $script:COL_DE[$arrivee]
        $b[$capt] = ' '
        $prise = $true
    } elseif ($nature -eq $script:MV_OO) {
        if ($blanc) { $b[5] = $b[7]; $b[7] = ' ' } else { $b[61] = $b[63]; $b[63] = ' ' }
    } elseif ($nature -eq $script:MV_OOO) {
        if ($blanc) { $b[3] = $b[0]; $b[0] = ' ' } else { $b[59] = $b[56]; $b[56] = ' ' }
    }

    if ($promo -gt 0) {
        $lettre = $script:PROMO_LETTRE[$promo]
        $b[$arrivee] = $(if ($blanc) { [char]$lettre.ToUpper() } else { [char]$lettre })
    }

    # Droits de roque : perdus dès que le roi bouge, dès que la tour bouge,
    # et dès qu'une tour est capturée sur sa case d'origine.
    $roques = $n.Roques
    $majuscule = [char]::ToUpper($piece)
    if ($majuscule -eq 'K') {
        # -creplace, pas -replace : l'opérateur -replace ignore la casse par
        # défaut, donc '[KQ]' effacerait aussi les droits noirs 'kq'.
        $roques = $(if ($blanc) { $roques -creplace '[KQ]', '' } else { $roques -creplace '[kq]', '' })
    }
    foreach ($paire in @(@(0, 'Q'), @(7, 'K'), @(56, 'q'), @(63, 'k'))) {
        if ($depart -eq $paire[0] -or $arrivee -eq $paire[0]) {
            $roques = $roques.Replace([string]$paire[1], '')
        }
    }
    $n.Roques = $roques

    $n.Ep = $(if ($nature -eq $script:MV_DOUBLE) {
        ($script:RNG_DE[$depart] + $script:RNG_DE[$arrivee]) / 2 * 8 + $script:COL_DE[$depart]
    } else { -1 })

    $n.Demi = $(if ($majuscule -eq 'P' -or $prise) { 0 } else { $Pos.Demi + 1 })
    if (-not $blanc) { $n.Coup = $Pos.Coup + 1 }
    $n.Trait = $(if ($blanc) { 'b' } else { 'w' })

    return $n
}

function Get-CoupsLegaux {
    param($Pos)

    $blanc = ($Pos.Trait -eq 'w')
    $legaux = New-Object 'System.Collections.Generic.List[int]'
    foreach ($c in (Get-CoupsPseudoLegaux $Pos)) {
        $apres = Invoke-Coup $Pos $c
        $r = Get-CaseRoi $apres.B $blanc
        if ($r -lt 0) { continue }
        if (-not (Test-CaseAttaquee $apres.B $r (-not $blanc))) { $legaux.Add($c) }
    }
    return $legaux
}

# ---------------------------------------------------------------------------
#  État de la partie
# ---------------------------------------------------------------------------

function Test-MaterielInsuffisant {
    param([char[]]$B)
    $mineures = 0
    for ($i = 0; $i -lt 64; $i++) {
        $p = [char]::ToUpper($B[$i])
        switch ($p) {
            ' ' { }
            'K' { }
            'N' { $mineures++ }
            'B' { $mineures++ }
            default { return $false }   # un pion, une tour ou une dame suffit
        }
    }
    return ($mineures -le 1)
}

function Get-EtatPartie {
    param($Pos, [string[]]$Historique = @())

    $legaux = Get-CoupsLegaux $Pos
    $echec  = Test-EnEchec $Pos

    if ($legaux.Count -eq 0) {
        return $(if ($echec) { 'mat' } else { 'pat' })
    }
    if (Test-MaterielInsuffisant $Pos.B) { return 'nulle-materiel' }
    if ($Pos.Demi -ge 100) { return 'nulle-50' }

    if ($Historique.Count -gt 0) {
        $cle = (ConvertTo-Fen $Pos) -replace '\s+\d+\s+\d+$', ''
        $vues = 0
        foreach ($h in $Historique) { if ($h -eq $cle) { $vues++ } }
        if ($vues -ge 3) { return 'nulle-repetition' }
    }

    return $(if ($echec) { 'echec' } else { 'jeu' })
}

# ---------------------------------------------------------------------------
#  Notations
# ---------------------------------------------------------------------------

function ConvertTo-Uci {
    param([int]$Coup)
    $depart  = $Coup -band 63
    $arrivee = ($Coup -shr 6) -band 63
    $promo   = ($Coup -shr 12) -band 7
    return (ConvertFrom-CaseIndex $depart) + (ConvertFrom-CaseIndex $arrivee) +
           $script:PROMO_LETTRE[$promo]
}

function ConvertFrom-Uci {
    param($Pos, [string]$Texte)
    $t = $Texte.Trim().ToLower()
    if ($t.Length -lt 4) { return -1 }
    foreach ($c in (Get-CoupsLegaux $Pos)) {
        if ((ConvertTo-Uci $c) -eq $t) { return $c }
    }
    return -1
}

function ConvertTo-San {
    param($Pos, [int]$Coup)

    $depart  = $Coup -band 63
    $arrivee = ($Coup -shr 6) -band 63
    $promo   = ($Coup -shr 12) -band 7
    $nature  = ($Coup -shr 15) -band 7

    if ($nature -eq $script:MV_OO)  { $texte = 'O-O' }
    elseif ($nature -eq $script:MV_OOO) { $texte = 'O-O-O' }
    else {
        $piece = [char]::ToUpper($Pos.B[$depart])
        $prise = ($Pos.B[$arrivee] -ne ' ') -or ($nature -eq $script:MV_EP)

        if ($piece -eq 'P') {
            $texte = $(if ($prise) { [string][char]([int][char]'a' + $script:COL_DE[$depart]) + 'x' } else { '' })
            $texte += ConvertFrom-CaseIndex $arrivee
        } else {
            # Levée d'ambiguïté : si une autre pièce du même type peut aller
            # sur la même case, on précise la colonne, sinon la rangée.
            $memeCol = $false; $memeRng = $false; $ambigu = $false
            foreach ($autre in (Get-CoupsLegaux $Pos)) {
                if ($autre -eq $Coup) { continue }
                $ad = $autre -band 63
                if ((($autre -shr 6) -band 63) -ne $arrivee) { continue }
                if ([char]::ToUpper($Pos.B[$ad]) -ne $piece) { continue }
                $ambigu = $true
                if ($script:COL_DE[$ad] -eq $script:COL_DE[$depart]) { $memeCol = $true }
                if ($script:RNG_DE[$ad] -eq $script:RNG_DE[$depart]) { $memeRng = $true }
            }
            $precision = ''
            if ($ambigu) {
                if (-not $memeCol) { $precision = [string][char]([int][char]'a' + $script:COL_DE[$depart]) }
                elseif (-not $memeRng) { $precision = [string][char]([int][char]'1' + $script:RNG_DE[$depart]) }
                else { $precision = ConvertFrom-CaseIndex $depart }
            }
            $texte = $script:SAN_FR[[string]$piece] + $precision + $(if ($prise) { 'x' } else { '' }) +
                     (ConvertFrom-CaseIndex $arrivee)
        }

        if ($promo -gt 0) {
            $texte += '=' + $script:SAN_FR[$script:PROMO_LETTRE[$promo].ToUpper()]
        }
    }

    $apres = Invoke-Coup $Pos $Coup
    $etat  = Get-EtatPartie $apres
    if ($etat -eq 'mat') { $texte += '#' } elseif ($etat -eq 'echec') { $texte += '+' }
    return $texte
}

# ---------------------------------------------------------------------------
#  Perft — le seul juge honnête d'un générateur de coups.
#
#  Compte les feuilles de l'arbre des coups légaux à une profondeur donnée.
#  Les valeurs de référence sont publiques et connues au nœud près : un
#  générateur qui se trompe sur un roque, une prise en passant ou une clouure
#  produit un total faux. Impossible de passer par hasard.
# ---------------------------------------------------------------------------

function Measure-Perft {
    param($Pos, [int]$Profondeur)
    if ($Profondeur -le 0) { return 1 }
    $legaux = Get-CoupsLegaux $Pos
    if ($Profondeur -eq 1) { return $legaux.Count }
    $total = 0
    foreach ($c in $legaux) {
        $total += Measure-Perft (Invoke-Coup $Pos $c) ($Profondeur - 1)
    }
    return $total
}

function Measure-PerftDetail {
    param($Pos, [int]$Profondeur)
    $detail = [ordered]@{}
    foreach ($c in (Get-CoupsLegaux $Pos)) {
        $detail[(ConvertTo-Uci $c)] = (Measure-Perft (Invoke-Coup $Pos $c) ($Profondeur - 1))
    }
    return $detail
}
