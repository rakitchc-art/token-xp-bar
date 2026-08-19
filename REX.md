# Retours d'expérience

Chaque bug ou incident passé à travers les protocoles est consigné ici. Une entrée doit **obligatoirement** conclure : soit le CDC est modifié (commit dans le dépôt `protocoles-dev`), soit le CDC était suffisant mais mal appliqué. Une entrée sans conclusion n'est pas terminée.

Format d'une entrée :

```markdown
## AAAA-MM-JJ — Titre court de l'incident

**Ce qui s'est passé :** le bug ou l'incident, en une ou deux phrases.
**Le protocole qui aurait dû l'attraper :** P.. ou G..-.. (ou « aucun n'existait »).
**Conclusion :** CDC modifié (préciser quoi) — ou — CDC suffisant mais mal appliqué (préciser pourquoi).
```

---

## 2026-08-19 — Une boîte d'erreur Windows a bloqué le processus de test

**Ce qui s'est passé :** une exception non gérée dans le gestionnaire `Paint` de la fenêtre d'échecs a ouvert une boîte modale « .NET Framework — Continuer / Quitter ». Le script de capture, lancé sans surveillance, est resté bloqué dessus jusqu'à ce que Dova signale la boîte à l'écran. Le journal de sortie était vide : rien n'indiquait un échec, seulement une absence de fin.
**Le protocole qui aurait dû l'attraper :** aucun n'existait. P11 exige une capture regardée, mais rien n'exigeait qu'un script d'interface ne puisse pas attendre indéfiniment.
**Conclusion :** CDC suffisant mais mal appliqué sur un point, et complété sur un autre. Deux verrous posés dans le projet : (1) tout gestionnaire d'affichage attrape ses exceptions, les écrit dans un journal ET les peint à l'écran — jamais de boîte système, jamais de silence ; (2) tout script qui ouvre une fenêtre embarque un chien de garde qui ferme tout au bout de 30 s. À proposer au CDC comme règle générale : « un test qui ouvre une interface se ferme tout seul, même quand il échoue ».

## 2026-08-19 — `.GetNewClosure()` vide les variables `$script:`

**Ce qui s'est passé :** toute la logique de dessin vivait dans le gestionnaire `Paint`, créé avec `.GetNewClosure()`. PowerShell rattache une telle fermeture à un **module neuf** : à l'intérieur, `$script:Palette` vaut `$null`, sans le moindre avertissement à l'écriture. Résultat à l'exécution : « Impossible de trouver un constructeur approprié pour System.Drawing.SolidBrush » — un message qui désigne le dessin alors que la cause est la portée des variables.
**Le protocole qui aurait dû l'attraper :** aucun n'existait.
**Conclusion :** CDC suffisant mais mal appliqué — la règle « corriger la cause, pas le symptôme » a été respectée : au lieu de recopier la palette dans la fermeture, tout le dessin a été sorti dans de vraies fonctions (`Draw-FenetreEchecs`, `Invoke-ClicEchecs`), les gestionnaires ne faisant plus que les appeler. Bénéfice imprévu et décisif : la fenêtre entière se dessine désormais hors écran, donc se juge sans être ouverte. L'hypothèse a été **prouvée** par un test isolé (`scripts/Test-PorteeFermeture.ps1`) avant correction, pas supposée.

## 2026-08-19 — `-eq` ignore la casse, et la casse portait la couleur des pièces

**Ce qui s'est passé :** le moteur d'échecs code la couleur par la casse (`P` = pion blanc, `p` = pion noir), comme le fait la notation FEN. Or `-eq` et `-replace` sont **insensibles à la casse** en PowerShell : `[char]'P' -eq 'p'` vaut `True`. Conséquence, un pion blanc en d2 était compté comme un pion noir attaquant e1 — donc le roi blanc était vu en échec en permanence, et **aucun coup n'était légal**. Même piège sur `-replace '[KQ]'`, qui effaçait les quatre droits de roque au lieu des deux blancs.
**Le protocole qui aurait dû l'attraper :** G10 / « un contrôle se prouve par son échec » — et il l'a attrapé. Le banc de test perft a été écrit AVANT la première ligne d'interface et a renvoyé `0 noeuds attendu 20` sur les six positions : impossible de passer à la suite.
**Conclusion :** CDC suffisant et bien appliqué. La leçon transférable n'est pas le bug lui-même mais l'ordre de travail : le moteur de règles a été écrit et prouvé sur des compteurs publics (perft, 20 compteurs jusqu'à 197 281 nœuds) avant qu'un seul pixel ne soit dessiné. Un bug de cette taille découvert à travers l'interface aurait ressemblé à un problème d'affichage pendant des heures.
