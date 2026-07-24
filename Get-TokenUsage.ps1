# ============================================================================
#  Get-TokenUsage.ps1  -  Le "cerveau" de la barre
#  ---------------------------------------------------------------------------
#  Source PRINCIPALE : le cache officiel de Claude Code, dans ~/.claude.json
#  (champ "cachedUsageUtilization"). C'est EXACTEMENT ce qu'affiche le panneau
#  "Account & Usage" de VS Code et le site claude.ai : ca inclut TOUT ton usage
#  (Claude Code + web + telephone), car c'est la limite du compte.
#
#  Repli (si le cache est absent) : estimation locale a partir des .jsonl.
# ============================================================================

function Get-TokenUsage {
    param(
        [double] $WindowHours = 5,     # utilise seulement pour le repli local
        [double] $TokenLimit  = 3000000
    )

    # ---------- 1) SOURCE OFFICIELLE : ~/.claude.json ----------------------
    $mainCfg = Join-Path $env:USERPROFILE '.claude.json'
    if (Test-Path $mainCfg) {
        try {
            $d = Get-Content $mainCfg -Raw -ErrorAction Stop | ConvertFrom-Json
            $cu = $d.cachedUsageUtilization
            if ($cu -and $cu.utilization -and $cu.utilization.five_hour) {
                $fh = $cu.utilization.five_hour
                $sd = $cu.utilization.seven_day

                $reset5 = $null
                if ($fh.resets_at) { $reset5 = ([datetime]$fh.resets_at).ToUniversalTime() }
                $reset7 = $null
                if ($sd -and $sd.resets_at) { $reset7 = ([datetime]$sd.resets_at).ToUniversalTime() }

                $ageSec = $null
                if ($cu.fetchedAtMs) {
                    $ageSec = [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$cu.fetchedAtMs) / 1000)
                }

                return [pscustomobject]@{
                    Source       = 'live'
                    Ratio        = [math]::Max(0.0, [math]::Min(1.0, [double]$fh.utilization / 100.0))
                    ResetTime    = $reset5
                    WeeklyRatio  = if ($sd) { [math]::Max(0.0, [math]::Min(1.0, [double]$sd.utilization / 100.0)) } else { $null }
                    WeeklyReset  = $reset7
                    FetchedAgeSec= $ageSec
                    TokensUsed   = $null
                    TokenLimit   = $null
                }
            }
        } catch { }   # en cas de souci de lecture -> on tombe sur le repli local
    }

    # ---------- 2) REPLI : estimation locale a partir des .jsonl -----------
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
        Source       = 'local'
        Ratio        = $ratio
        ResetTime    = $resetTime
        WeeklyRatio  = $null
        WeeklyReset  = $null
        FetchedAgeSec= $null
        TokensUsed   = [long]$tokensUsed
        TokenLimit   = [long]$TokenLimit
    }
}
