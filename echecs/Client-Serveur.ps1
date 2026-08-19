# ============================================================================
#  Client-Serveur.ps1 — le dialogue avec la boîte aux lettres distante.
#
#  Le serveur ne connaît pas les règles : il tient une liste de coups. C'est
#  ici qu'on la REJOUE dans le moteur local avant d'y croire. Une liste
#  contenant un coup impossible est refusée en bloc, avec un message clair,
#  plutôt que d'aboutir à un échiquier incohérent.
#
#  Dépend de Moteur-Echecs.ps1 et Partie-Echecs.ps1.
# ============================================================================

function ConvertTo-AdresseServeur {
    # Accepte ce qu'un humain tape : « 12.34.56.78 », « 12.34.56.78:8137 »,
    # « http://mondomaine.fr/echecs ». Renvoie une base d'URL utilisable.
    param([string]$Saisie)

    $t = ($Saisie + '').Trim()
    if (-not $t) { return '' }
    if ($t -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $t = 'http://' + $t }
    try { $u = [uri]$t } catch { return '' }
    if (-not $u.Host) { return '' }

    $port = $(if ($u.IsDefaultPort -and $t -notmatch ':\d+') { 8137 } else { $u.Port })
    $base = $u.Scheme + '://' + $u.Host + ':' + $port
    $chemin = $u.AbsolutePath.TrimEnd('/')
    if ($chemin -and $chemin -ne '/') { $base += $chemin }
    return $base
}

function Invoke-ServeurEchecs {
    # Un appel au serveur. Ne lève JAMAIS d'exception : renvoie toujours un
    # objet avec Ok/Erreur, pour qu'un serveur éteint ne fasse pas tomber la
    # fenêtre de jeu ni la barre TokenBar qui l'héberge.
    param(
        [string]$Adresse,
        [string]$Code,
        [string]$Joueur,
        [string]$Route,
        [hashtable]$Corps = @{},
        [int]$Delai = 8
    )

    $base = ConvertTo-AdresseServeur $Adresse
    if (-not $base) { return @{ Ok = $false; Erreur = 'Adresse de serveur illisible.' } }

    $charge = @{ code = $Code; joueur = $Joueur }
    foreach ($k in $Corps.Keys) { $charge[$k] = $Corps[$k] }
    $json = ($charge | ConvertTo-Json -Compress -Depth 5)

    try {
        $r = Invoke-RestMethod -Uri ($base + $Route) -Method Post -Body $json `
                               -ContentType 'application/json; charset=utf-8' `
                               -TimeoutSec $Delai -ErrorAction Stop
        return @{ Ok = $true; Etat = $r.etat; Reponse = $r }
    } catch {
        # Le serveur explique ses refus dans le corps de la réponse ; le laisser
        # tomber transformerait « ce n'est pas ton tour » en « (409) Conflit ».
        $err = $_
        $codeHttp = 0
        $detail = $err.Exception.Message
        $etat = $null

        $rep = $err.Exception.Response
        if ($rep) { try { $codeHttp = [int]$rep.StatusCode } catch { } }

        # En PowerShell 5.1, Invoke-RestMethod a DÉJÀ lu le corps de la réponse
        # d'erreur et le range dans ErrorDetails.Message. Relire le flux après
        # coup ne rend rien : il est consommé. D'où l'ordre ci-dessous.
        $brut = $null
        if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
            $brut = $err.ErrorDetails.Message
        } elseif ($rep) {
            try {
                $flux = New-Object System.IO.StreamReader($rep.GetResponseStream())
                $brut = $flux.ReadToEnd()
                $flux.Close()
            } catch { }
        }

        if ($brut) {
            try {
                $o = $brut | ConvertFrom-Json
                if ($o.erreur) { $detail = $o.erreur }
                if ($o.etat)   { $etat = $o.etat }
            } catch { }
        }
        return @{ Ok = $false; Erreur = $detail; CodeHttp = $codeHttp; Etat = $etat }
    }
}

function Sync-PartieDepuisServeur {
    # Applique un état reçu du serveur à une partie locale. La liste de coups
    # est REJOUÉE par le moteur : si elle contient l'impossible, on refuse tout
    # et on le dit, plutôt que d'afficher un échiquier faux.
    param($Partie, $Etat, [string]$MonNom)

    if (-not $Etat) { return @{ Ok = $false; Erreur = 'Etat vide.' } }

    $couleur = $null
    if ($Etat.joueurs.w -eq $MonNom) { $couleur = 'w' }
    elseif ($Etat.joueurs.b -eq $MonNom) { $couleur = 'b' }
    if (-not $couleur) {
        return @{ Ok = $false; Erreur = "Le serveur ne te connait pas dans cette partie." }
    }

    $Partie.MaCouleur     = $couleur
    $Partie.MonNom        = $MonNom
    $Partie.NomAdversaire = $(if ($couleur -eq 'w') { $Etat.joueurs.b } else { $Etat.joueurs.w })
    $Partie.Id            = $Etat.partieId
    $Partie.Local         = $false

    $coups = @()
    if ($Etat.coups) { $coups = @($Etat.coups) }
    if (-not (Set-PartieDepuisCoups $Partie $coups)) {
        return @{ Ok = $false; Erreur = 'La partie recue contient un coup impossible : rien n a ete applique.' }
    }

    # Les scores sont tenus par le serveur : lui seul voit les deux joueurs.
    if ($Etat.scores) {
        $mien = $Etat.scores.$MonNom
        $sien = $Etat.scores.($Partie.NomAdversaire)
        $Partie.MesPoints = $(if ($null -ne $mien) { [double]$mien } else { 0.0 })
        $Partie.SesPoints = $(if ($null -ne $sien) { [double]$sien } else { 0.0 })
    }

    # Le serveur fait foi sur la fin de partie : il connaît l'abandon, que le
    # moteur ne peut pas déduire de la seule position.
    if ($Etat.termine -and $Etat.resultat) {
        $Partie.Resultat = $Etat.resultat
        if ($Partie.Etat -eq 'jeu' -or $Partie.Etat -eq 'echec') { $Partie.Etat = 'abandon' }
    }

    return @{ Ok = $true; Etat = $Etat }
}

function Send-CoupServeur {
    # Envoie un coup, puis resynchronise la partie sur ce que le serveur a
    # réellement enregistré — jamais sur ce qu'on croit avoir envoyé.
    param($Partie, [string]$Adresse, [string]$Code, [string]$MonNom,
          [string]$CoupUci, [int]$AvantVersion)

    $corps = @{ coup = $CoupUci; apresVersion = $AvantVersion }
    if ($Partie.Resultat) { $corps['resultat'] = $Partie.Resultat }

    $r = Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $MonNom `
                              -Route '/coup' -Corps $corps
    if (-not $r.Ok) {
        # Même en cas de refus, le serveur renvoie l'état courant : on s'y
        # recale, sinon le joueur reste devant une position qui n'existe pas.
        if ($r.Etat) { [void](Sync-PartieDepuisServeur $Partie $r.Etat $MonNom) }
        return $r
    }
    return (Sync-PartieDepuisServeur $Partie $r.Etat $MonNom)
}
