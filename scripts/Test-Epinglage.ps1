# Test-Epinglage.ps1 -- eprouve le chiffrement de la liaison et l'epinglage.
#
# La question a laquelle ce test repond : est-ce qu'un certificat qui CHANGE
# est reellement refuse ? Un epinglage qui ne sait pas refuser ne protege de
# rien, et rien a l'ecran ne le dirait.
#
# Deroulement : deux certificats sont fabriques, le serveur est demarre avec
# le premier, puis redemarre avec le second -- ce qui simule exactement ce
# que verrait la barre si quelqu'un s'interposait.
#
# Rien de reel n'est touche : port libre, dossier jetable, aucun VPS.

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Client-Serveur.ps1')

$script:reussis = 0
$script:rates   = 0
function Assert-Vrai {
    param([string]$Titre, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { Write-Host ("  OK   " + $Titre) -ForegroundColor Green; $script:reussis++ }
    else { Write-Host ("  RATE " + $Titre + $(if ($Detail) { "  -> " + $Detail } else { '' })) -ForegroundColor Red; $script:rates++ }
}

$bac = Join-Path $env:TEMP ('bac-tls-' + (Get-Random))
New-Item -ItemType Directory -Path $bac -Force | Out-Null

$openssl = (Get-Command openssl -ErrorAction SilentlyContinue)
if (-not $openssl) { throw 'openssl introuvable : impossible de fabriquer les certificats de test.' }

function Invoke-Openssl {
    # openssl ecrit sa barre de progression sur la sortie d'erreur. Avec
    # $ErrorActionPreference = 'Stop', PowerShell 5.1 transforme ca en
    # exception bloquante alors que la commande a parfaitement reussi.
    param([string[]]$Arguments)
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $openssl.Source @Arguments 2>&1) }
    finally { $ErrorActionPreference = $ancien }
}

function New-CertificatTest {
    param([string]$Prefixe)
    $cert = Join-Path $bac ($Prefixe + '-cert.pem')
    $cle  = Join-Path $bac ($Prefixe + '-cle.pem')
    [void](Invoke-Openssl @('req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-days', '3650',
                            '-nodes', '-keyout', $cle, '-out', $cert,
                            '-subj', "/CN=echecs-test-$Prefixe"))
    if (-not (Test-Path $cert)) { throw ("certificat non genere : " + $Prefixe) }
    # Empreinte de reference, calculee par un outil INDEPENDANT du code teste.
    $brut = (Invoke-Openssl @('x509', '-in', $cert, '-noout', '-fingerprint', '-sha256')) -join ''
    $emp = ($brut -replace '.*=', '') -replace ':', ''
    return @{ Cert = $cert; Cle = $cle; Empreinte = $emp.Trim().ToUpperInvariant() }
}

$certA = New-CertificatTest 'a'
$certB = New-CertificatTest 'b'
Assert-Vrai 'deux certificats DIFFERENTS ont ete fabriques' ($certA.Empreinte -ne $certB.Empreinte)

$ecouteur = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), 0
$ecouteur.Start(); $port = $ecouteur.LocalEndpoint.Port; $ecouteur.Stop()

$etatFichier = Join-Path $bac 'etat.json'
$code = 'le nom du vent'
$adresse = 'https://127.0.0.1:' + $port

$script:proc = $null
function Start-ServeurTest {
    param($Certificat)
    if ($script:proc -and -not $script:proc.HasExited) {
        Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
    }
    $env:ECHECS_CODE    = $code
    $env:ECHECS_JOUEURS = 'Dova,Nisse'
    $env:ECHECS_PORT    = [string]$port
    $env:ECHECS_HOTE    = '127.0.0.1'
    $env:ECHECS_ETAT    = $etatFichier
    $env:ECHECS_CERT    = $Certificat.Cert
    $env:ECHECS_CLE     = $Certificat.Cle
    $script:proc = Start-Process -FilePath 'node' `
        -ArgumentList (Join-Path $racine 'serveur\echecs-serveur.js') `
        -PassThru -WindowStyle Hidden
    for ($i = 0; $i -lt 60; $i++) {
        try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $c.Close(); return $true }
        catch { Start-Sleep -Milliseconds 150 }
    }
    return $false
}

try {
    Write-Host ''
    Write-Host '--- Serveur en HTTPS avec le certificat A ---'
    Assert-Vrai 'le serveur ecoute' (Start-ServeurTest $certA)

    Write-Host ''
    Write-Host '--- Premiere connexion : on note l empreinte ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -AutoriserPremiere
    Assert-Vrai 'la premiere connexion passe' $r.Ok $r.Erreur
    Assert-Vrai 'une empreinte a ete relevee' ([string]$r.EmpreinteVue -ne '')
    # Calibration : l'empreinte que MON code calcule doit etre celle qu'openssl
    # annonce. Sans ce controle, tout le reste du test pourrait comparer une
    # valeur fausse a elle-meme et paraitre juste.
    Assert-Vrai 'mon empreinte est celle d openssl' ($r.EmpreinteVue -eq $certA.Empreinte) `
                ("vue " + $r.EmpreinteVue + " / openssl " + $certA.Empreinte)
    $empreinteA = [string]$r.EmpreinteVue

    Write-Host ''
    Write-Host '--- Connexions suivantes ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'la bonne empreinte est acceptee' $r.Ok $r.Erreur

    $fausse = ($empreinteA.Substring(0, $empreinteA.Length - 2) + $(if ($empreinteA.EndsWith('00')) { '11' } else { '00' }))
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -Empreinte $fausse
    Assert-Vrai 'une MAUVAISE empreinte est refusee' (-not $r.Ok) 'elle a ete acceptee !'
    Assert-Vrai 'et le message parle du certificat' ($r.Erreur -like '*Certificat refuse*') ("message : " + $r.Erreur)

    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat'
    Assert-Vrai 'sans empreinte et sans autorisation, c est refuse' (-not $r.Ok) 'accepte sans rien !'

    Write-Host ''
    Write-Host '--- Le certificat CHANGE (quelqu un s interpose) ---'
    Assert-Vrai 'le serveur redemarre avec le certificat B' (Start-ServeurTest $certB)
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'l ancienne empreinte ne passe plus' (-not $r.Ok) 'le changement de certificat est passe inapercu !'
    Assert-Vrai 'et le message le dit clairement' ($r.Erreur -like '*a CHANGE*') ("message : " + $r.Erreur)

    # Retour au certificat A : la barre doit refonctionner sans rien changer.
    Assert-Vrai 'le serveur revient au certificat A' (Start-ServeurTest $certA)
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'la connexion refonctionne' $r.Ok $r.Erreur

    Write-Host ''
    Write-Host '--- Le code, majuscules ou pas ---'
    foreach ($variante in @('le nom du vent', 'Le Nom Du Vent', 'LE NOM DU VENT', '  le   nom du vent  ')) {
        $r = Invoke-ServeurEchecs -Adresse $adresse -Code $variante -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
        Assert-Vrai ("'" + $variante + "' est accepte") $r.Ok $r.Erreur
    }
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code 'le nom du vend' -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'un code faux reste refuse' ((-not $r.Ok) -and $r.CodeHttp -eq 401) ("recu " + $r.CodeHttp)

    Write-Host ''
    Write-Host '--- Seulement eux deux ---'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Nisse' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'Nisse est accepte' $r.Ok $r.Erreur
    Assert-Vrai 'les deux places sont deja attribuees' `
                (($r.Etat.joueurs.w -eq 'Dova') -and ($r.Etat.joueurs.b -eq 'Nisse')) `
                ("blancs " + $r.Etat.joueurs.w + " / noirs " + $r.Etat.joueurs.b)
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'dova' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'la casse du nom ne cree pas un troisieme joueur' `
                ($r.Ok -and $r.Etat.joueurs.w -eq 'Dova') ("blancs = " + $r.Etat.joueurs.w)
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Intrus' -Route '/etat' -Empreinte $empreinteA
    Assert-Vrai 'un troisieme joueur est refuse' ((-not $r.Ok) -and $r.CodeHttp -eq 403) `
                ("recu " + $r.CodeHttp + ' ' + $r.Erreur)

    Write-Host ''
    Write-Host '--- Une partie complete, chiffree ---'
    $p = New-Partie -MonNom 'Dova'
    $r = Invoke-ServeurEchecs -Adresse $adresse -Code $code -Joueur 'Dova' -Route '/etat' -Empreinte $empreinteA
    [void](Sync-PartieDepuisServeur $p $r.Etat 'Dova')
    $coup = ConvertFrom-Uci $p.Pos 'e2e4'
    [void](Add-CoupPartie $p $coup)
    $env2 = Send-CoupServeur -Partie $p -Adresse $adresse -Code $code -MonNom 'Dova' `
                             -CoupUci 'e2e4' -AvantVersion 0 -Empreinte $empreinteA
    Assert-Vrai 'un coup passe a travers la liaison chiffree' $env2.Ok $env2.Erreur
    Assert-Vrai 'le serveur l a bien enregistre' ($p.Coups.Count -eq 1) ("coups = " + $p.Coups.Count)
}
finally {
    Write-Host ''
    Write-Host '--- Menage ---'
    if ($script:proc -and -not $script:proc.HasExited) {
        Stop-Process -Id $script:proc.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 500
    Assert-Vrai 'le serveur de test est arrete' (-not (Get-Process -Id $script:proc.Id -ErrorAction SilentlyContinue))
    Remove-Item $bac -Recurse -Force -ErrorAction SilentlyContinue
    Assert-Vrai 'le bac a sable est supprime' (-not (Test-Path $bac))
}

Write-Host ''
if ($script:rates -eq 0) { Write-Host ("TOUT PASSE -- " + $script:reussis + " controles.") -ForegroundColor Green; exit 0 }
else { Write-Host ("{0} controle(s) en echec sur {1}" -f $script:rates, ($script:reussis + $script:rates)) -ForegroundColor Red; exit 1 }
