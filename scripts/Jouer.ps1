# Jouer.ps1 -- client d'echecs en ligne de commande.
#
# Sert a deux choses : eprouver le serveur reel depuis un poste, et permettre
# de jouer sans la fenetre graphique (par exemple depuis une session sans
# interface). Le meme moteur et le meme client que la barre sont utilises :
# ce qui marche ici marche dans TokenBar, et reciproquement.
#
#   .\Jouer.ps1 -Nom Nisse                      montre la position
#   .\Jouer.ps1 -Nom Nisse -Coup e7e5           joue un coup
#   .\Jouer.ps1 -Nom Nisse -Image plateau.png   ecrit une image de la position
#   .\Jouer.ps1 -Nom Dova -Premiere             accepte le certificat et
#                                               affiche son empreinte
#
# Les reglages viennent des variables d'environnement ECHECS_ADRESSE,
# ECHECS_CODE et ECHECS_EMPREINTE, ou des parametres ci-dessous. Rien n'est
# ecrit en dur : ce fichier part sur un depot public.

param(
    [Parameter(Mandatory = $true)][string]$Nom,
    [string]$Adresse   = $env:ECHECS_ADRESSE,
    [string]$Code      = $env:ECHECS_CODE,
    [string]$Empreinte = $env:ECHECS_EMPREINTE,
    [string]$Coup      = '',
    [string]$Image     = '',
    [switch]$Premiere,
    [switch]$Nouvelle
)

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Client-Serveur.ps1')

if (-not $Adresse) { throw 'Adresse du serveur absente (ECHECS_ADRESSE ou -Adresse).' }
if (-not $Code)    { throw 'Code partage absent (ECHECS_CODE ou -Code).' }

function Invoke-Route {
    param([string]$Route, [hashtable]$Corps = @{})
    if ($Premiere) {
        return Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $Nom `
                                    -Route $Route -Corps $Corps -Delai 10 -AutoriserPremiere
    }
    return Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $Nom `
                                -Route $Route -Corps $Corps -Delai 10 -Empreinte $Empreinte
}

function Write-Plateau {
    param($Partie)
    $b = $Partie.Pos.B
    # Vue du cote du joueur : sa premiere rangee en bas, comme sur un vrai
    # echiquier -- sinon on lit le plateau a l'envers un coup sur deux.
    $rangs = $(if ($Partie.MaCouleur -eq 'b') { 0..7 } else { 7..0 })
    $cols  = $(if ($Partie.MaCouleur -eq 'b') { 7..0 } else { 0..7 })
    Write-Host ''
    foreach ($r in $rangs) {
        $ligne = '  ' + ($r + 1) + ' '
        foreach ($c in $cols) {
            $p = $b[$r * 8 + $c]
            $ligne += ' ' + $(if ($p -eq ' ') { '.' } else { [string]$p })
        }
        Write-Host $ligne
    }
    $lettres = '    '
    foreach ($c in $cols) { $lettres += ' ' + [char]([int][char]'a' + $c) }
    Write-Host $lettres
    Write-Host ''
    Write-Host ('  majuscules = blancs, minuscules = noirs')
}

# --- etat courant ---------------------------------------------------------
$r = Invoke-Route '/etat'
if (-not $r.Ok) {
    Write-Host ('ECHEC : ' + $r.Erreur) -ForegroundColor Red
    if ($r.EmpreinteVue) { Write-Host ('Empreinte vue : ' + $r.EmpreinteVue) }
    exit 1
}
if ($Premiere) {
    Write-Host ('Empreinte du certificat a epingler :') -ForegroundColor Cyan
    Write-Host ('  ' + $r.EmpreinteVue)
}

if ($Nouvelle) {
    $r = Invoke-Route '/nouvelle'
    if (-not $r.Ok) { Write-Host ('ECHEC : ' + $r.Erreur) -ForegroundColor Red; exit 1 }
    Write-Host 'Nouvelle partie lancee.' -ForegroundColor Green
}

$partie = New-Partie -MonNom $Nom
$s = Sync-PartieDepuisServeur $partie $r.Etat $Nom
if (-not $s.Ok) { Write-Host ('ECHEC : ' + $s.Erreur) -ForegroundColor Red; exit 1 }

# --- coup eventuel --------------------------------------------------------
if ($Coup) {
    if (-not (Test-MonTour $partie)) {
        Write-Host ("Ce n'est pas ton tour (" + (Get-TexteEtat $partie) + ').') -ForegroundColor Yellow
        exit 1
    }
    $c = ConvertFrom-Uci $partie.Pos $Coup
    if ($c -lt 0) {
        Write-Host ("Coup illegal ou malforme : " + $Coup) -ForegroundColor Red
        Write-Host ('Coups possibles : ' + ((Get-CoupsLegaux $partie.Pos | ForEach-Object { ConvertTo-Uci $_ }) -join ' '))
        exit 1
    }
    $avant = $partie.Coups.Count
    $san = ConvertTo-San $partie.Pos $c
    [void](Add-CoupPartie $partie $c)
    [void](Add-ResultatAuScore $partie)
    $env2 = Send-CoupServeur -Partie $partie -Adresse $Adresse -Code $Code -MonNom $Nom `
                             -CoupUci $Coup -AvantVersion $avant -Empreinte $Empreinte
    if (-not $env2.Ok) { Write-Host ('REFUSE : ' + $env2.Erreur) -ForegroundColor Red; exit 1 }
    Write-Host ("Coup joue : " + $san) -ForegroundColor Green
}

# --- affichage ------------------------------------------------------------
Write-Host ''
Write-Host ('  ' + $partie.MonNom + ' (' + $(if ($partie.MaCouleur -eq 'w') { 'blancs' } else { 'noirs' }) +
            ')  contre  ' + $partie.NomAdversaire)
Write-Host ('  score : ' + $partie.MesPoints + ' - ' + $partie.SesPoints)
Write-Host ('  ' + (Get-TexteEtat $partie))
if ($partie.San.Count -gt 0) {
    $liste = @()
    for ($i = 0; $i -lt $partie.San.Count; $i += 2) {
        $n = [int]($i / 2) + 1
        $t = [string]$n + '.' + $partie.San[$i]
        if (($i + 1) -lt $partie.San.Count) { $t += ' ' + $partie.San[$i + 1] }
        $liste += $t
    }
    Write-Host ('  coups : ' + ($liste -join '  '))
}
Write-Plateau $partie

if ($Image) {
    . (Join-Path $racine 'echecs\Rendu-Echiquier.ps1')
    $case = 70
    $img = New-Object System.Drawing.Bitmap (8 * $case), (8 * $case)
    $g = [System.Drawing.Graphics]::FromImage($img)
    Draw-Echiquier $g 0 0 $case $partie.Pos @{
        Retourne       = ($partie.MaCouleur -eq 'b')
        DernierDepart  = $partie.DernierDepart
        DernierArrivee = $partie.DernierArrivee
        CaseEchec      = (Get-CaseRoiEnEchec $partie)
    }
    $img.Save($Image, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $img.Dispose()
    Write-Host ('  image : ' + $Image)
}
