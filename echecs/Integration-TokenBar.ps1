# ============================================================================
#  Integration-TokenBar.ps1 — l'easter egg.
#
#  Tant qu'aucun serveur n'est enregistré, ce fichier ne fait rien de visible :
#  la barre est identique à ce qu'elle a toujours été. Le jeu ne se révèle
#  qu'après un geste caché — Ctrl + Maj + double-clic sur le cœur — qui ouvre
#  le seul endroit où saisir une adresse de serveur.
#
#  Ensuite, une petite flèche s'affiche sous le pourcentage. Un clic déplie le
#  plateau sous la barre, un autre le replie. Aucune fenêtre séparée : rien
#  dans la barre des tâches, rien qui vole le premier plan, aucun délai
#  d'ouverture.
#
#  RÈGLE DU RÉSEAU, valable partout ici : l'interface n'attend JAMAIS le
#  serveur. Un coup joué s'affiche immédiatement et part ensuite dans un fil
#  séparé. Sur une connexion lente, l'ancienne version figeait la fenêtre
#  pendant tout l'aller-retour.
#
#  RAPPEL DE PORTÉE : dans un bloc créé avec .GetNewClosure(), toute variable
#  $script: vaut $null. Les fermetures d'ici ne manipulent que des variables
#  locales et des appels de fonction.
# ============================================================================

# Chargé au niveau du script, jamais dans une fonction : un « . fichier.ps1 »
# exécuté dans une fonction y définit ses fonctions, qui disparaissent au
# retour. Le chargement paraît réussir et tout casse au premier appel.
. (Join-Path $PSScriptRoot 'Moteur-Echecs.ps1')
. (Join-Path $PSScriptRoot 'Rendu-Echiquier.ps1')
. (Join-Path $PSScriptRoot 'Partie-Echecs.ps1')
. (Join-Path $PSScriptRoot 'Client-Serveur.ps1')
. (Join-Path $PSScriptRoot 'Plateau-Barre.ps1')

# ---------------------------------------------------------------------------
#  Configuration
# ---------------------------------------------------------------------------

function Test-EchecsConfigure {
    param($Config)
    return ([string]$Config.EchecsAdresse -ne '' -and
            [string]$Config.EchecsCode    -ne '' -and
            [string]$Config.EchecsNom     -ne '')
}

function Invoke-EssaiConnexion {
    # Un essai depuis le dialogue. $Etat porte l'empreinte déjà connue et se
    # met à jour avec celle qu'on vient de voir.
    #
    # Règle d'épinglage : on n'accepte un certificat inconnu QUE si aucune
    # empreinte n'est enregistrée pour cette adresse. Changer d'adresse remet
    # le compteur à zéro ; un certificat qui change sur la MÊME adresse est
    # refusé — c'est tout l'intérêt.
    param([string]$Nom, [string]$Adresse, [string]$Code, $Etat)

    $memeServeur = ((ConvertTo-AdresseServeur $Adresse) -eq (ConvertTo-AdresseServeur $Etat.AdresseConnue))
    $empreinte = $(if ($memeServeur) { [string]$Etat.EmpreinteConnue } else { '' })

    if ($empreinte) {
        $r = Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $Nom `
                                  -Route '/etat' -Delai 8 -Empreinte $empreinte
    } else {
        $r = Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $Nom `
                                  -Route '/etat' -Delai 8 -AutoriserPremiere
    }

    if ($r.Ok -and $r.EmpreinteVue) {
        $Etat.EmpreinteConnue = [string]$r.EmpreinteVue
        $Etat.AdresseConnue   = $Adresse
    }
    return $r
}

function Write-EtatConnexion {
    param($Etiquette, $Reponse)
    if ($Reponse.Ok) {
        $Etiquette.ForeColor = [System.Drawing.Color]::FromArgb(120, 200, 120)
        $Etiquette.Text = ('Serveur joignable. Blancs : ' + $Reponse.Etat.joueurs.w +
                           '   Noirs : ' + $Reponse.Etat.joueurs.b)
    } else {
        $Etiquette.ForeColor = [System.Drawing.Color]::FromArgb(226, 96, 80)
        $Etiquette.Text = ('Echec : ' + $Reponse.Erreur)
    }
}

function New-ChampDialogue {
    param($Parent, [string]$Libelle, [string]$Valeur, [ref]$Y, [bool]$Secret = $false)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Libelle
    $l.SetBounds(16, $Y.Value, 124, 24)
    $l.TextAlign = 'MiddleLeft'
    $Parent.Controls.Add($l)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $Valeur
    $t.SetBounds(146, $Y.Value, 266, 24)
    $t.BackColor = [System.Drawing.Color]::FromArgb(28, 27, 25)
    $t.ForeColor = [System.Drawing.Color]::FromArgb(238, 236, 231)
    $t.BorderStyle = 'FixedSingle'
    if ($Secret) { $t.UseSystemPasswordChar = $true }
    $Parent.Controls.Add($t)
    $Y.Value = $Y.Value + 36
    return $t
}

function Show-DialogueConnexionEchecs {
    # La seule porte d'entrée. Trois champs, un essai avant d'enregistrer, et
    # un bouton pour tout effacer — qui fait disparaître le jeu comme s'il
    # n'avait jamais existé.
    param($Config, [string]$CheminIcone = '')

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Connexion'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'
    $f.ClientSize = New-Object System.Drawing.Size 430, 250
    $f.BackColor = [System.Drawing.Color]::FromArgb(38, 36, 33)
    $f.ForeColor = [System.Drawing.Color]::FromArgb(232, 230, 225)
    $f.Font = New-Object System.Drawing.Font 'Segoe UI', 9.5
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    if ($CheminIcone -and (Test-Path $CheminIcone)) {
        try { $f.Icon = New-Object System.Drawing.Icon $CheminIcone } catch { }
    }

    $y = 18
    $tNom     = New-ChampDialogue $f 'Ton nom de joueur'  ([string]$Config.EchecsNom)     ([ref]$y)
    $tAdresse = New-ChampDialogue $f 'Adresse du serveur' ([string]$Config.EchecsAdresse) ([ref]$y)
    $tCode    = New-ChampDialogue $f 'Code partage'       ([string]$Config.EchecsCode)    ([ref]$y) $true

    $etat = New-Object System.Windows.Forms.Label
    $etat.SetBounds(16, ($y + 4), 396, 48)
    $etat.Text = "Ton nom doit etre different de celui de ton adversaire, et rester le meme d'une partie a l'autre."
    $etat.ForeColor = [System.Drawing.Color]::FromArgb(150, 148, 143)
    $f.Controls.Add($etat)

    $bTester  = New-Object System.Windows.Forms.Button
    $bOublier = New-Object System.Windows.Forms.Button
    $bOk      = New-Object System.Windows.Forms.Button
    foreach ($paire in @(@($bTester, 'Tester', 16), @($bOublier, 'Oublier', 124), @($bOk, 'Enregistrer', 312))) {
        $b = $paire[0]
        $b.Text = $paire[1]
        $b.SetBounds($paire[2], 202, 102, 30)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(96, 93, 88)
        # Un bouton IGNORE sa couleur de fond tant que UseVisualStyleBackColor
        # est vrai : sans cette ligne, il reste gris clair sur un fond sombre.
        $b.UseVisualStyleBackColor = $false
        $b.BackColor = [System.Drawing.Color]::FromArgb(58, 56, 51)
        $b.ForeColor = [System.Drawing.Color]::FromArgb(236, 234, 229)
        $f.Controls.Add($b)
    }

    $resultat = @{ Action = 'annule'; EmpreinteConnue = [string]$Config.EchecsEmpreinte
                   AdresseConnue = [string]$Config.EchecsAdresse }

    $bTester.Add_Click({
        $etat.ForeColor = [System.Drawing.Color]::FromArgb(150, 148, 143)
        $etat.Text = 'Contact en cours...'
        $f.Refresh()
        Write-EtatConnexion $etat (Invoke-EssaiConnexion $tNom.Text $tAdresse.Text $tCode.Text $resultat)
    }.GetNewClosure())

    $bOk.Add_Click({
        # Enregistrer ESSAIE d'abord : des réglages qui ne fonctionnent pas
        # feraient apparaître la flèche pour rien, et l'erreur ne se verrait
        # qu'au premier clic dessus.
        $etat.ForeColor = [System.Drawing.Color]::FromArgb(150, 148, 143)
        $etat.Text = 'Verification avant enregistrement...'
        $f.Refresh()
        $r = Invoke-EssaiConnexion $tNom.Text $tAdresse.Text $tCode.Text $resultat
        Write-EtatConnexion $etat $r
        if (-not $r.Ok) { return }

        $resultat.Action    = 'enregistre'
        $resultat.Nom       = $tNom.Text.Trim()
        $resultat.Adresse   = $tAdresse.Text.Trim()
        $resultat.Code      = $tCode.Text
        $resultat.Empreinte = $resultat.EmpreinteConnue
        $f.Close()
    }.GetNewClosure())

    $bOublier.Add_Click({ $resultat.Action = 'oublie'; $f.Close() }.GetNewClosure())

    [void]$f.ShowDialog()
    $f.Dispose()
    return $resultat
}

# ---------------------------------------------------------------------------
#  Dialogue avec le serveur — toujours dans un fil séparé
#
#  Une seule tâche à la fois, dans une file. Les coups passent avant les
#  interrogations d'état : sans cette priorité, un sondage arrivé entre-temps
#  ramènerait la position d'AVANT le coup qu'on vient de jouer et l'effacerait
#  de l'écran.
# ---------------------------------------------------------------------------

$script:echecsRunspace = $null
$script:echecsPs       = $null
$script:echecsHandle   = $null
$script:echecsTacheEnCours = $null
$script:echecsFile     = New-Object 'System.Collections.Generic.List[hashtable]'

$script:echecsEtat     = $null      # dernier état reçu du serveur
$script:echecsNom      = ''
$script:echecsMonTour  = $false
$script:echecsErreur   = ''
$script:echecsPartie   = $null
# Coup joue localement mais dont on ignore s'il est arrive au serveur.
$script:echecsCoupEnAttente = $null

function Initialize-EchecsRunspace {
    param([string]$Dossier)
    if ($script:echecsRunspace) { return }
    $script:echecsRunspace = [runspacefactory]::CreateRunspace()
    $script:echecsRunspace.Open()
    $init = [powershell]::Create()
    $init.Runspace = $script:echecsRunspace
    # Seul le client est chargé ici : parler au serveur ne demande pas les
    # règles du jeu, qui restent du côté de l'interface.
    [void]$init.AddScript({ param($d) . (Join-Path $d 'echecs\Client-Serveur.ps1') }).AddArgument($Dossier)
    $init.Invoke() | Out-Null
    $init.Dispose()
}

function Add-TacheEchecs {
    param([string]$Route, [hashtable]$Corps = @{}, [bool]$Prioritaire = $false)
    $t = @{ Route = $Route; Corps = $Corps }
    if ($Prioritaire) { $script:echecsFile.Insert(0, $t) } else { $script:echecsFile.Add($t) }
}

function Start-EchecsPoll {
    # Met une interrogation d'état en file, sauf s'il y a déjà à faire.
    param($Config, [string]$Dossier)
    if (-not (Test-EchecsConfigure $Config)) { return }
    if ($script:echecsFile.Count -gt 0) { return }
    Add-TacheEchecs '/etat'
    Start-TacheSuivante $Config $Dossier
}

function Start-TacheSuivante {
    param($Config, [string]$Dossier)
    if ($script:echecsHandle) { return }
    if ($script:echecsFile.Count -eq 0) { return }
    if (-not (Test-EchecsConfigure $Config)) { return }
    Initialize-EchecsRunspace $Dossier
    $script:echecsNom = [string]$Config.EchecsNom

    $tache = $script:echecsFile[0]
    $script:echecsFile.RemoveAt(0)
    $script:echecsTacheEnCours = $tache

    $ps = [powershell]::Create()
    $ps.Runspace = $script:echecsRunspace
    [void]$ps.AddScript({
        param($adresse, $code, $nom, $empreinte, $route, $corps)
        # Pas de -AutoriserPremiere ici : un échange de fond ne doit JAMAIS
        # accepter un certificat inconnu. Seul le dialogue de connexion, où
        # quelqu'un est devant l'écran, en a le droit.
        Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur $nom `
                             -Route $route -Corps $corps -Delai 10 -Empreinte $empreinte
    })
    [void]$ps.AddArgument([string]$Config.EchecsAdresse)
    [void]$ps.AddArgument([string]$Config.EchecsCode)
    [void]$ps.AddArgument([string]$Config.EchecsNom)
    [void]$ps.AddArgument([string]$Config.EchecsEmpreinte)
    [void]$ps.AddArgument([string]$tache.Route)
    [void]$ps.AddArgument([hashtable]$tache.Corps)

    $script:echecsPs     = $ps
    $script:echecsHandle = $ps.BeginInvoke()
}

function Complete-EchecsPoll {
    # Ramasse le résultat quand il est prêt. Renvoie $true si l'affichage doit
    # être redessiné.
    param($Config, [string]$Dossier)
    if (-not $script:echecsHandle) {
        Start-TacheSuivante $Config $Dossier
        return $false
    }
    if (-not $script:echecsHandle.IsCompleted) { return $false }

    $tache = $script:echecsTacheEnCours
    $avantTour = $script:echecsMonTour
    $redessiner = $false

    try {
        $res = $script:echecsPs.EndInvoke($script:echecsHandle)
        if ($res -and $res[0]) {
            $r = $res[0]
            if ($r.Ok -and $r.Etat) {
                $script:echecsEtat   = $r.Etat
                $script:echecsErreur = ''
                if ($tache -and $tache.Route -eq '/coup') { $script:echecsCoupEnAttente = $null }
                $redessiner = (Sync-PartieBarre $Config)
                # Un coup reste en attente : l'etat qu'on vient de lire dit
                # s'il est arrive ou non. Sync-PartieBarre a deja tranche.
                if ($script:echecsCoupEnAttente -and $tache -and $tache.Route -eq '/etat') {
                    $enAttente = $script:echecsCoupEnAttente
                    $nb = 0
                    if ($r.Etat.coups) { $nb = @($r.Etat.coups).Count }
                    if ($nb -gt [int]$enAttente.Corps.apresVersion) {
                        $script:echecsCoupEnAttente = $null    # il etait bien passe
                    } else {
                        # Remis en tete TEL QUEL : recreer la tache perdrait le
                        # compteur d'essais et on reessaierait sans fin.
                        $script:echecsFile.Insert(0, $enAttente)
                    }
                }
            } else {
                $script:echecsErreur = [string]$r.Erreur
                $redessiner = $true

                # AUCUNE boîte de dialogue ici. Une coupure réseau se répète
                # toutes les cinq secondes : la première version en empilait
                # une par échec, jusqu'à une trentaine à l'écran. Le problème
                # se signale par la couleur de la flèche, et le coup est
                # simplement RÉESSAYÉ.
                if ($r.Etat) {
                    $script:echecsEtat = $r.Etat
                    [void](Sync-PartieBarre $Config)
                }

                if ($tache -and $tache.Route -eq '/coup') {
                    # CodeHttp à 0 = on n'a pas eu de réponse du tout (délai
                    # dépassé, coupure). Le coup est peut-être passé, peut-être
                    # pas : on redemande l'état, et Sync-PartieBarre décidera
                    # s'il faut le renvoyer. Un code 4xx, lui, est un refus
                    # ferme : inutile d'insister.
                    if ([int]$r.CodeHttp -eq 0 -and $tache.Essais -lt 4) {
                        $tache.Essais = [int]$tache.Essais + 1
                        $script:echecsCoupEnAttente = $tache
                        Add-TacheEchecs '/etat' @{} $true
                    } else {
                        # On renonce. La partie locale contient peut-etre un
                        # coup fantome que le serveur n'a jamais recu : on la
                        # jette pour qu'elle soit reconstruite depuis le
                        # serveur, plutot que de laisser un echiquier faux.
                        $script:echecsCoupEnAttente = $null
                        Reset-PartieBarre
                        Add-TacheEchecs '/etat' @{} $true
                    }
                }
            }
        }
    } catch {
        $script:echecsErreur = $_.Exception.Message
    } finally {
        try { $script:echecsPs.Dispose() } catch { }
        $script:echecsPs = $null
        $script:echecsHandle = $null
        $script:echecsTacheEnCours = $null
    }

    Start-TacheSuivante $Config $Dossier
    return ($redessiner -or ($avantTour -ne $script:echecsMonTour))
}

function Sync-PartieBarre {
    # Applique le dernier état reçu à la partie affichée. Renvoie $true si
    # quelque chose a bougé.
    param($Config)
    if (-not $script:echecsEtat) { return $false }
    $nom = [string]$Config.EchecsNom

    $script:echecsMonTour = Test-MonTourDepuisEtat $script:echecsEtat $nom

    $nbServeur = 0
    if ($script:echecsEtat.coups) { $nbServeur = @($script:echecsEtat.coups).Count }

    if (-not $script:echecsPartie) {
        $script:echecsPartie = New-Partie -MonNom $nom
        $s = Sync-PartieDepuisServeur $script:echecsPartie $script:echecsEtat $nom
        if (-not $s.Ok) { $script:echecsErreur = $s.Erreur; $script:echecsPartie = $null; return $false }
        $script:plateauRetourne = ($script:echecsPartie.MaCouleur -eq 'b')
        return $true
    }

    # Rien de neuf : on ne touche à rien. Important, car un coup joué ici et
    # pas encore confirmé rendrait la partie locale plus longue que celle du
    # serveur — la resynchroniser l'effacerait de l'écran.
    if ($nbServeur -eq $script:echecsPartie.Coups.Count) { return $false }
    if ($nbServeur -lt $script:echecsPartie.Coups.Count) { return $false }

    $s = Sync-PartieDepuisServeur $script:echecsPartie $script:echecsEtat $nom
    if (-not $s.Ok) { $script:echecsErreur = $s.Erreur; return $false }
    $script:plateauRetourne = ($script:echecsPartie.MaCouleur -eq 'b')
    $script:plateauSelection = -1
    $script:plateauCibles = @()
    $script:plateauPromo = $null
    return $true
}

function Test-MonTourDepuisEtat {
    # Pas besoin du moteur : les blancs jouent quand le nombre de coups joués
    # est pair. C'est vrai de toute partie d'échecs.
    param($Etat, [string]$MonNom)
    if (-not $Etat -or $Etat.termine) { return $false }
    $couleur = $null
    if ($Etat.joueurs.w -eq $MonNom) { $couleur = 'w' }
    elseif ($Etat.joueurs.b -eq $MonNom) { $couleur = 'b' }
    if (-not $couleur) { return $false }
    $nb = 0
    if ($Etat.coups) { $nb = @($Etat.coups).Count }
    return ($couleur -eq $(if ($nb % 2 -eq 0) { 'w' } else { 'b' }))
}

# ---------------------------------------------------------------------------
#  Le plateau : ouverture, clics, coups
# ---------------------------------------------------------------------------

function Switch-PlateauEchecs {
    # Déplie ou replie. Instantané : on n'attend rien du réseau, on affiche la
    # dernière position connue et on demande la suite en arrière-plan.
    param($Config, [string]$Dossier)
    $script:echecsOuvert = -not $script:echecsOuvert
    $script:plateauSelection = -1
    $script:plateauCibles = @()
    $script:plateauPromo = $null
    if ($script:echecsOuvert) {
        [void](Sync-PartieBarre $Config)
        Add-TacheEchecs '/etat' @{} $true
        Start-TacheSuivante $Config $Dossier
    }
}

function Invoke-ClicPlateau {
    # Un clic sur le damier. Renvoie $true s'il faut redessiner.
    param($Geo, [int]$PX, [int]$PY, $Config, [string]$Dossier)

    $partie = $script:echecsPartie
    if (-not $partie) { return $false }

    # Un choix de promotion ouvert capte le clic, ou se referme.
    if ($script:plateauPromo) {
        foreach ($choix in $script:plateauPromo.Cases) {
            if ($choix.Rect.Contains($PX, $PY)) {
                $coup = $choix.Coup
                $script:plateauPromo = $null
                Invoke-CoupBarre $coup $Config $Dossier
                return $true
            }
        }
        $script:plateauPromo = $null
        return $true
    }

    $case = Get-CaseDepuisPointBarre $Geo $PX $PY
    if ($case -lt 0 -or -not (Test-MonTour $partie)) {
        $script:plateauSelection = -1; $script:plateauCibles = @()
        return $true
    }

    # Deuxième clic sur une case pointée : on joue.
    if ($script:plateauSelection -ge 0 -and ($script:plateauCibles -contains $case)) {
        $candidats = @(Get-CoupVers $partie $script:plateauSelection $case)
        $script:plateauSelection = -1; $script:plateauCibles = @()
        if ($candidats.Count -eq 1) {
            Invoke-CoupBarre $candidats[0] $Config $Dossier
        } elseif ($candidats.Count -gt 1) {
            # Plusieurs coups pour un même trajet : c'est une promotion.
            $script:plateauPromo = @{ Arrivee = $case; Candidats = $candidats; Cases = @() }
        }
        return $true
    }

    # Sinon : sélection d'une de ses propres pièces.
    $piece = $partie.Pos.B[$case]
    if ($piece -ne ' ' -and ([char]::IsUpper($piece) -eq ($partie.MaCouleur -eq 'w'))) {
        $script:plateauSelection = $case
        $script:plateauCibles = @(Get-CoupsDepuis $partie $case)
    } else {
        $script:plateauSelection = -1
        $script:plateauCibles = @()
    }
    return $true
}

function Invoke-CoupBarre {
    # Le coup est appliqué LOCALEMENT tout de suite — c'est ce que le joueur
    # voit — puis mis en file pour partir dans le fil de fond. Aucune attente
    # réseau sur le fil de l'interface.
    param([int]$Coup, $Config, [string]$Dossier)

    $partie = $script:echecsPartie
    $avant = $partie.Coups.Count
    if (-not (Add-CoupPartie $partie $Coup)) { return }
    $uci = $partie.Coups[$partie.Coups.Count - 1]

    $corps = @{ coup = $uci; apresVersion = $avant }
    if ($partie.Resultat) { $corps['resultat'] = $partie.Resultat }
    Add-TacheEchecs '/coup' $corps $true
    Start-TacheSuivante $Config $Dossier

    $script:echecsMonTour = $false
}

function Show-MenuPlateau {
    # Tout ce qui aurait demandé des boutons vit ici : le plateau reste nu.
    param($Panneau, $Point, $Config, [string]$Dossier)

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $partie = $script:echecsPartie

    $mRetourner = $menu.Items.Add('Retourner le plateau')
    $mRetourner.Add_Click({ Switch-OrientationPlateau }.GetNewClosure())

    $mNouvelle = $menu.Items.Add('Nouvelle partie')
    $mNouvelle.Enabled = ($partie -and (Test-PartieTerminee $partie))
    $mNouvelle.Add_Click({
        Add-TacheEchecs '/nouvelle' @{} $true
        Start-TacheSuivante $Config $Dossier
        Reset-PartieBarre
    }.GetNewClosure())

    $mAbandon = $menu.Items.Add('Abandonner')
    $mAbandon.Enabled = ($partie -and -not (Test-PartieTerminee $partie))
    $mAbandon.Add_Click({
        $rep = [System.Windows.Forms.MessageBox]::Show(
            'Abandonner cette partie ? Le point va a ton adversaire.',
            'Echecs', 'YesNo', 'Question')
        if ($rep -eq 'Yes') {
            Add-TacheEchecs '/abandon' @{} $true
            Start-TacheSuivante $Config $Dossier
        }
    }.GetNewClosure())

    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $mConnexion = $menu.Items.Add('Connexion...')
    $mConnexion.Add_Click({ Invoke-ConnexionEchecs }.GetNewClosure())

    $menu.Show($Panneau, $Point)
}

function Switch-OrientationPlateau {
    $script:plateauRetourne = -not $script:plateauRetourne
    $script:plateauSelection = -1
    $script:plateauCibles = @()
}

function Reset-PartieBarre {
    # La partie locale est oubliee : la reponse du serveur la reconstruira.
    $script:echecsPartie = $null
    $script:plateauSelection = -1
    $script:plateauCibles = @()
    $script:plateauPromo = $null
}
