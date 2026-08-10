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
#  ANCRAGE PAR DECALAGE : dispPct = officiel + echelle x (formule_maintenant -
#  formule_ancre). L'officiel porte le niveau (dont usage web/telephone) ; la
#  marge comble le retard (~5-6 min) du cache. Reactif ET recale, sans plafond.
#
#  ECHELLE DU PLAN (Pro/Max) : le % officiel est normalise par plan et la vraie
#  limite en tokens n'est PAS exposee. Les poids RELATIFS (sortie/cache) sont
#  communs a tous les plans ; seule l'echelle globale change. On l'APPREND :
#  (a) AMORCAGE des le 1er fetch exploitable : echelle ~ officiel/formule (bon
#  ordre de grandeur tout de suite, tout plan) ; (b) AFFINAGE par pente entre
#  deux fetchs : echelle ~ (d officiel)/(d formule) (precis, annule l'offset
#  web). Pro -> ~1 ; Max -> <1. Persistee dans calib-state.json (survit au redemarrage).
#  L'echelle est LIEE AU COMPTE (accountUuid) : si le compte connecte change
#  (Pro <-> Max, autre user), on repart de zero pour ne pas melanger les limites.
#  On journalise (usage-log.csv) pour re-verifier les poids relatifs.
# ============================================================================

# --- Etat (persiste entre appels dans le process ; l'echelle va sur disque) --
$script:calTa           = $null   # dernier fetch officiel journalise (anti-doublon)
$script:calPrevOff      = $null   # % officiel au fetch precedent
$script:calPrevEstRaw   = $null   # formule brute (echelle 1) a l'ancre du fetch precedent
$script:calScale        = 1.0     # facteur d'echelle du PLAN (Pro=1 ; Max<1). Auto-appris.
$script:calScaleLearned = $false  # a-t-on deja une mesure fiable ?
$script:calN            = 0        # nb d'affinages par pente (poids plus fort au debut)
$script:calAccount      = $null    # compte (accountUuid) auquel l'echelle apprise appartient
$script:calStatePath    = Join-Path $PSScriptRoot 'calib-state.json'
try {
    if (Test-Path $script:calStatePath) {
        $st = Get-Content $script:calStatePath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($st.scale)   { $script:calScale = [double]$st.scale }
        if ($st.learned) { $script:calScaleLearned = [bool]$st.learned }
        if ($st.account) { $script:calAccount = [string]$st.account }
    }
} catch { }

function Save-CalState {
    try { ([pscustomobject]@{ scale = $script:calScale; learned = $script:calScaleLearned; account = $script:calAccount } |
           ConvertTo-Json -Compress) | Out-File $script:calStatePath -Encoding utf8 } catch { }
}

function Get-TokenUsage {
    # LiveFactor : reglage fin de l'estimation live (1 = neutre). Avec l'auto-
    # calibrage, 1.0 devrait etre juste ; baisse/monte seulement si besoin.
    param([double] $WindowHours = 5, [double] $TokenLimit = 3000000, [double] $LiveFactor = 1.0)

    $mainCfg = Join-Path $env:USERPROFILE '.claude.json'
    if (Test-Path $mainCfg) {
        try {
            $d = Get-Content $mainCfg -Raw -ErrorAction Stop | ConvertFrom-Json

            # ---- Changement de COMPTE : l'echelle est propre a un compte (Pro/Max
            #      ont des limites differentes). Si le compte connecte a change, on
            #      repart de zero pour ne pas appliquer l'ancienne echelle au nouveau.
            $acct = try { [string]$d.oauthAccount.accountUuid } catch { '' }
            if (-not $acct) { $acct = try { [string]$d.cachedUsageUtilization.accountUuid } catch { '' } }
            if ($acct -and $script:calAccount -ne $acct) {
                $script:calScale = 1.0; $script:calScaleLearned = $false; $script:calN = 0
                $script:calPrevOff = $null; $script:calPrevEstRaw = $null
                $script:calAccount = $acct
                Save-CalState
            }

            # ---- Seed d'echelle selon le PLAN reconnu (une seule fois). Les poids de la
            #      formule sont calibres sur Claude Pro -> echelle exacte = 1.0. Les autres
            #      plans (Max...) restent en auto-apprentissage (amorcage + pente).
            if (-not $script:calScaleLearned) {
                $plan = try { [string]$d.oauthAccount.organizationType } catch { '' }
                if ($plan -eq 'claude_pro') {
                    $script:calScale = 1.0; $script:calScaleLearned = $true
                    Save-CalState
                }
            }
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

                    # ---- AMORCAGE immediat : des qu'on a un peu d'usage et un officiel > 1,
                    #      echelle ~ officiel/formule(ancre). Fixe le bon ordre de grandeur EN UNE
                    #      SECONDE pour tout plan (evite de sur-estimer en attendant un 2e fetch).
                    #      La pente (bloc "nouveau fetch") affine ensuite. Ne s'applique qu'une fois.
                    if (-not $script:calScaleLearned -and $estAnchor -gt 5.0 -and $officialPct -gt 1.0) {
                        $kBoot = $officialPct / $estAnchor
                        if ($kBoot -lt 0.02) { $kBoot = 0.02 }
                        if ($kBoot -gt 3.0)  { $kBoot = 3.0 }
                        $script:calScale = $kBoot; $script:calScaleLearned = $true; Save-CalState
                    }

                    # ---- Officiel perime : la fenetre a reset, on affiche la formule (a l'echelle du plan) ----
                    if ($stale) {
                        $dispPct = [math]::Max(0.0, [math]::Min(100.0, $script:calScale * $estNow))
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

                    # ---- A chaque nouveau rafraichissement officiel : apprendre l'echelle + journaliser ----
                    if ($script:calTa -ne $Ta) {
                        # Echelle du plan = pente reelle / pente-formule entre deux fetchs.
                        # Isole le marginal LOCAL (dRaw) -> annule l'offset web/tel constant.
                        # Pro reste ~1 ; Max converge tout seul vers sa vraie valeur (<1).
                        $updated = $false
                        # (a) Affinage par PENTE (precis) : d officiel / d formule entre 2 fetchs.
                        if ($null -ne $script:calPrevOff -and $null -ne $script:calPrevEstRaw) {
                            $dOff = $officialPct - $script:calPrevOff
                            $dRaw = $estAnchor  - $script:calPrevEstRaw
                            if ($dRaw -gt 3.0 -and $dOff -gt 0.5) {
                                $kInst = $dOff / $dRaw
                                if ($kInst -lt 0.02) { $kInst = 0.02 }
                                if ($kInst -gt 3.0)  { $kInst = 3.0 }
                                if (-not $script:calScaleLearned) { $script:calScale = $kInst }
                                else { $w = if ($script:calN -lt 3) { 0.5 } else { 0.3 }; $script:calScale = (1 - $w) * $script:calScale + $w * $kInst }
                                $script:calScaleLearned = $true; $script:calN++; $updated = $true
                            }
                        }
                        if ($updated) { Save-CalState }
                        $script:calPrevOff    = $officialPct
                        $script:calPrevEstRaw = $estAnchor
                        # Journal (re-verif des poids relatifs sur donnees reelles).
                        try {
                            $logPath = Join-Path $PSScriptRoot 'usage-log.csv'
                            if (-not (Test-Path $logPath)) { 'utc,official_pct,in,out,cc,cr' | Out-File $logPath -Encoding utf8 }
                            ('{0:o},{1},{2:F0},{3:F0},{4:F0},{5:F0}' -f $Ta, $officialPct, $inA, $outA, $ccA, $crA) | Add-Content $logPath -Encoding utf8
                        } catch { }
                        $script:calTa = $Ta
                    }

                    # ---- Affichage : officiel + marge reactive locale, a l'echelle du plan ----
                    #  dispPct = officiel + LiveFactor * echelle * (formule_maintenant - formule_ancre).
                    #  L'officiel porte le niveau (dont usage web) ; la marge comble le retard du
                    #  cache. Pas de plafond : l'echelle bornee (0.02..3) suffit a eviter l'emballement.
                    $marge   = $script:calScale * ($estNow - $estAnchor)
                    $dispPct = [math]::Max(0.0, [math]::Min(100.0, $officialPct + $LiveFactor * $marge))
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
    # tokensUsed est deja en POINTS de % (formule calibree), a l'echelle du plan.
    $ratio = [math]::Max(0.0, [math]::Min($script:calScale * [double]$tokensUsed / 100.0, 1.0))
    [pscustomobject]@{
        Source='local'; Ratio=$ratio; OfficialRatio=$null; ResetTime=$resetTime
        WeeklyRatio=$null; TokensPerPct=$null; FetchedAgeSec=$null
    }
}
