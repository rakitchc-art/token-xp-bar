# Assurer-Bom.ps1 -- garantit que chaque .ps1 du projet commence par un BOM
# UTF-8 (EF BB BF).
#
# Pourquoi : PowerShell 5.1 lit un .ps1 SANS BOM comme de l'ANSI Windows-1252.
# Un fichier ecrit en UTF-8 avec des accents est alors mal decode, et l'erreur
# ne ressemble pas a un probleme d'encodage -- typiquement une accolade
# "manquante" signalee des dizaines de lignes plus loin.
#
# Ce script travaille en OCTETS (ReadAllBytes / WriteAllBytes) : il ne decode
# jamais le contenu, donc il ne peut pas abimer les accents au passage.
# Ce fichier-ci est volontairement sans accent : il doit pouvoir se lancer
# avant que le BOM ne soit pose.

param(
    [string]$Racine = (Split-Path -Parent $PSScriptRoot)
)

$bom = [byte[]](0xEF, 0xBB, 0xBF)
$ajoutes = 0
$dejaOk  = 0

foreach ($f in (Get-ChildItem -Path $Racine -Filter '*.ps1' -Recurse -File)) {
    $octets = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($octets.Length -ge 3 -and
        $octets[0] -eq $bom[0] -and $octets[1] -eq $bom[1] -and $octets[2] -eq $bom[2]) {
        $dejaOk++
        continue
    }

    # Un fichier 100 % ASCII se lit identiquement en ANSI et en UTF-8 : lui
    # ajouter un BOM ne corrigerait rien et modifierait un fichier deja livre
    # pour rien. On ne touche que ce qui contient reellement du non-ASCII.
    $nonAscii = $false
    foreach ($o in $octets) { if ($o -ge 0x80) { $nonAscii = $true; break } }
    if (-not $nonAscii) { $dejaOk++; continue }
    $nouveau = New-Object 'byte[]' ($octets.Length + 3)
    [Array]::Copy($bom, 0, $nouveau, 0, 3)
    [Array]::Copy($octets, 0, $nouveau, 3, $octets.Length)
    [System.IO.File]::WriteAllBytes($f.FullName, $nouveau)
    $ajoutes++
    Write-Host ("BOM ajoute : " + $f.FullName.Substring($Racine.Length + 1))
}

Write-Host ("Termine. " + $ajoutes + " fichier(s) corrige(s), " + $dejaOk + " deja conforme(s).")
