# ============================================================================
#  Test-Moteur.ps1 — met le moteur à l'épreuve des compteurs perft.
#
#  Perft = « combien de parties distinctes existe-t-il à N coups d'ici ? ».
#  Ces totaux sont publiés et connus au nœud près pour six positions choisies
#  précisément parce qu'elles piègent les générateurs de coups : roques
#  interdits par une case attaquée, prises en passant qui découvrent le roi,
#  promotions multiples, clouages.
#
#  L'intérêt : un seul coup illégal généré, ou un seul coup légal oublié,
#  n'importe où dans l'arbre, change le total. Il n'y a aucun moyen de passer
#  ce test « par chance » ni de l'ajuster après coup.
#
#  Usage :
#     .\Test-Moteur.ps1            profondeurs complètes (plusieurs minutes)
#     .\Test-Moteur.ps1 -Rapide    profondeurs réduites (quelques secondes)
# ============================================================================

param(
    [switch]$Rapide,
    [int]$Plafond = 0   # 0 = pas de plafond ; sinon limite la profondeur testée
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Moteur-Echecs.ps1')

# Position, description, puis totaux attendus pour les profondeurs 1, 2, 3...
$cas = @(
    @{
        Nom  = 'Position de depart'
        Fen  = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
        Note = 'le cas de base : tout generateur doit le passer'
        Att  = @(20, 400, 8902, 197281)
    },
    @{
        Nom  = 'Kiwipete'
        Fen  = 'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1'
        Note = 'les deux roques des deux cotes, sous le feu de plusieurs pieces'
        Att  = @(48, 2039, 97862)
    },
    @{
        Nom  = 'Finale de pions'
        Fen  = '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1'
        Note = 'prises en passant qui decouvrent le roi sur la 5e rangee'
        Att  = @(14, 191, 2812, 43238)
    },
    @{
        Nom  = 'Promotions'
        Fen  = 'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1'
        Note = 'pions a promouvoir des deux cotes, roques noirs encore valides'
        Att  = @(6, 264, 9467)
    },
    @{
        Nom  = 'Position 5'
        Fen  = 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8'
        Note = 'promotion avec prise, roi blanc encore capable de roquer'
        Att  = @(44, 1486, 62379)
    },
    @{
        Nom  = 'Position 6'
        Fen  = 'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10'
        Note = 'position calme et dense : beaucoup de clouages potentiels'
        Att  = @(46, 2079, 89890)
    }
)

# En mode rapide on s'arrête à la profondeur 2 : ça vérifie déjà la génération
# et la réponse de l'adversaire, en quelques secondes.
$plafondEffectif = $Plafond
if ($Rapide -and $plafondEffectif -eq 0) { $plafondEffectif = 2 }

$echecs = 0
$total  = 0

foreach ($c in $cas) {
    Write-Host ''
    Write-Host ('=== ' + $c.Nom + ' ===') -ForegroundColor Cyan
    Write-Host ('    ' + $c.Note) -ForegroundColor DarkGray
    Write-Host ('    ' + $c.Fen) -ForegroundColor DarkGray

    $pos = New-Position $c.Fen

    for ($d = 1; $d -le $c.Att.Count; $d++) {
        if ($plafondEffectif -gt 0 -and $d -gt $plafondEffectif) { break }
        $attendu = $c.Att[$d - 1]
        $chrono = [System.Diagnostics.Stopwatch]::StartNew()
        $obtenu = Measure-Perft $pos $d
        $chrono.Stop()
        $total++
        $duree = [math]::Round($chrono.Elapsed.TotalSeconds, 2)

        if ($obtenu -eq $attendu) {
            Write-Host ("    profondeur {0} : {1,10} noeuds  OK  ({2} s)" -f $d, $obtenu, $duree) -ForegroundColor Green
        } else {
            $echecs++
            Write-Host ("    profondeur {0} : {1,10} noeuds  ECHEC — attendu {2}" -f $d, $obtenu, $attendu) -ForegroundColor Red
            # Le détail coup par coup dit immédiatement QUEL coup est mal
            # généré, au lieu de laisser chercher dans tout l'arbre.
            if ($d -ge 2) {
                Write-Host '    detail par coup :' -ForegroundColor Yellow
                foreach ($kv in (Measure-PerftDetail $pos $d).GetEnumerator()) {
                    Write-Host ("      {0} : {1}" -f $kv.Key, $kv.Value)
                }
            }
            break
        }
    }
}

Write-Host ''
if ($echecs -eq 0) {
    Write-Host ("TOUT PASSE — {0} compteurs verifies." -f $total) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("{0} compteur(s) FAUX sur {1}." -f $echecs, $total) -ForegroundColor Red
    exit 1
}
