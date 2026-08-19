# Attendre-Tour.ps1 -- guetteur : dort jusqu'a ce que ce soit mon tour.
#
# Sert a jouer sans surveiller l'ecran : le script rend la main uniquement
# quand l'adversaire a joue (ou que la partie se termine), et affiche alors
# la position. Il ne joue rien lui-meme.
#
#   .\Attendre-Tour.ps1 -Nom Nisse
#
# Codes de sortie : 0 = c'est mon tour, 2 = partie terminee, 3 = delai depasse,
# 1 = erreur persistante de connexion.

param(
    [Parameter(Mandatory = $true)][string]$Nom,
    [string]$Adresse   = $env:ECHECS_ADRESSE,
    [string]$Code      = $env:ECHECS_CODE,
    [string]$Empreinte = $env:ECHECS_EMPREINTE,
    [int]$Intervalle   = 10,
    [int]$MinutesMax   = 50
)

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Moteur-Echecs.ps1')
. (Join-Path $racine 'echecs\Partie-Echecs.ps1')
. (Join-Path $racine 'echecs\Client-Serveur.ps1')

if (-not $Adresse -or -not $Code) { throw 'ECHECS_ADRESSE et ECHECS_CODE sont requis.' }

$limite = (Get-Date).AddMinutes($MinutesMax)
$echecsDaffilee = 0
$dernierNb = -1

while ((Get-Date) -lt $limite) {
    $r = Invoke-ServeurEchecs -Adresse $Adresse -Code $Code -Joueur $Nom `
                              -Route '/etat' -Delai 10 -Empreinte $Empreinte
    if (-not $r.Ok) {
        # Une coupure passagere ne doit pas arreter le guetteur, mais une
        # panne durable ne doit pas non plus etre avalee en silence.
        $echecsDaffilee++
        if ($echecsDaffilee -ge 12) {
            Write-Host ('ARRET : le serveur ne repond plus (' + $r.Erreur + ')')
            exit 1
        }
        Start-Sleep -Seconds $Intervalle
        continue
    }
    $echecsDaffilee = 0

    $etat = $r.Etat
    $nb = 0
    if ($etat.coups) { $nb = @($etat.coups).Count }
    if ($nb -ne $dernierNb) {
        Write-Host ((Get-Date -Format 'HH:mm:ss') + '  coups joues : ' + $nb)
        $dernierNb = $nb
    }

    if ($etat.termine) {
        Write-Host 'PARTIE TERMINEE.'
        exit 2
    }

    $couleur = $null
    if ($etat.joueurs.w -eq $Nom) { $couleur = 'w' }
    elseif ($etat.joueurs.b -eq $Nom) { $couleur = 'b' }
    if (-not $couleur) { Write-Host 'ARRET : ce serveur ne me connait pas.'; exit 1 }

    $auTrait = $(if ($nb % 2 -eq 0) { 'w' } else { 'b' })
    if ($auTrait -eq $couleur) {
        $partie = New-Partie -MonNom $Nom
        $s = Sync-PartieDepuisServeur $partie $etat $Nom
        if (-not $s.Ok) { Write-Host ('ARRET : ' + $s.Erreur); exit 1 }
        Write-Host ''
        Write-Host ('C EST MON TOUR. ' + (Get-TexteEtat $partie))
        if ($partie.San.Count -gt 0) {
            Write-Host ('Dernier coup adverse : ' + $partie.San[$partie.San.Count - 1])
            $liste = @()
            for ($i = 0; $i -lt $partie.San.Count; $i += 2) {
                $t = [string]([int]($i / 2) + 1) + '.' + $partie.San[$i]
                if (($i + 1) -lt $partie.San.Count) { $t += ' ' + $partie.San[$i + 1] }
                $liste += $t
            }
            Write-Host ('Partie : ' + ($liste -join '  '))
        }
        exit 0
    }

    Start-Sleep -Seconds $Intervalle
}

Write-Host ('Delai de ' + $MinutesMax + ' minutes depasse sans coup adverse.')
exit 3
