# ============================================================================
#  Partie-Echecs.ps1 — l'état d'une partie, sans interface ni réseau.
#
#  Une partie n'est PAS stockée comme « la position actuelle » mais comme
#  « la position de départ + la liste des coups joués ». C'est ce qui rend la
#  synchronisation avec le serveur sûre : au lieu de recevoir un échiquier
#  déjà arrangé et de devoir le croire, on reçoit une liste de coups et on la
#  rejoue soi-même à travers le moteur. Un coup illégal glissé dans la liste
#  est refusé ici, pas découvert trois coups plus tard.
#
#  Dépend de Moteur-Echecs.ps1 (à charger avant).
# ============================================================================

function New-Partie {
    param(
        [string]$Id = '',
        [string]$MaCouleur = 'w',
        [string]$MonNom = 'Moi',
        [string]$NomAdversaire = 'Adversaire',
        [string]$Depart = $script:FEN_DEPART,
        [double]$MesPoints = 0.0,
        [double]$SesPoints = 0.0,
        [switch]$Local
    )

    $p = @{
        Id             = $Id
        Depart         = $Depart
        MaCouleur      = $MaCouleur
        MonNom         = $MonNom
        NomAdversaire  = $NomAdversaire
        MesPoints      = $MesPoints
        SesPoints      = $SesPoints
        # Mode « les deux camps sur le même écran » : sert à jouer seul contre
        # soi-même pour éprouver l'interface, et à tester sans serveur.
        Local          = [bool]$Local

        Pos            = (New-Position $Depart)
        Coups          = (New-Object 'System.Collections.Generic.List[string]')   # notation UCI
        San            = (New-Object 'System.Collections.Generic.List[string]')   # notation lisible
        Positions      = (New-Object 'System.Collections.Generic.List[string]')   # pour la répétition

        DernierDepart  = -1
        DernierArrivee = -1
        Etat           = 'jeu'
        Resultat       = ''      # '', '1-0', '0-1', '1/2-1/2'
        ScoreCompte    = $false  # le résultat a-t-il déjà été porté au score ?
        Version        = 0
    }
    $p.Positions.Add((Get-CleRepetition $p.Pos))
    $p.Etat = Get-EtatPartie $p.Pos
    return $p
}

function Get-CleRepetition {
    # Deux positions se répètent si l'échiquier, le trait, les droits de roque
    # et la case de prise en passant coïncident — les compteurs de coups, eux,
    # ne comptent pas. On retire donc les deux derniers champs de la FEN.
    param($Pos)
    return ((ConvertTo-Fen $Pos) -replace '\s+\d+\s+\d+$', '')
}

function Add-CoupPartie {
    # Joue un coup et met la partie à jour. Renvoie $true si le coup a été
    # accepté, $false s'il était illégal (la partie reste alors intacte).
    param($Partie, [int]$Coup)

    $legaux = @(Get-CoupsLegaux $Partie.Pos)
    if ($legaux -notcontains $Coup) { return $false }

    $Partie.San.Add((ConvertTo-San $Partie.Pos $Coup))
    $Partie.Coups.Add((ConvertTo-Uci $Coup))
    $Partie.DernierDepart  = $Coup -band 63
    $Partie.DernierArrivee = ($Coup -shr 6) -band 63
    $Partie.Pos = Invoke-Coup $Partie.Pos $Coup
    $Partie.Positions.Add((Get-CleRepetition $Partie.Pos))
    $Partie.Version++

    $Partie.Etat = Get-EtatPartie $Partie.Pos $Partie.Positions.ToArray()
    $Partie.Resultat = Get-ResultatPartie $Partie
    return $true
}

function Get-ResultatPartie {
    param($Partie)
    switch ($Partie.Etat) {
        'mat' {
            # Le camp au trait est maté : c'est l'autre qui gagne.
            return $(if ($Partie.Pos.Trait -eq 'w') { '0-1' } else { '1-0' })
        }
        'pat'              { return '1/2-1/2' }
        'nulle-materiel'   { return '1/2-1/2' }
        'nulle-50'         { return '1/2-1/2' }
        'nulle-repetition' { return '1/2-1/2' }
        default            { return '' }
    }
}

function Test-PartieTerminee {
    param($Partie)
    return ($Partie.Resultat -ne '')
}

function Test-MonTour {
    param($Partie)
    if (Test-PartieTerminee $Partie) { return $false }
    if ($Partie.Local) { return $true }
    return ($Partie.Pos.Trait -eq $Partie.MaCouleur)
}

function Add-ResultatAuScore {
    # Reporte le résultat de la partie au score cumulé : victoire 1 point,
    # nulle ½, défaite 0. À n'appeler qu'une fois par partie terminée — d'où
    # le drapeau ScoreCompte, qui rend l'appel idempotent.
    param($Partie)
    if (-not (Test-PartieTerminee $Partie)) { return $false }
    if ($Partie.ScoreCompte) { return $false }

    switch ($Partie.Resultat) {
        '1/2-1/2' { $Partie.MesPoints += 0.5; $Partie.SesPoints += 0.5 }
        '1-0' {
            if ($Partie.MaCouleur -eq 'w') { $Partie.MesPoints += 1.0 } else { $Partie.SesPoints += 1.0 }
        }
        '0-1' {
            if ($Partie.MaCouleur -eq 'b') { $Partie.MesPoints += 1.0 } else { $Partie.SesPoints += 1.0 }
        }
    }
    $Partie.ScoreCompte = $true
    return $true
}

function Set-PartieDepuisCoups {
    # Rejoue une partie entière à partir de sa liste de coups. C'est le point
    # d'entrée de la synchronisation : ce que le serveur envoie est REJOUÉ,
    # jamais recopié tel quel. Renvoie $true si toute la liste est légale.
    param($Partie, [string[]]$CoupsUci)

    $neuf = New-Partie -Id $Partie.Id -MaCouleur $Partie.MaCouleur `
                       -MonNom $Partie.MonNom -NomAdversaire $Partie.NomAdversaire `
                       -Depart $Partie.Depart

    foreach ($u in $CoupsUci) {
        if (-not $u) { continue }
        $c = ConvertFrom-Uci $neuf.Pos $u
        if ($c -lt 0) { return $false }
        if (-not (Add-CoupPartie $neuf $c)) { return $false }
    }

    $Partie.Pos            = $neuf.Pos
    $Partie.Coups          = $neuf.Coups
    $Partie.San            = $neuf.San
    $Partie.Positions      = $neuf.Positions
    $Partie.DernierDepart  = $neuf.DernierDepart
    $Partie.DernierArrivee = $neuf.DernierArrivee
    $Partie.Etat           = $neuf.Etat
    $Partie.Resultat       = $neuf.Resultat
    $Partie.ScoreCompte    = $neuf.ScoreCompte
    $Partie.Version        = $neuf.Coups.Count
    return $true
}

function Get-CaseRoiEnEchec {
    # Case du roi à entourer de rouge, ou -1 s'il n'y a pas d'échec.
    param($Partie)
    if ($Partie.Etat -ne 'echec' -and $Partie.Etat -ne 'mat') { return -1 }
    return (Get-CaseRoi $Partie.Pos.B ($Partie.Pos.Trait -eq 'w'))
}

function Get-TexteEtat {
    # La phrase affichée au joueur. Volontairement à la deuxième personne :
    # après plusieurs heures sans regarder, la seule question est « est-ce que
    # c'est à moi ? ».
    param($Partie)

    switch ($Partie.Etat) {
        'mat' {
            $gagnant = $(if ($Partie.Pos.Trait -eq $Partie.MaCouleur) { $Partie.NomAdversaire } else { $Partie.MonNom })
            return "Échec et mat — $gagnant gagne"
        }
        'pat'              { return 'Pat — partie nulle' }
        'nulle-materiel'   { return 'Matériel insuffisant — partie nulle' }
        'nulle-50'         { return 'Règle des 50 coups — partie nulle' }
        'nulle-repetition' { return 'Triple répétition — partie nulle' }
        'echec' {
            if (Test-MonTour $Partie) { return 'Échec ! À toi de jouer' }
            return "Échec ! $($Partie.NomAdversaire) doit répondre"
        }
        default {
            if (Test-MonTour $Partie) { return 'À toi de jouer' }
            return "Au tour de $($Partie.NomAdversaire)"
        }
    }
}

function Get-CoupsDepuis {
    # Les cases d'arrivée légales pour la pièce posée sur une case donnée.
    param($Partie, [int]$Case)
    $cibles = New-Object 'System.Collections.Generic.List[int]'
    foreach ($c in (Get-CoupsLegaux $Partie.Pos)) {
        if (($c -band 63) -eq $Case) { $cibles.Add((($c -shr 6) -band 63)) }
    }
    return $cibles
}

function Get-CoupVers {
    # Le coup qui va d'une case à une autre. S'il y a plusieurs candidats,
    # c'est une promotion : on renvoie tous les choix pour laisser trancher.
    param($Partie, [int]$Depart, [int]$Arrivee)
    $candidats = New-Object 'System.Collections.Generic.List[int]'
    foreach ($c in (Get-CoupsLegaux $Partie.Pos)) {
        if (($c -band 63) -eq $Depart -and ((($c -shr 6) -band 63) -eq $Arrivee)) {
            $candidats.Add($c)
        }
    }
    return $candidats
}
