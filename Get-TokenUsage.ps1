# ============================================================================
#  Get-TokenUsage.ps1  -  Le "cerveau" de la barre (FORMULE CALIBREE)
#  ---------------------------------------------------------------------------
#  Ancrage : cache officiel de Claude Code (~/.claude.json, "cachedUsage-
#  Utilization.five_hour") = vrai % du compte (Code + web + telephone).
#
#  FORMULE : le % officiel est (a ~1 point pres) une fonction DETERMINISTE des
#  tokens locaux de la fenetre. Calibree sur usage-log.csv (11 releves, 2
#  sessions) par regression : chaque type de token pese dans la limite ->
#      % ~ [ (in+out)*88.996 + cc*11.1857 + cr*0.15563 ] / 1e6
#  (points par MILLION de tokens : entree+sortie plein pot, creation de cache
#  ~1/8, lecture de cache ~1/570 ; 100% ~ 1.12M tokens-equivalents).
#
#  ANCRAGE PAR DECALAGE : on calcule la formule a l'ancre (dernier fetch) et
#  maintenant. offset = officiel - formule(ancre) capte le "hors-local" (web/
#  telephone + residu) ; on le reporte sur la formule(maintenant). Resultat :
#  reactif en direct ET recale sur l'officiel a chaque fetch, sans plafond.
#  On continue a journaliser (usage-log.csv) pour re-verifier les poids.
# ============================================================================

# --- Etat (persiste dans le process via dot-source) -------------------------
$script:calTa  = $null   # horodatage du dernier rafraichissement officiel journalise

function Get-TokenUsage {
    # LiveFactor : reglage fin de l'estimation live (1 = neutre). Avec l'auto-
    # calibrage, 1.0 devrait etre juste ; baisse/monte seulement si besoin.
    param([double] $WindowHours = 5, [double] $TokenLimit = 3000000, [double] $LiveFactor = 1.0)

    $mainCfg = Join-Path $env:USERPROFILE '.claude.json'
    if (Test-Path $mainCfg) {
        try {
            $d = Get-Content $mainCfg -Raw -ErrorAction Stop | ConvertFrom-Json
            $cu = $d.cachedUsageUtilization
            if ($cu -and $cu.utilization -and $cu.utilization.five_hour) {
                $fh = $cu.utilization.five_hour
                $sd = $cu.utilization.seven_day
                $officialPct = [double]$fh.utilization
                $reset5 = if ($fh.resets_at) { ([datetime]$fh.resets_at).ToUniversalTime() } else { $null }
                $Ta = if ($cu.fetchedAtMs) { [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$cu.fetchedAtMs).UtcDateTime } else { $null }

                $now2  = [datetime]::UtcNow
                $stale = ($reset5 -and $reset5 -lt $now2)   # cache officiel perime : la fenetre a deja reset
                $dispPct = $officialPct
                if ($reset5 -and $Ta -and $officialPct -ge 0) {
                    $windowStart = if ($stale) { $reset5 } else { $reset5.AddHours(-$WindowHours) }

                    # ---- Composants de tokens sur la fenetre : maintenant (N) et a l'ancre (A) ----
                    #  A = cumul jusqu'au dernier fetch officiel (Ta) ; N = cumul jusqu'a maintenant.
                    $inN=0.0; $outN=0.0; $ccN=0.0; $crN=0.0
                    $inA=0.0; $outA=0.0; $ccA=0.0; $crA=0.0
                    $firstT = $null
                    $projectsDir = Join-Path $env:USERPROFILE '.claude\projects'
                    $files = Get-ChildItem $projectsDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
                             Where-Object { $_.LastWriteTimeUtc -ge $windowStart }
                    foreach ($file in $files) {
                        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                            if ($line -notlike '*"usage"*') { continue }
                            $mo = [regex]::Match($line, '"output_tokens":(\d+)')
                            if (-not $mo.Success) { continue }
                            $mt = [regex]::Match($line, '"timestamp":"([^"]+)"')
                            if (-not $mt.Success) { continue }
                            $t = ([datetime]::Parse($mt.Groups[1].Value)).ToUniversalTime()
                            if ($t -lt $windowStart) { continue }
                            $mi = [regex]::Match($line, '"input_tokens":(\d+)')
                            $mc = [regex]::Match($line, '"cache_creation_input_tokens":(\d+)')
                            $mr = [regex]::Match($line, '"cache_read_input_tokens":(\d+)')
                            $vOut = [double]$mo.Groups[1].Value
                            $vIn  = if ($mi.Success) { [double]$mi.Groups[1].Value } else { 0.0 }
                            $vCc  = if ($mc.Success) { [double]$mc.Groups[1].Value } else { 0.0 }
                            $vCr  = if ($mr.Success) { [double]$mr.Groups[1].Value } else { 0.0 }
                            $inN += $vIn; $outN += $vOut; $ccN += $vCc; $crN += $vCr
                            if ($null -eq $firstT -or $t -lt $firstT) { $firstT = $t }
                            if ($t -le $Ta) { $inA += $vIn; $outA += $vOut; $ccA += $vCc; $crA += $vCr }
                        }
                    }

                    # ---- Formule calibree (points par MILLION de tokens de chaque type) ----
                    $wIO = 88.996; $wCC = 11.1857; $wCR = 0.15563
                    $estNow    = (($inN + $outN) * $wIO + $ccN * $wCC + $crN * $wCR) / 1e6
                    $estAnchor = (($inA + $outA) * $wIO + $ccA * $wCC + $crA * $wCR) / 1e6

                    # ---- Officiel perime : la fenetre a reset, on affiche la formule pure ----
                    if ($stale) {
                        $dispPct = [math]::Max(0.0, [math]::Min(100.0, $estNow))
                        $newReset = if ($firstT) { $firstT.AddHours($WindowHours) } else { $null }
                        return [pscustomobject]@{
                            Source        = 'local-bridge'
                            Ratio         = [math]::Max(0.0, [math]::Min(1.0, $dispPct / 100.0))
                            OfficialRatio = $null
                            ResetTime     = $newReset
                            WeeklyRatio   = if ($sd) { [math]::Max(0.0, [math]::Min(1.0, [double]$sd.utilization / 100.0)) } else { $null }
                            TokensPerPct  = $null
                            FetchedAgeSec = if ($cu.fetchedAtMs) { [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$cu.fetchedAtMs) / 1000) } else { $null }
                        }
                    }

                    # ---- A chaque nouveau rafraichissement officiel : journaliser (re-verif des poids) ----
                    if ($script:calTa -ne $Ta) {
                        try {
                            $logPath = Join-Path $PSScriptRoot 'usage-log.csv'
                            if (-not (Test-Path $logPath)) { 'utc,official_pct,in,out,cc,cr' | Out-File $logPath -Encoding utf8 }
                            ('{0:o},{1},{2:F0},{3:F0},{4:F0},{5:F0}' -f $Ta, $officialPct, $inA, $outA, $ccA, $crA) | Add-Content $logPath -Encoding utf8
                        } catch { }
                        $script:calTa = $Ta
                    }

                    # ---- Affichage : formule en direct, recalee sur l'officiel (sans plafond) ----
                    #  offset = ce que l'officiel a en plus du local a l'ancre (usage web/tel + residu).
                    #  On le reporte sur l'estimation "maintenant" -> reactif ET ancre.
                    $offset  = $officialPct - $estAnchor
                    $dispPct = [math]::Max(0.0, [math]::Min(100.0, ($estNow + $offset) * $LiveFactor + $officialPct * (1 - $LiveFactor)))
                }

                return [pscustomobject]@{
                    Source        = 'hybrid'
                    Ratio         = [math]::Max(0.0, [math]::Min(1.0, $dispPct / 100.0))
                    OfficialRatio = [math]::Max(0.0, [math]::Min(1.0, $officialPct / 100.0))
                    ResetTime     = $reset5
                    WeeklyRatio   = if ($sd) { [math]::Max(0.0, [math]::Min(1.0, [double]$sd.utilization / 100.0)) } else { $null }
                    TokensPerPct  = $null
                    FetchedAgeSec = if ($cu.fetchedAtMs) { [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$cu.fetchedAtMs) / 1000) } else { $null }
                }
            }
        } catch { }
    }

    # ---------- REPLI : estimation locale simple (pas de cache officiel) -----
    $projectsDir = Join-Path $env:USERPROFILE ".claude\projects"
    $files = Get-ChildItem -Path $projectsDir -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ($line -notlike '*"usage"*') { continue }
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            $usage = $obj.message.usage
            if ($null -eq $usage -or $null -eq $obj.timestamp) { continue }
            # Contribution en POINTS de % (memes poids calibres que la formule principale).
            $tokens = (([double]$usage.input_tokens + [double]$usage.output_tokens) * 88.996 + [double]$usage.cache_creation_input_tokens * 11.1857 + [double]$usage.cache_read_input_tokens * 0.15563) / 1e6
            $events.Add([pscustomobject]@{ Time = [datetime]::Parse($obj.timestamp).ToUniversalTime(); Tokens = $tokens })
        }
    }
    $now = (Get-Date).ToUniversalTime()
    $sorted = $events | Sort-Object Time
    $windowStart = $null
    foreach ($e in $sorted) {
        if ($null -eq $windowStart -or $e.Time -ge $windowStart.AddHours($WindowHours)) { $windowStart = $e.Time }
    }
    $tokensUsed = 0; $resetTime = $null
    if ($null -ne $windowStart) {
        $resetTime = $windowStart.AddHours($WindowHours)
        if ($resetTime -gt $now) {
            $tokensUsed = ($sorted | Where-Object { $_.Time -ge $windowStart } | Measure-Object -Property Tokens -Sum).Sum
        } else { $tokensUsed = 0; $resetTime = $null }
    }
    # tokensUsed est deja en POINTS de % (formule calibree) -> ratio = points / 100.
    $ratio = [math]::Max(0.0, [math]::Min([double]$tokensUsed / 100.0, 1.0))
    [pscustomobject]@{
        Source='local'; Ratio=$ratio; OfficialRatio=$null; ResetTime=$resetTime
        WeeklyRatio=$null; TokensPerPct=$null; FetchedAgeSec=$null
    }
}
