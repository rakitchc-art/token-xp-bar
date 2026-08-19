# Diag-Moteur.ps1 -- isole ou le moteur perd les coups.
# Etage par etage : un coup pseudo-legal, la position obtenue, le roi, l'echec.

$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'echecs\Moteur-Echecs.ps1')

$pos = New-Position
$pseudo = @(Get-CoupsPseudoLegaux $pos)
Write-Host ("Pseudo-legaux : " + $pseudo.Count)

$c = $pseudo[0]
Write-Host ("Premier coup : " + (ConvertTo-Uci $c) + "  (entier " + $c + ")")

$apres = Invoke-Coup $pos $c
Write-Host ("Type de \$apres      : " + $apres.GetType().FullName)
Write-Host ("Type de \$apres.B    : " + $apres.B.GetType().FullName)
Write-Host ("FEN apres le coup   : " + (ConvertTo-Fen $apres))

$blanc = ($pos.Trait -eq 'w')
Write-Host ("\$blanc = " + $blanc)

$r = Get-CaseRoi $apres.B $blanc
Write-Host ("Get-CaseRoi -> " + $r + "  (type " + $r.GetType().Name + ")")
if ($r -ge 0) { Write-Host ("   soit la case " + (ConvertFrom-CaseIndex $r)) }

$att = Test-CaseAttaquee $apres.B $r (-not $blanc)
Write-Host ("Test-CaseAttaquee(roi blanc, par les noirs) -> " + $att + "  (type " + $att.GetType().Name + ")")

# Le meme test, mais sur une case ou la reponse est connue d'avance :
# e2 apres 1.a3 doit etre attaquee par le roi blanc, jamais par les noirs.
Write-Host ("Controle : a1 attaquee par les blancs ? " + (Test-CaseAttaquee $apres.B 0 $true))
Write-Host ("Controle : a8 attaquee par les noirs ?  " + (Test-CaseAttaquee $apres.B 56 $false))
