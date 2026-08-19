# ============================================================================
#  Integration-TokenBar.ps1 — l'easter egg.
#
#  Tant qu'aucun serveur n'est enregistré, ce fichier ne fait strictement
#  rien de visible : la barre est identique à ce qu'elle a toujours été. Le
#  jeu ne se révèle qu'après un geste caché — Ctrl + Maj + double-clic sur le
#  cœur — qui ouvre le seul endroit où saisir une adresse de serveur.
#
#  Une fois un serveur enregistré, un petit pion en pixels s'affiche sous le
#  pourcentage. Un clic ouvre la partie ; une pastille rouge apparaît dessus
#  quand c'est à toi de jouer.
#
#  RAPPEL DE PORTÉE (voir Fenetre-Echecs.ps1) : dans un bloc créé avec
#  .GetNewClosure(), toute variable $script: vaut $null. Les fermetures de ce
#  fichier ne manipulent donc que des variables locales et des appels de
#  fonction — jamais $script:quelquechose.
# ============================================================================

# Chargé ici, au niveau du script, et non à la demande dans une fonction :
# un « . fichier.ps1 » exécuté dans une fonction définit ses fonctions dans
# la portée de cette fonction, qui disparaît au retour. Le chargement paraît
# réussir et tout casse au premier appel.
. (Join-Path $PSScriptRoot 'Moteur-Echecs.ps1')
. (Join-Path $PSScriptRoot 'Rendu-Echiquier.ps1')
. (Join-Path $PSScriptRoot 'Partie-Echecs.ps1')
. (Join-Path $PSScriptRoot 'Client-Serveur.ps1')
. (Join-Path $PSScriptRoot 'Fenetre-Echecs.ps1')

# ---------------------------------------------------------------------------
#  Le pion en pixels — même famille graphique que le cœur de la barre.
#  0 = rien, 1 = contour sombre, 2 = corps clair.
# ---------------------------------------------------------------------------

$script:PION_PIXEL = @(
    '000111000',
    '001222100',
    '001222100',
    '000121000',
    '001222100',
    '012222210',
    '122222221',
    '111111111')

function Write-PixelPion {
    # Dessiné sans lissage, comme le cœur : le fond de la barre est une
    # couleur de transparence, et un bord adouci y laisserait un halo gris.
    param($G, [single]$OX, [single]$OY, [single]$Cell, [bool]$Pastille)

    $ancien = $G.SmoothingMode
    $G.SmoothingMode = 'None'
    $sombre = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(14, 14, 16))
    $clair  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(238, 238, 238))

    for ($r = 0; $r -lt $script:PION_PIXEL.Count; $r++) {
        $ligne = $script:PION_PIXEL[$r]
        for ($c = 0; $c -lt $ligne.Length; $c++) {
            $ch = $ligne[$c]
            if ($ch -eq '0') { continue }
            $b = $(if ($ch -eq '1') { $sombre } else { $clair })
            $G.FillRectangle($b, ($OX + $c * $Cell), ($OY + $r * $Cell), $Cell, $Cell)
        }
    }

    if ($Pastille) {
        $rouge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 45, 50))
        $G.FillRectangle($sombre, ($OX + 6 * $Cell), $OY, (3 * $Cell), (3 * $Cell))
        $G.FillRectangle($rouge,  ($OX + 6.5 * $Cell), ($OY + 0.5 * $Cell), (2 * $Cell), (2 * $Cell))
        $rouge.Dispose()
    }

    $sombre.Dispose(); $clair.Dispose()
    $G.SmoothingMode = $ancien
}

# ---------------------------------------------------------------------------
#  Configuration
# ---------------------------------------------------------------------------

function Test-EchecsConfigure {
    param($Config)
    return ([string]$Config.EchecsAdresse -ne '' -and
            [string]$Config.EchecsCode    -ne '' -and
            [string]$Config.EchecsNom     -ne '')
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

function Invoke-EssaiConnexion {
    # Un essai de connexion depuis le dialogue. $Etat porte l'empreinte déjà
    # connue et se met à jour avec celle qu'on vient de voir.
    #
    # La règle d'épinglage : on n'accepte un certificat inconnu QUE si aucune
    # empreinte n'est encore enregistrée pour cette adresse. Changer d'adresse
    # remet donc le compteur à zéro, mais un certificat qui change sur la même
    # adresse est refusé — c'est tout l'intérêt.
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
        $Etat.Premiere        = (-not $empreinte)
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

function Show-DialogueConnexionEchecs {
    # La seule porte d'entrée. Trois champs, un bouton pour éprouver la
    # connexion AVANT d'enregistrer, et un bouton pour tout effacer — qui fait
    # disparaître le jeu comme s'il n'avait jamais existé.
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
    $i = 0
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
        $i++
    }

    $resultat = @{ Action = 'annule'; EmpreinteConnue = [string]$Config.EchecsEmpreinte
                   AdresseConnue = [string]$Config.EchecsAdresse }

    # .GetNewClosure() est indispensable ici : sans lui, ces blocs ne verraient
    # aucune des variables locales de cette fonction ($tNom, $f, $resultat...).
    # En revanche ils ne doivent contenir QUE des appels de fonction et des
    # locales — jamais de $script:, qui y vaudrait $null.
    $bTester.Add_Click({
        $etat.ForeColor = [System.Drawing.Color]::FromArgb(150, 148, 143)
        $etat.Text = 'Contact en cours...'
        $f.Refresh()
        $r = Invoke-EssaiConnexion $tNom.Text $tAdresse.Text $tCode.Text $resultat
        Write-EtatConnexion $etat $r
    }.GetNewClosure())

    $bOk.Add_Click({
        # Enregistrer ESSAIE d'abord. Enregistrer des reglages qui ne
        # fonctionnent pas ferait apparaitre le pion pour rien, et l'erreur ne
        # se verrait qu'au premier clic dessus.
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
#  Interrogation du serveur, sans jamais bloquer la barre
# ---------------------------------------------------------------------------

$script:echecsRunspace = $null
$script:echecsPs       = $null
$script:echecsHandle   = $null
$script:echecsEtat     = $null      # dernier état reçu du serveur
$script:echecsNom      = ''
$script:echecsMonTour  = $false
$script:echecsErreur   = ''

function Initialize-EchecsRunspace {
    param([string]$Dossier)
    if ($script:echecsRunspace) { return }
    $script:echecsRunspace = [runspacefactory]::CreateRunspace()
    $script:echecsRunspace.Open()
    $init = [powershell]::Create()
    $init.Runspace = $script:echecsRunspace
    # Seul le client est chargé ici : savoir « est-ce mon tour ? » ne demande
    # pas les règles du jeu, seulement la parité du nombre de coups.
    [void]$init.AddScript({ param($d) . (Join-Path $d 'echecs\Client-Serveur.ps1') }).AddArgument($Dossier)
    $init.Invoke() | Out-Null
    $init.Dispose()
}

function Start-EchecsPoll {
    param($Config, [string]$Dossier)
    if (-not (Test-EchecsConfigure $Config)) { return }
    if ($script:echecsHandle) { return }
    Initialize-EchecsRunspace $Dossier
    $script:echecsNom = [string]$Config.EchecsNom

    $ps = [powershell]::Create()
    $ps.Runspace = $script:echecsRunspace
    [void]$ps.AddScript({
        param($adresse, $code, $nom, $empreinte)
        # Pas de -AutoriserPremiere ici : un sondage de fond ne doit JAMAIS
        # accepter un certificat inconnu. Seul le dialogue de connexion, où
        # quelqu'un est devant l'écran, a ce droit.
        Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur $nom `
                             -Route '/etat' -Delai 7 -Empreinte $empreinte
    })
    [void]$ps.AddArgument([string]$Config.EchecsAdresse)
    [void]$ps.AddArgument([string]$Config.EchecsCode)
    [void]$ps.AddArgument([string]$Config.EchecsNom)
    [void]$ps.AddArgument([string]$Config.EchecsEmpreinte)

    $script:echecsPs     = $ps
    $script:echecsHandle = $ps.BeginInvoke()
}

function Complete-EchecsPoll {
    # Renvoie $true si l'affichage doit changer.
    if (-not $script:echecsHandle -or -not $script:echecsHandle.IsCompleted) { return $false }

    $avantTour = $script:echecsMonTour
    $avantNb = -1
    if ($script:echecsEtat -and $script:echecsEtat.coups) { $avantNb = @($script:echecsEtat.coups).Count }

    try {
        $res = $script:echecsPs.EndInvoke($script:echecsHandle)
        if ($res -and $res[0]) {
            $r = $res[0]
            if ($r.Ok -and $r.Etat) {
                $script:echecsEtat    = $r.Etat
                $script:echecsErreur  = ''
                $script:echecsMonTour = Test-MonTourDepuisEtat $r.Etat $script:echecsNom
            } else {
                $script:echecsErreur  = [string]$r.Erreur
                $script:echecsMonTour = $false
            }
        }
    } catch {
        $script:echecsErreur = $_.Exception.Message
    } finally {
        try { $script:echecsPs.Dispose() } catch { }
        $script:echecsPs = $null
        $script:echecsHandle = $null
    }

    $apresNb = -1
    if ($script:echecsEtat -and $script:echecsEtat.coups) { $apresNb = @($script:echecsEtat.coups).Count }
    return (($avantTour -ne $script:echecsMonTour) -or ($avantNb -ne $apresNb))
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
#  La fenêtre de jeu
# ---------------------------------------------------------------------------

$script:echecsFenetre = $null
$script:echecsPartie  = $null

function Update-AffichageEchecs {
    # Appelée depuis des fermetures, qui ne peuvent pas lire $script: elles-mêmes.
    if ($script:echecsFenetre -and -not $script:echecsFenetre.Form.IsDisposed) {
        $script:echecsFenetre.Panneau.Invalidate()
    }
}

function Open-FenetreEchecs {
    param($Config, [string]$Dossier)

    # Déjà ouverte : on la ramène devant plutôt que d'en ouvrir une seconde.
    if ($script:echecsFenetre -and -not $script:echecsFenetre.Form.IsDisposed) {
        $script:echecsFenetre.Form.Activate()
        return
    }

    $nom       = [string]$Config.EchecsNom
    $adresse   = [string]$Config.EchecsAdresse
    $code      = [string]$Config.EchecsCode
    $empreinte = [string]$Config.EchecsEmpreinte

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur $nom -Route '/etat' `
                              -Delai 8 -Empreinte $empreinte
    if (-not $r.Ok) {
        [void][System.Windows.Forms.MessageBox]::Show(
            ("Le serveur ne repond pas :`r`n`r`n" + $r.Erreur), 'Echecs', 'OK', 'Warning')
        return
    }

    # Si une place est encore libre, on se présente. (Sans objet quand le
    # serveur a une liste blanche : les deux places y sont déjà attribuées.)
    if ($r.Etat.joueurs.w -ne $nom -and $r.Etat.joueurs.b -ne $nom) {
        $j = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur $nom `
                                  -Route '/rejoindre' -Delai 8 -Empreinte $empreinte
        if ($j.Ok) { $r = $j }
    }

    $partie = New-Partie -MonNom $nom
    $s = Sync-PartieDepuisServeur $partie $r.Etat $nom
    if (-not $s.Ok) {
        [void][System.Windows.Forms.MessageBox]::Show($s.Erreur, 'Echecs', 'OK', 'Warning')
        return
    }
    $script:echecsPartie = $partie

    $envoyer = {
        param($P, $Coup)
        # Le coup vient d'être appliqué localement : la version connue AVANT
        # ce coup est donc le nombre de coups moins celui-ci.
        $avant = $P.Coups.Count - 1
        $dernier = $P.Coups[$P.Coups.Count - 1]
        $rep = Send-CoupServeur -Partie $P -Adresse $adresse -Code $code -MonNom $nom `
                                -CoupUci $dernier -AvantVersion $avant -Empreinte $empreinte
        if (-not $rep.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show(
                ("Le serveur a refuse ce coup :`r`n`r`n" + $rep.Erreur +
                 "`r`n`r`nLa partie a ete remise a l'etat du serveur."),
                'Echecs', 'OK', 'Warning')
        }
        Update-AffichageEchecs
    }.GetNewClosure()

    $script:echecsFenetre = Show-FenetreEchecs -Partie $partie -SurCoup $envoyer `
                                -CheminIcone (Join-Path $Dossier 'TokenBar.ico')
}

function Sync-FenetreEchecsOuverte {
    # Appelée quand un sondage rapporte du neuf : si la fenêtre est ouverte,
    # elle doit voir le coup de l'adversaire sans qu'on la rouvre.
    param($Config)
    if (-not $script:echecsFenetre -or $script:echecsFenetre.Form.IsDisposed) { return }
    if (-not $script:echecsEtat -or -not $script:echecsPartie) { return }

    $nb = 0
    if ($script:echecsEtat.coups) { $nb = @($script:echecsEtat.coups).Count }
    if ($nb -eq $script:echecsPartie.Coups.Count) { return }   # rien de neuf

    $s = Sync-PartieDepuisServeur $script:echecsPartie $script:echecsEtat ([string]$Config.EchecsNom)
    if ($s.Ok) { Update-AffichageEchecs }
}
