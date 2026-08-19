# Capture-DialogueConnexion.ps1 -- ouvre le dialogue cache, clique reellement
# sur « Tester » contre le serveur indique, et photographie le resultat.
#
# Sert a verifier ce que verra Dova AVANT qu'elle ne fasse le geste secret :
# la mise en page, la lisibilite, et surtout que le bouton Tester dise vrai.
#
# Rien n'est enregistre : le dialogue est referme par « Oublier ».
#
#   ECHECS_ADRESSE=... ECHECS_CODE=... .\Capture-DialogueConnexion.ps1
#
# Sortie : scripts\dialogue-connexion.png

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
. (Join-Path $racine 'echecs\Integration-TokenBar.ps1')

$adresse = $env:ECHECS_ADRESSE
$code    = $env:ECHECS_CODE
if (-not $adresse -or -not $code) { throw 'ECHECS_ADRESSE et ECHECS_CODE sont requis.' }

# Un objet de configuration jetable, de la meme forme que celui de la barre.
$config = [pscustomobject]@{
    EchecsNom = 'Dova'; EchecsAdresse = $adresse; EchecsCode = $code; EchecsEmpreinte = ''
}

$sortie = Join-Path $PSScriptRoot 'dialogue-connexion.png'
if (Test-Path $sortie) { Remove-Item $sortie -Force }

# Un compteur dans une TABLE, pas dans une variable simple. Dans une fermeture,
# « $etape++ » lit bien la valeur capturee mais ECRIT dans une copie locale,
# jetee a la fin de l'appel : le compteur reste eternellement a 1. Muter le
# contenu d'un objet, lui, marche.
$pas = @{ n = 0 }
$minuterie = New-Object System.Windows.Forms.Timer
$minuterie.Interval = 1200
$minuterie.Add_Tick({
    $pas.n++
    $etape = $pas.n
    $f = $null
    $vus = @()
    foreach ($o in [System.Windows.Forms.Application]::OpenForms) {
        $vus += ("'" + $o.Text + "'")
        if ($o.Text -eq 'Connexion') { $f = $o }
    }
    Write-Host ("tick " + $etape + " : fenetres ouvertes = " + $(if ($vus.Count) { $vus -join ', ' } else { 'aucune' }))
    if (-not $f) { return }

    function Get-Bouton($form, $libelle) {
        foreach ($c in $form.Controls) {
            if ($c -is [System.Windows.Forms.Button] -and $c.Text -eq $libelle) { return $c }
        }
        return $null
    }

    if ($etape -eq 1) {
        # Un vrai clic sur un vrai bouton : c'est le chemin que Dova prendra,
        # pas un appel direct a la fonction de test.
        (Get-Bouton $f 'Tester').PerformClick()
        return
    }

    if ($etape -eq 2) {
        $img = New-Object System.Drawing.Bitmap $f.Width, $f.Height
        $f.DrawToBitmap($img, (New-Object System.Drawing.Rectangle 0, 0, $f.Width, $f.Height))
        $img.Save($sortie, [System.Drawing.Imaging.ImageFormat]::Png)
        $img.Dispose()
        Write-Host ("Image ecrite : " + $sortie)
        # On lit l'etiquette d'etat pour savoir CE QUE le dialogue a repondu,
        # sans avoir a dechiffrer l'image.
        foreach ($c in $f.Controls) {
            if ($c -is [System.Windows.Forms.Label] -and $c.Text -notlike '*joueur*' -and
                $c.Text -notlike '*serveur*' -and $c.Text -notlike '*partage*') {
                Write-Host ("Message affiche : " + $c.Text)
            }
        }
        return
    }

    $minuterie.Stop()
    (Get-Bouton $f 'Oublier').PerformClick()
}.GetNewClosure())

$garde = New-Object System.Windows.Forms.Timer
$garde.Interval = 25000
$garde.Add_Tick({
    $garde.Stop()
    Write-Host 'CHIEN DE GARDE : fermeture forcee.'
    foreach ($o in @([System.Windows.Forms.Application]::OpenForms)) { $o.Close() }
}.GetNewClosure())

$minuterie.Start()
$garde.Start()

$r = Show-DialogueConnexionEchecs $config (Join-Path $racine 'TokenBar.ico')
Write-Host ("Action renvoyee par le dialogue : " + $r.Action)
Write-Host ("Empreinte relevee : " + [string]$r.EmpreinteConnue)
