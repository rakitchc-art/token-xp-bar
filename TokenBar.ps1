# ============================================================================
#  TokenBar.ps1  -  Barre d'XP "jeu video" de conso Claude
#  ---------------------------------------------------------------------------
#  Fine jauge facon jeu video : coeur pixel 8-bit + barre a contour noir remplie
#  d'un degrade vif vert -> rouge (donnee officielle locale). % net a droite ;
#  au survol, un bandeau sombre montre le "reset".
#    - taille FIXE, survol fiable (surveillance souris), chiffres nets (GDI)
#    - visible seulement quand VS Code est la fenetre active
#    - glisser pour deplacer, clic = rafraichir, clic droit = menu
#
#  Doit tourner en STA -> lance via "Start-TokenBar.vbs".
# ============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System; using System.Windows.Forms;
public class BarForm : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
}
"@ -ErrorAction Stop
    $FormClass = 'BarForm'
} catch { $FormClass = 'System.Windows.Forms.Form' }

Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class FgWin {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. (Join-Path $scriptDir 'Get-TokenUsage.ps1')

# --- Calcul en ARRIERE-PLAN ---------------------------------------------------
# Get-TokenUsage lit les .jsonl de la fenetre de 5h (cache incremental cote
# fichier -> ne relit que ce qui a ete ajoute depuis le dernier appel) : meme
# ainsi, l'executer directement sur le thread de l'UI FIGEAIT la fenetre
# (deplacement saccade, survol qui traine). On le lance dans un runspace
# separe, sans jamais bloquer l'UI.
$script:bgRunspace = [runspacefactory]::CreateRunspace()
$script:bgRunspace.Open()
$bgInit = [powershell]::Create()
$bgInit.Runspace = $script:bgRunspace
[void]$bgInit.AddScript({ param($dir) . (Join-Path $dir 'Get-TokenUsage.ps1') }).AddArgument($scriptDir)
$bgInit.Invoke() | Out-Null
$bgInit.Dispose()
$script:bgPs     = $null
$script:bgHandle = $null

# --- Configuration ----------------------------------------------------------
$configPath = Join-Path $scriptDir 'config.json'
$config = [pscustomobject]@{ PosRight = -1; PosY = 12; LiveFactor = 1.0 }
if (Test-Path $configPath) {
    try { $s = Get-Content $configPath -Raw | ConvertFrom-Json
          foreach ($p in $s.PSObject.Properties) { $config.$($p.Name) = $p.Value } } catch { }
}
function Save-Config { $config | ConvertTo-Json | Set-Content -Path $configPath -Encoding UTF8 }

# --- Dimensions -------------------------------------------------------------
$W = 208; $H = 20
$KEY = [System.Drawing.Color]::FromArgb(31, 31, 34)
$TXTFLAGS = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor `
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor `
            [System.Windows.Forms.TextFormatFlags]::SingleLine -bor `
            [System.Windows.Forms.TextFormatFlags]::NoPadding
# Coeur pixel 8-bit : 0=vide 1=noir 2=rouge 3=blanc (reflet)
$HEART = @('011000110','122101221','132222221','132222221','012222210','001222100','000121000','000010000')

# Geometrie de la barre (partagee entre le dessin et la detection de survol,
# pour que la zone survolable corresponde exactement a la forme visible).
$script:BX = 24.0; $script:BH = 12.0; $script:BY = ([single]$H - $script:BH) / 2
$script:BW = [single]$W - 24.0 - 44.0; $script:RAD = $script:BH / 2
$script:HeartRect = New-Object System.Drawing.Rectangle 2, 2, 18, 16
$script:PctRect    = New-Object System.Drawing.Rectangle ([int]($W - 44)), 0, 42, $H

function New-RoundedPath([single]$x,[single]$y,[single]$w,[single]$h,[single]$r) {
    $d = $r*2; if ($d -gt $h) { $d = $h }; if ($d -gt $w) { $d = $w }
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x,$y,$d,$d,180,90); $p.AddArc($x+$w-$d,$y,$d,$d,270,90)
    $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90); $p.AddArc($x,$y+$h-$d,$d,$d,90,90)
    $p.CloseFigure(); return $p
}
function Write-PixelHeart($g,[single]$ox,[single]$oy,[single]$cell){
    $old = $g.SmoothingMode; $g.SmoothingMode = 'None'
    $K  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(14,14,16))
    $R  = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(226,36,42))
    $Wt = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245,245,245))
    for($ry=0; $ry -lt $HEART.Count; $ry++){ $line = $HEART[$ry]
        for($cx=0; $cx -lt $line.Length; $cx++){ $ch = $line[$cx]
            if($ch -eq '0'){ continue }
            $br = if($ch -eq '1'){$K}elseif($ch -eq '2'){$R}else{$Wt}
            $g.FillRectangle($br, ($ox+$cx*$cell),($oy+$ry*$cell),$cell,$cell)
        }
    }
    $K.Dispose(); $R.Dispose(); $Wt.Dispose(); $g.SmoothingMode = $old
}

# --- Fenetre ----------------------------------------------------------------
$form                 = New-Object $FormClass
$form.FormBorderStyle = 'None'
$form.TopMost         = $true
$form.ShowInTaskbar   = $false
$form.Size            = New-Object System.Drawing.Size($W, $H)
$form.BackColor       = $KEY
$form.TransparencyKey = $KEY
$form.StartPosition   = 'Manual'
$icoPath = Join-Path $scriptDir 'TokenBar.ico'
if (Test-Path $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon $icoPath } catch { } }

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$posRight = if ($config.PosRight -lt 0) { $screen.Right - 12 } else { [int]$config.PosRight }
$form.Location = New-Object System.Drawing.Point(($posRight - $W), [int]$config.PosY)

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Fill'; $panel.BackColor = $KEY
$form.Controls.Add($panel)
$panel.GetType().GetProperty('DoubleBuffered',
    [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
).SetValue($panel, $true, $null)

$script:ratio           = 0.0
$script:pctText         = '···'
$script:resetText       = '?'
$script:weeklyText      = ''
$script:hover           = $false
$script:lastResetTime   = $null
$script:lastWeeklyRatio = $null

$panel.Add_Paint({
    param($src, $e)
    $g = $e.Graphics
    $g.SmoothingMode='AntiAlias'; $g.PixelOffsetMode='HighQuality'
    $g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAlias
    $g.Clear($KEY)

    Write-PixelHeart $g 2 2 2                    # coeur pixel a gauche

    $bx=$script:BX; $by=$script:BY; $bw=$script:BW; $bh=$script:BH; $rad=$script:RAD
    $outer = New-RoundedPath $bx $by $bw $bh $rad
    $tb = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF $bx,$by,$bw,$bh),([System.Drawing.Color]::FromArgb(118,118,124)),([System.Drawing.Color]::FromArgb(94,94,100)),90.0
    $g.FillPath($tb,$outer); $tb.Dispose()

    $g.SetClip($outer)
    $r=[double]$script:ratio
    $fillW=[single]([math]::Max(0.0,[math]::Min([double]$bw,[double]$bw*$r)))
    if($fillW -gt 0.5){
        $full=New-Object System.Drawing.RectangleF $bx,$by,$bw,$bh
        $lg=New-Object System.Drawing.Drawing2D.LinearGradientBrush $full,([System.Drawing.Color]::White),([System.Drawing.Color]::White),0.0
        $cb=New-Object System.Drawing.Drawing2D.ColorBlend 5
        $cb.Colors=@([System.Drawing.Color]::FromArgb(40,205,65),[System.Drawing.Color]::FromArgb(180,225,40),[System.Drawing.Color]::FromArgb(245,215,35),[System.Drawing.Color]::FromArgb(245,150,30),[System.Drawing.Color]::FromArgb(230,40,40))
        $cb.Positions=@(0.0,0.35,0.55,0.78,1.0); $lg.InterpolationColors=$cb
        $g.FillRectangle($lg,(New-Object System.Drawing.RectangleF $bx,$by,$fillW,$bh)); $lg.Dispose()
        $sp=New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(45,0,0,0)),1.0
        for($i=1;$i -lt 9;$i++){ $sxp=$bx+($bw/9.0)*$i; if($sxp -lt ($bx+$fillW)){ $g.DrawLine($sp,$sxp,$by,$sxp,($by+$bh)) } }
        $sp.Dispose()
        $gr=New-Object System.Drawing.RectangleF $bx,$by,$fillW,($bh*0.48)
        $gl=New-Object System.Drawing.Drawing2D.LinearGradientBrush $gr,([System.Drawing.Color]::FromArgb(95,255,255,255)),([System.Drawing.Color]::FromArgb(0,255,255,255)),90.0
        $g.FillRectangle($gl,$gr); $gl.Dispose()
    }
    $g.ResetClip()
    $ol=New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(235,10,10,12)),2.0
    $g.DrawPath($ol,$outer)

    $font=New-Object System.Drawing.Font 'Segoe UI',9.5,([System.Drawing.FontStyle]::Bold)
    $rc=New-Object System.Drawing.Rectangle ([int]($W-44)),0,42,$H
    $rcSh=New-Object System.Drawing.Rectangle ([int]($W-44)+1),1,42,$H
    [System.Windows.Forms.TextRenderer]::DrawText($g,$script:pctText,$font,$rcSh,([System.Drawing.Color]::FromArgb(0,0,0)),$TXTFLAGS)
    [System.Windows.Forms.TextRenderer]::DrawText($g,$script:pctText,$font,$rc,([System.Drawing.Color]::White),$TXTFLAGS)

    if($script:hover){
        $ob=New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(210,20,20,22))
        $g.FillPath($ob,$outer); $ob.Dispose()
        $g.DrawPath($ol,$outer)                  # contour redessine par-dessus (net)
        $rf=New-Object System.Drawing.Rectangle ([int]$bx),0,([int]$bw),$H
        $hoverFont = if ($script:weeklyText) { New-Object System.Drawing.Font 'Segoe UI',8.5,([System.Drawing.FontStyle]::Bold) } else { $font }
        $hoverLine = if ($script:weeklyText) { "$script:resetText  ·  $script:weeklyText" } else { $script:resetText }
        [System.Windows.Forms.TextRenderer]::DrawText($g,$hoverLine,$hoverFont,$rf,([System.Drawing.Color]::FromArgb(238,238,238)),$TXTFLAGS)
        if ($script:weeklyText) { $hoverFont.Dispose() }
    }
    $ol.Dispose(); $outer.Dispose(); $font.Dispose()
})

# --- Detection de survol PRECISE : uniquement sur la forme visible (coeur,
#     pilule arrondie, texte %), pas sur tout le rectangle de la fenetre
#     (qui inclut des marges/coins transparents plus larges que la barre).
function Test-OverBar([System.Drawing.Point]$pt) {
    if ($script:HeartRect.Contains($pt)) { return $true }
    if ($script:PctRect.Contains($pt))   { return $true }
    $path = New-RoundedPath $script:BX $script:BY $script:BW $script:BH $script:RAD
    $over = $path.IsVisible($pt)
    $path.Dispose()
    return $over
}

# --- Recalcul ---------------------------------------------------------------
function Format-Reset($resetUtc) {
    if (-not $resetUtc) { return '?' }
    $mins = [int]((([datetime]$resetUtc) - (Get-Date).ToUniversalTime()).TotalMinutes)
    if ($mins -lt 0) { $mins = 0 }
    if ($mins -ge 60) { return ("{0}h{1:00}" -f [math]::Floor($mins/60), ($mins%60)) }
    return ("{0} min" -f $mins)
}
function Apply-Usage($u) {
    $script:ratio           = [double]$u.Ratio
    $script:pctText         = "{0:P0}" -f $u.Ratio
    $script:lastResetTime   = $u.ResetTime
    $script:lastWeeklyRatio = $u.WeeklyRatio
    $script:resetText       = Format-Reset $u.ResetTime
    $script:weeklyText      = if ($null -ne $u.WeeklyRatio) { "{0:P0} sem." -f $u.WeeklyRatio } else { '' }
    $panel.Invalidate()
}
function Start-BgUpdate {
    # Calcul ASYNCHRONE (thread separe) : ne bloque jamais l'UI. Si un calcul
    # est deja en cours, on ne relance pas (evite d'empiler des appels).
    if ($script:bgHandle) { return }
    $ps = [powershell]::Create()
    $ps.Runspace = $script:bgRunspace
    [void]$ps.AddScript({ param($lf) Get-TokenUsage -LiveFactor $lf }).AddArgument($config.LiveFactor)
    $script:bgPs     = $ps
    $script:bgHandle = $ps.BeginInvoke()
}

# --- Deplacement + clic = rafraichir ----------------------------------------
$script:drag = $false; $script:moved = $false; $script:dragOff = New-Object System.Drawing.Point 0,0
$panel.Add_MouseDown({ param($s,$e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:drag = $true; $script:moved = $false; $script:dragOff = $e.Location }
})
$panel.Add_MouseMove({ param($s,$e)
    if ($script:drag) {
        $script:moved = $true
        $form.Location = New-Object System.Drawing.Point `
            (($form.Location.X + $e.X - $script:dragOff.X), ($form.Location.Y + $e.Y - $script:dragOff.Y))
    }
})
$panel.Add_MouseUp({ param($s,$e)
    if ($script:drag) {
        $script:drag = $false
        if ($script:moved) { $config.PosRight = $form.Left + $form.Width; $config.PosY = $form.Top; Save-Config }
        else { Start-BgUpdate }
    }
})

# --- Menu clic droit --------------------------------------------------------
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miRefresh = $menu.Items.Add("Actualiser maintenant"); $miRefresh.Add_Click({ Start-BgUpdate })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miClose = $menu.Items.Add("Fermer"); $miClose.Add_Click({ $form.Close() })
$panel.ContextMenuStrip = $menu

# --- Visibilite : seulement quand VS Code est la fenetre ACTIVE --------------
function Sync-Visibility {
    $hwnd = [FgWin]::GetForegroundWindow()
    $fpid = 0; [FgWin]::GetWindowThreadProcessId($hwnd, [ref]$fpid) | Out-Null
    $show = $false
    if ($fpid -eq $PID) { $show = $true }
    else { try { $pn = (Get-Process -Id $fpid -ErrorAction Stop).ProcessName; if ($pn -eq 'Code' -or $pn -eq 'Code - Insiders') { $show = $true } } catch { } }
    if ($show) { if (-not $form.Visible) { $form.Show(); Start-BgUpdate }; $form.TopMost = $true }
    else       { if ($form.Visible) { $form.Hide() } }
}

# --- Minuteries -------------------------------------------------------------
# Rafraichissement : on surveille la DATE DE MODIF du cache de Claude Code
# -> la barre se met a jour des que Claude Code y ecrit de nouvelles donnees
# (dans la seconde), au lieu d'attendre. + refresh de secours toutes les 30 s
# pour faire descendre le compte a rebours du reset.
$script:lastWrite = [datetime]::MinValue
$script:tick = 0
$mainCfgPath = Join-Path $env:USERPROFILE '.claude.json'
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    $script:tick++
    try {
        $lw = (Get-Item $mainCfgPath -ErrorAction Stop).LastWriteTimeUtc
        if ($lw -ne $script:lastWrite) { $script:lastWrite = $lw; Start-BgUpdate; return }  # re-calage instantane sur l'officiel
    } catch { }
    if ($script:tick % 4 -eq 0) { Start-BgUpdate }   # estimation "live" (conso locale) toutes les 4 s
})
$timer.Start()

$visTimer = New-Object System.Windows.Forms.Timer
$visTimer.Interval = 500
$visTimer.Add_Tick({ Sync-Visibility }); $visTimer.Start()

# Sondage du calcul en arriere-plan : recupere le resultat des qu'il est pret,
# sans jamais attendre/bloquer (IsCompleted est instantane a lire).
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 200
$pollTimer.Add_Tick({
    if ($script:bgHandle -and $script:bgHandle.IsCompleted) {
        try {
            $result = $script:bgPs.EndInvoke($script:bgHandle)
            if ($result) { Apply-Usage $result[0] }
        } catch { }
        finally { $script:bgPs.Dispose(); $script:bgPs = $null; $script:bgHandle = $null }
    }
})
$pollTimer.Start()

# Survol FIABLE : on surveille la position de la souris (plus de blocage).
# INSTANTANE : on ne relance PAS Get-TokenUsage (lecture des .jsonl, couteux)
# au survol -> on reformate juste les valeurs deja en cache (Update-Bar les
# rafraichit en tache de fond toutes les ~4 s). Le compte a rebours reste
# vivant pendant le survol (recalcul cette partie, pure arithmetique).
$hoverTimer = New-Object System.Windows.Forms.Timer
$hoverTimer.Interval = 150
$hoverTimer.Add_Tick({
    $localPt = $panel.PointToClient([System.Windows.Forms.Cursor]::Position)
    $over = Test-OverBar $localPt
    if ($over) {
        $script:resetText  = Format-Reset $script:lastResetTime
        $script:weeklyText = if ($null -ne $script:lastWeeklyRatio) { "{0:P0} sem." -f $script:lastWeeklyRatio } else { '' }
        $script:hover = $true
        $panel.Invalidate()
    } elseif ($script:hover) {
        $script:hover = $false
        $panel.Invalidate()
    }
})
$hoverTimer.Start()

# --- Go ! -------------------------------------------------------------------
# Meme le premier calcul part en arriere-plan (cache froid = jusqu'a plusieurs
# secondes de lecture) : la fenetre s'affiche tout de suite avec "..." et se
# met a jour des que le resultat arrive (pollTimer), sans jamais geler l'UI.
Start-BgUpdate
[System.Windows.Forms.Application]::EnableVisualStyles()
$form.Add_Shown({ Sync-Visibility })
$form.Add_FormClosed({ try { $script:bgPs.Dispose() } catch {}; try { $script:bgRunspace.Close(); $script:bgRunspace.Dispose() } catch {} })
[System.Windows.Forms.Application]::Run($form)
