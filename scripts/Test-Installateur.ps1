# Test-Installateur.ps1 -- eprouve TokenBar-Installer.bat sans rien installer.
#
# Ce qui est reellement verifie :
#   1. l'auto-extraction "more +9" du .bat produit bien le PowerShell attendu
#      (c'est le mecanisme le plus fragile de tout l'installateur) ;
#   2. les 13 fichiers embarques ressortent OCTET POUR OCTET identiques aux
#      sources -- accents et BOM compris.
#
# Rien de reel n'est touche : le dossier de destination est redirige vers un
# dossier jetable, et la creation des raccourcis Bureau/Demarrage ainsi que le
# lancement de l'application sont neutralises. Chaque neutralisation est
# VERIFIEE : si une substitution ne trouve pas sa cible, le test s'arrete au
# lieu d'installer pour de vrai.

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
$batch = Join-Path $racine 'TokenBar-Installer.bat'
if (-not (Test-Path $batch)) { throw 'TokenBar-Installer.bat absent : lancer Build-Installer.ps1' }

$reussis = 0; $rates = 0
function Assert-Vrai {
    param([string]$Titre, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { Write-Host ("  OK   " + $Titre) -ForegroundColor Green; $script:reussis++ }
    else { Write-Host ("  RATE " + $Titre + $(if ($Detail) { "  -> " + $Detail } else { '' })) -ForegroundColor Red; $script:rates++ }
}

$bac = Join-Path $env:TEMP ('bac-install-' + (Get-Random))
New-Item -ItemType Directory -Path $bac -Force | Out-Null
Write-Host ("Bac a sable : " + $bac)

# --- 1. extraction reelle, par le meme "more" que cmd.exe utilisera --------
$extrait = Join-Path $bac 'extrait.ps1'
$lanceur = Join-Path $bac 'extraire.cmd'
# Passer par un vrai fichier .cmd : appeler more a travers plusieurs couches
# de guillemets change son comportement.
[System.IO.File]::WriteAllText($lanceur,
    ('@echo off' + "`r`n" + 'more +9 "' + $batch + '" > "' + $extrait + '"' + "`r`n"),
    (New-Object System.Text.ASCIIEncoding))
& $lanceur | Out-Null

Assert-Vrai 'le .bat s auto-extrait' ((Test-Path $extrait) -and (Get-Item $extrait).Length -gt 100000) `
            ("taille = " + $(if (Test-Path $extrait) { (Get-Item $extrait).Length } else { 0 }))

$src = [System.IO.File]::ReadAllText($extrait)
Assert-Vrai 'l extrait ne contient plus l en-tete batch' ($src -notmatch '@echo off')
Assert-Vrai 'l extrait commence bien par du PowerShell' ($src.TrimStart() -like '$ErrorActionPreference*')

# --- 2. neutralisation, chaque substitution controlee ---------------------
function Set-Substitution {
    param([string]$Texte, [string]$Cherche, [string]$Remplace, [string]$Titre)
    $apres = $Texte.Replace($Cherche, $Remplace)
    Assert-Vrai ('neutralisation : ' + $Titre) ($apres -ne $Texte) 'motif introuvable'
    if ($apres -eq $Texte) { throw ('substitution sans effet : ' + $Titre) }
    return $apres
}

$cible = Join-Path $bac 'installe'
$src = Set-Substitution $src "Join-Path `$env:LOCALAPPDATA 'TokenBar'" "`$env:TOKENBAR_BAC" 'dossier de destination'
$src = Set-Substitution $src "New-TokenBarShortcut (Join-Path `$startup 'TokenBar.lnk')" '# raccourci Demarrage neutralise' 'raccourci Demarrage'
$src = Set-Substitution $src "New-TokenBarShortcut (Join-Path `$desktop 'TokenBar.lnk')" '# raccourci Bureau neutralise' 'raccourci Bureau'
$src = Set-Substitution $src "Start-Process wscript.exe -ArgumentList ('`"' + `$vbs + '`"')" '# lancement neutralise' 'lancement de l application'
$src = Set-Substitution $src 'Read-Host "  Appuie sur Entree pour fermer cette fenetre"' '# attente neutralisee' 'attente clavier'

$patche = Join-Path $bac 'installe.ps1'
[System.IO.File]::WriteAllText($patche, $src, (New-Object System.Text.UTF8Encoding $false))

# --- 3. execution -----------------------------------------------------------
$env:TOKENBAR_BAC = $cible
$avantBureau  = @(Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Filter 'TokenBar.lnk' -ErrorAction SilentlyContinue).Count
$avantDemarr  = @(Get-ChildItem ([Environment]::GetFolderPath('Startup')) -Filter 'TokenBar.lnk' -ErrorAction SilentlyContinue).Count

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patche | Out-Null
Assert-Vrai 'l installateur s execute sans erreur' ($LASTEXITCODE -eq 0) ("code = " + $LASTEXITCODE)

# --- 4. fidelite octet pour octet -------------------------------------------
$fichiers = @(
    'TokenBar.ps1', 'Get-TokenUsage.ps1', 'Start-TokenBar.vbs', 'Install-Autostart.ps1',
    'TokenBar.ico',
    'echecs\Moteur-Echecs.ps1', 'echecs\Rendu-Echiquier.ps1', 'echecs\Partie-Echecs.ps1',
    'echecs\Client-Serveur.ps1', 'echecs\Fenetre-Echecs.ps1', 'echecs\Integration-TokenBar.ps1',
    'echecs\LISEZMOI-echecs.md',
    'serveur\echecs-serveur.js'
)

foreach ($rel in $fichiers) {
    $a = Join-Path $racine $rel
    $b = Join-Path $cible $rel
    if (-not (Test-Path $b)) { Assert-Vrai ($rel + ' : present') $false 'absent du dossier installe'; continue }
    $oa = [IO.File]::ReadAllBytes($a)
    $ob = [IO.File]::ReadAllBytes($b)
    $identique = ($oa.Length -eq $ob.Length)
    if ($identique) {
        for ($i = 0; $i -lt $oa.Length; $i++) { if ($oa[$i] -ne $ob[$i]) { $identique = $false; break } }
    }
    Assert-Vrai ($rel + ' : identique a la source') $identique ("source " + $oa.Length + " o, installe " + $ob.Length + " o")
}

# Le BOM est ce qui decide si PowerShell 5.1 lit un .ps1 en UTF-8 ou en ANSI :
# il merite son propre controle, separement de la comparaison globale.
foreach ($rel in @('TokenBar.ps1', 'echecs\Moteur-Echecs.ps1', 'echecs\Fenetre-Echecs.ps1')) {
    $b = Join-Path $cible $rel
    if (-not (Test-Path $b)) { continue }
    $o = [IO.File]::ReadAllBytes($b)
    $bom = ($o.Length -ge 3 -and $o[0] -eq 0xEF -and $o[1] -eq 0xBB -and $o[2] -eq 0xBF)
    Assert-Vrai ($rel + ' : BOM UTF-8 present') $bom
}

# --- 5. rien de reel n a bouge ----------------------------------------------
$apresBureau = @(Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Filter 'TokenBar.lnk' -ErrorAction SilentlyContinue).Count
$apresDemarr = @(Get-ChildItem ([Environment]::GetFolderPath('Startup')) -Filter 'TokenBar.lnk' -ErrorAction SilentlyContinue).Count
Assert-Vrai 'le raccourci Bureau reel est intact'    ($avantBureau -eq $apresBureau)
Assert-Vrai 'le raccourci Demarrage reel est intact' ($avantDemarr -eq $apresDemarr)
Assert-Vrai 'aucune installation reelle creee' (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'TokenBar\echecs'))) `
            'un dossier echecs est apparu dans la vraie installation'

Remove-Item $bac -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($rates -eq 0) { Write-Host ("TOUT PASSE -- " + $reussis + " controles.") -ForegroundColor Green; exit 0 }
else { Write-Host ("{0} controle(s) en echec sur {1}" -f $rates, ($reussis + $rates)) -ForegroundColor Red; exit 1 }
