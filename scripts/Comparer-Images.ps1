# Comparer-Images.ps1 -- compte les pixels differents entre deux images et dit
# OU ils sont. Sert a prouver qu'une modification n'a rien change ailleurs que
# la ou elle devait changer.
#
#   .\Comparer-Images.ps1 -A avant.png -B apres.png

param(
    [Parameter(Mandatory = $true)][string]$A,
    [Parameter(Mandatory = $true)][string]$B,
    [string]$Difference = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ia = [System.Drawing.Bitmap]::new((Resolve-Path $A).Path)
$ib = [System.Drawing.Bitmap]::new((Resolve-Path $B).Path)

Write-Host ("A : " + $ia.Width + " x " + $ia.Height + "   " + (Split-Path $A -Leaf))
Write-Host ("B : " + $ib.Width + " x " + $ib.Height + "   " + (Split-Path $B -Leaf))

$l = [math]::Min($ia.Width,  $ib.Width)
$h = [math]::Min($ia.Height, $ib.Height)
if ($ia.Width -ne $ib.Width -or $ia.Height -ne $ib.Height) {
    Write-Host 'ATTENTION : dimensions differentes, comparaison sur la zone commune.' -ForegroundColor Yellow
}

$diff = 0
$xmin = [int]::MaxValue; $xmax = -1; $ymin = [int]::MaxValue; $ymax = -1
$carte = New-Object System.Drawing.Bitmap $l, $h

for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $l; $x++) {
        $pa = $ia.GetPixel($x, $y)
        $pb = $ib.GetPixel($x, $y)
        if ($pa.ToArgb() -eq $pb.ToArgb()) {
            $carte.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(20, 20, 22))
        } else {
            $diff++
            if ($x -lt $xmin) { $xmin = $x }; if ($x -gt $xmax) { $xmax = $x }
            if ($y -lt $ymin) { $ymin = $y }; if ($y -gt $ymax) { $ymax = $y }
            $carte.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 60, 60))
        }
    }
}

$total = $l * $h
Write-Host ("Pixels differents : " + $diff + " sur " + $total +
            "  (" + [math]::Round(100.0 * $diff / $total, 2) + " %)")
if ($diff -gt 0) {
    Write-Host ("Zone touchee : x " + $xmin + '..' + $xmax + "   y " + $ymin + '..' + $ymax)
}

if ($Difference) {
    $carte.Save($Difference, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host ("Carte des differences : " + $Difference)
}

$carte.Dispose(); $ia.Dispose(); $ib.Dispose()
exit $(if ($diff -eq 0) { 0 } else { 1 })
