# Test-PorteeFermeture.ps1 -- une fermeture (GetNewClosure) voit-elle encore
# les variables $script: du fichier ou elle a ete creee ?
#
# L'enjeu : la fenetre d'echecs peint dans un gestionnaire d'evenement cree
# avec .GetNewClosure(). Si $script:Palette y devient $null, le dessin part en
# exception au premier pinceau -- ce qui ressemble a un bug de dessin alors
# que c'est un bug de portee.

$script:Temoin = 'valeur du script'

function New-Fermeture {
    $local = 'valeur locale'
    return {
        $vuScript = $(if ($null -eq $script:Temoin) { '<NULL>' } else { $script:Temoin })
        $vuLocal  = $(if ($null -eq $local)         { '<NULL>' } else { $local })
        Write-Host ("  depuis la fermeture : `$script:Temoin = " + $vuScript)
        Write-Host ("  depuis la fermeture : `$local         = " + $vuLocal)
    }.GetNewClosure()
}

Write-Host 'Fermeture creee avec GetNewClosure :'
$f = New-Fermeture
& $f
