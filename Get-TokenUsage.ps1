# ============================================================================
#  Get-TokenUsage.ps1  -  Le "cerveau" de la barre (HYBRIDE AUTO-CALIBRE)
#  ---------------------------------------------------------------------------
#  Ancrage : cache officiel de Claude Code (~/.claude.json, "cachedUsage-
#  Utilization.five_hour") = vrai % du compte (Code + web + telephone).
#
#  Entre deux rafraichissements officiels, on fait avancer la barre en direct
#  grace aux tokens locaux (logs .jsonl, temps reel), puis on se re-cale sur
#  l'exact des que l'officiel bouge.
#
#  AUTO-CALIBRAGE : on APPREND le vrai "tokens locaux par %" en comparant deux
#  rafraichissements officiels successifs (dP = hausse du %, dL = hausse des
#  tokens locaux -> taux = dL/dP). C'est exact car chaque hausse du % officiel
#  vient de la conso locale (tant qu'il n'y a pas d'usage web/telephone). Tant
#  qu'on n'a pas encore appris, on utilise une estimation de repli (moyenne de
#  la fenetre). L'etat d'apprentissage persiste entre les appels (dot-source).
# ============================================================================

# --- Etat d'apprentissage (persiste dans le process) ------------------------
$script:calTPP = $null   # tokens locaux appris par 1% (taux marginal)
$script:calP   = $null   # % officiel au dernier rafraichissement
$script:calL   = $null   # tokens locaux (a l'ancre) au dernier rafraichissement
$script:calTa  = $null   # horodatage (fetchedAtMs) du dernier rafraichissement

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

                    # ---- Somme des tokens locaux : ancre (<= Ta), total, 1er evenement ----
                    $locAnchor = 0.0; $locNow = 0.0; $firstT = $null
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
                            $tok = [double]$mo.Groups[1].Value
                            if ($mi.Success) { $tok += [double]$mi.Groups[1].Value }
                            if ($mc.Success) { $tok += [double]$mc.Groups[1].Value }
                            $locNow += $tok
                            if ($null -eq $firstT -or $t -lt $firstT) { $firstT = $t }
                            if ($t -le $Ta) { $locAnchor += $tok }
                        }
                    }

                    # ---- Officiel perime : pont 100% local le temps que Code rafraichisse ----
                    if ($stale) {
                        if ($script:calTPP -and $script:calTPP -gt 0) { $dispPct = [math]::Min(100.0, $locNow / $script:calTPP) }
                        elseif ($TokenLimit -gt 0)                    { $dispPct = [math]::Min(100.0, ($locNow / $TokenLimit) * 100.0) }
                        else                                          { $dispPct = 0.0 }
                        $newReset = if ($firstT) { $firstT.AddHours($WindowHours) } else { $null }
                        return [pscustomobject]@{
                            Source        = 'local-bridge'
                            Ratio         = [math]::Max(0.0, [math]::Min(1.0, $dispPct / 100.0))
                            OfficialRatio = $null
                            ResetTime     = $newReset
                            WeeklyRatio   = if ($sd) { [math]::Max(0.0, [math]::Min(1.0, [double]$sd.utilization / 100.0)) } else { $null }
                            TokensPerPct  = $script:calTPP
                            FetchedAgeSec = if ($cu.fetchedAtMs) { [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$cu.fetchedAtMs) / 1000) } else { $null }
                        }
                    }

                    # ---- Apprentissage a chaque nouveau rafraichissement officiel ----
                    if ($script:calTa -ne $Ta) {
                        if ($null -ne $script:calTa -and $null -ne $script:calP -and $officialPct -gt $script:calP) {
                            $dP = $officialPct - $script:calP
                            $dL = $locAnchor - [double]$script:calL
                            if ($dP -ge 0.5 -and $dL -gt 10000) {
                                $learned = $dL / $dP
                                if ($script:calTPP) { $script:calTPP = 0.6 * $script:calTPP + 0.4 * $learned }
                                else                { $script:calTPP = $learned }
                            }
                        }
                        $script:calTa = $Ta; $script:calP = $officialPct; $script:calL = $locAnchor
                    }

                    # ---- Interpolation live ----
                    $deltaNow = $locNow - $locAnchor
                    if ($deltaNow -gt 0) {
                        if ($script:calTPP -and $script:calTPP -gt 0) {
                            $added = $LiveFactor * $deltaNow / $script:calTPP          # taux APPRIS (precis)
                        } elseif ($locAnchor -gt 50000 -and $officialPct -gt 0) {
                            $added = $LiveFactor * $deltaNow * $officialPct / $locAnchor  # repli (moyenne fenetre)
                        } else { $added = 0 }
                        if ($added -lt 0)  { $added = 0 }
                        if ($added -gt 20) { $added = 20 }                              # garde-fou
                        $dispPct = [math]::Min(100.0, $officialPct + $added)
                    }
                }

                return [pscustomobject]@{
                    Source        = 'hybrid'
                    Ratio         = [math]::Max(0.0, [math]::Min(1.0, $dispPct / 100.0))
                    OfficialRatio = [math]::Max(0.0, [math]::Min(1.0, $officialPct / 100.0))
                    ResetTime     = $reset5
                    WeeklyRatio   = if ($sd) { [math]::Max(0.0, [math]::Min(1.0, [double]$sd.utilization / 100.0)) } else { $null }
                    TokensPerPct  = $script:calTPP
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
            $tokens = [double]$usage.input_tokens + [double]$usage.output_tokens + [double]$usage.cache_creation_input_tokens
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
    $ratio = if ($TokenLimit -gt 0) { [math]::Min([double]$tokensUsed / $TokenLimit, 1.0) } else { 0.0 }
    [pscustomobject]@{
        Source='local'; Ratio=$ratio; OfficialRatio=$null; ResetTime=$resetTime
        WeeklyRatio=$null; TokensPerPct=$null; FetchedAgeSec=$null
    }
}
