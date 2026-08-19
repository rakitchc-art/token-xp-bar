# Test-Serveur.ps1 -- eprouve le serveur et le client de bout en bout.
#
# Deux joueurs simules (Dova et Nisse) jouent une vraie partie a travers un
# serveur Node lance pour l'occasion sur un port libre, avec un fichier d'etat
# jetable. Rien de la machine ni du VPS n'est touche.
#
# Chaque controle est ecrit pour POUVOIR echouer : on tente le mauvais code,
# le coup hors tour, le coup double, la position perimee, et une liste de
# coups sabotee a la main dans le fichier d'etat.

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Client-Serveur.ps1')

$script:reussis = 0
$script:rates   = 0

function Assert-Vrai {
    param([string]$Titre, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host ("  OK   " + $Titre) -ForegroundColor Green
        $script:reussis++
    } else {
        Write-Host ("  RATE " + $Titre + $(if ($Detail) { "  -> " + $Detail } else { '' })) -ForegroundColor Red
        $script:rates++
    }
}

# --- port libre -----------------------------------------------------------
$ecouteur = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
$ecouteur.Start()
$port = $ecouteur.LocalEndpoint.Port
$ecouteur.Stop()

$etatFichier = Join-Path $env:TEMP ('echecs-test-' + $port + '.json')
if (Test-Path $etatFichier) { Remove-Item $etatFichier -Force }
$code = 'code-de-test-1234'
# http:// explicite : cette suite eprouve la logique de partie, pas le
# chiffrement (qui a sa propre suite, Test-Epinglage.ps1). Sans le prefixe,
# le client passerait en https et ne trouverait personne.
$adresse = 'http://127.0.0.1:' + $port

Write-Host ("Serveur de test sur le port " + $port)
Write-Host ("Etat jetable : " + $etatFichier)

$env:ECHECS_CODE = $code
$env:ECHECS_PORT = [string]$port
$env:ECHECS_HOTE = '127.0.0.1'
$env:ECHECS_ETAT = $etatFichier

$proc = Start-Process -FilePath 'node' `
    -ArgumentList (Join-Path $racine 'serveur\echecs-serveur.js') `
    -PassThru -WindowStyle Hidden

# Attente active de l'ecoute : un Start-Sleep fixe echouerait au hasard sur
# une machine chargee, et reussirait a tort sur une machine rapide.
$pret = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $port)
        $c.Close()
        $pret = $true
        break
    } catch { Start-Sleep -Milliseconds 150 }
}
Assert-Vrai 'le serveur ecoute' $pret

try {
    if (-not $pret) { throw 'serveur non demarre' }

    Write-Host ''
    Write-Host '--- Authentification ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code 'mauvais-code' -Joueur 'Dova' -Route '/etat'
    Assert-Vrai 'un mauvais code est refuse' ((-not $r.Ok) -and $r.CodeHttp -eq 401) ("recu " + $r.CodeHttp)

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova<script>' -Route '/etat'
    Assert-Vrai 'un nom de joueur invalide est refuse' ((-not $r.Ok) -and $r.CodeHttp -eq 400) ("recu " + $r.CodeHttp)

    Write-Host ''
    Write-Host '--- Mise en place ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat'
    Assert-Vrai 'Dova cree la partie et prend les blancs' ($r.Ok -and $r.Etat.joueurs.w -eq 'Dova')

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Nisse' -Route '/rejoindre'
    Assert-Vrai 'Nisse rejoint et prend les noirs' ($r.Ok -and $r.Etat.joueurs.b -eq 'Nisse')

    $pDova  = New-Partie -MonNom 'Dova'  -NomAdversaire 'Nisse'
    $pNisse = New-Partie -MonNom 'Nisse' -NomAdversaire 'Dova'
    $s = Sync-PartieDepuisServeur $pDova $r.Etat 'Dova'
    Assert-Vrai 'Dova se synchronise' $s.Ok $s.Erreur
    Assert-Vrai 'Dova joue bien les blancs' ($pDova.MaCouleur -eq 'w')

    Write-Host ''
    Write-Host '--- Arbitrage du tour ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Nisse' -Route '/coup' `
                              -Corps @{ coup = 'e7e5'; apresVersion = 0 }
    Assert-Vrai 'Nisse ne peut pas jouer en premier' `
                ((-not $r.Ok) -and $r.CodeHttp -eq 409 -and $r.Erreur -like '*ton tour*') `
                ("recu " + $r.CodeHttp + ' ' + $r.Erreur)

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/coup' `
                              -Corps @{ coup = 'zz9zz9' }
    Assert-Vrai 'un coup malforme est refuse' ((-not $r.Ok) -and $r.CodeHttp -eq 400) ("recu " + $r.CodeHttp)

    Write-Host ''
    Write-Host '--- La partie (mat du sot : 1.f3 e5 2.g4 Dh4#) ---'
    # Chaque camp joue depuis SA propre partie locale, comme dans la vraie vie.
    $sequence = @(
        @{ Qui = 'Dova';  P = $pDova;  Uci = 'f2f3' },
        @{ Qui = 'Nisse'; P = $pNisse; Uci = 'e7e5' },
        @{ Qui = 'Dova';  P = $pDova;  Uci = 'g2g4' },
        @{ Qui = 'Nisse'; P = $pNisse; Uci = 'd8h4' }
    )

    foreach ($etape in $sequence) {
        $partie = $etape.P

        # 1. se remettre a jour
        $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur $etape.Qui -Route '/etat'
        [void](Sync-PartieDepuisServeur $partie $r.Etat $etape.Qui)

        # 2. jouer localement, a travers le moteur
        $avant = $partie.Coups.Count
        $coup = ConvertFrom-Uci $partie.Pos $etape.Uci
        Assert-Vrai ($etape.Qui + ' : ' + $etape.Uci + ' est un coup legal') ($coup -ge 0)
        [void](Add-CoupPartie $partie $coup)

        # 3. l'envoyer
        $env2 = Send-CoupServeur -Partie $partie -Adresse $adresse -Code $code `
                                 -MonNom $etape.Qui -CoupUci $etape.Uci -AvantVersion $avant
        Assert-Vrai ($etape.Qui + ' : le serveur accepte ' + $etape.Uci) $env2.Ok $env2.Erreur
    }

    Assert-Vrai 'la partie est un mat' ($pNisse.Etat -eq 'mat') ("etat = " + $pNisse.Etat)
    Assert-Vrai 'les noirs gagnent' ($pNisse.Resultat -eq '0-1') ("resultat = " + $pNisse.Resultat)
    Assert-Vrai 'notation francaise' ($pNisse.San[3] -eq 'Dh4#') ("obtenu " + $pNisse.San[3])

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat'
    Assert-Vrai 'le serveur enregistre la fin' ($r.Etat.termine -eq $true)
    Assert-Vrai 'le score de Nisse passe a 1' ([double]$r.Etat.scores.Nisse -eq 1.0) ("recu " + $r.Etat.scores.Nisse)
    Assert-Vrai 'le score de Dova reste a 0' ([double]$r.Etat.scores.Dova -eq 0.0) ("recu " + $r.Etat.scores.Dova)

    $s = Sync-PartieDepuisServeur $pDova $r.Etat 'Dova'
    Assert-Vrai 'Dova voit le score cote a cote' (($pDova.MesPoints -eq 0.0) -and ($pDova.SesPoints -eq 1.0)) `
                ("mes=" + $pDova.MesPoints + " ses=" + $pDova.SesPoints)

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/coup' `
                              -Corps @{ coup = 'a2a3' }
    Assert-Vrai 'on ne joue plus apres le mat' `
                ((-not $r.Ok) -and $r.CodeHttp -eq 409 -and $r.Erreur -like '*terminee*') `
                ("recu " + $r.CodeHttp + ' ' + $r.Erreur)

    Write-Host ''
    Write-Host '--- Partie suivante : les couleurs s echangent ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/nouvelle'
    Assert-Vrai 'nouvelle partie acceptee' $r.Ok $r.Erreur
    Assert-Vrai 'Nisse passe aux blancs' ($r.Etat.joueurs.w -eq 'Nisse') ("blanc = " + $r.Etat.joueurs.w)
    Assert-Vrai 'Dova passe aux noirs'   ($r.Etat.joueurs.b -eq 'Dova')
    Assert-Vrai 'les scores sont conserves' ([double]$r.Etat.scores.Nisse -eq 1.0)

    Write-Host ''
    Write-Host '--- Position perimee ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Nisse' -Route '/coup' `
                              -Corps @{ coup = 'e2e4'; apresVersion = 0 }
    Assert-Vrai 'Nisse ouvre la nouvelle partie' $r.Ok $r.Erreur
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/coup' `
                              -Corps @{ coup = 'e7e5'; apresVersion = 0 }
    Assert-Vrai 'un coup joue sur une position perimee est refuse' `
                ((-not $r.Ok) -and $r.Erreur -like '*perimee*') ("recu " + $r.Erreur)

    Write-Host ''
    Write-Host '--- Sabotage : une liste de coups impossible ---'
    # Le levier d'echec : on injecte a la main un coup illegal dans le fichier
    # d'etat, exactement ce qu'un serveur corrompu ou un client bricole
    # produirait. Le client doit tout refuser plutot que d'afficher un
    # echiquier faux.
    $obj = [System.IO.File]::ReadAllText($etatFichier) | ConvertFrom-Json
    # a1h8 : une tour qui traverse tout l'echiquier en diagonale.
    $obj.coups = @(@($obj.coups) + 'a1h8')
    # Sans BOM : Node refuse un JSON qui commence par EF BB BF.
    $sansBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($etatFichier, ($obj | ConvertTo-Json -Depth 6), $sansBom)

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat'
    Assert-Vrai 'le serveur relit bien le fichier sabote' ($r.Ok -and (@($r.Etat.coups).Count -eq 2)) `
                ("coups = " + (@($r.Etat.coups) -join ','))
    $pTest = New-Partie -MonNom 'Dova' -NomAdversaire 'Nisse'
    $s = Sync-PartieDepuisServeur $pTest $r.Etat 'Dova'
    Assert-Vrai 'le client refuse la liste impossible' (-not $s.Ok) 'elle a ete acceptee !'
    Assert-Vrai 'et il le dit clairement' ($s.Erreur -like '*impossible*') ("message : " + $s.Erreur)
}
finally {
    Write-Host ''
    Write-Host '--- Menage ---'
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    $vivant = $null -ne (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)
    Assert-Vrai 'le serveur de test est bien arrete' (-not $vivant)
    if (Test-Path $etatFichier) { Remove-Item $etatFichier -Force }
    Assert-Vrai 'le fichier d etat jetable est supprime' (-not (Test-Path $etatFichier))
}

Write-Host ''
if ($script:rates -eq 0) {
    Write-Host ("TOUT PASSE -- " + $script:reussis + " controles.") -ForegroundColor Green
    exit 0
} else {
    Write-Host ("{0} controle(s) en echec sur {1}" -f $script:rates, ($script:reussis + $script:rates)) -ForegroundColor Red
    exit 1
}
