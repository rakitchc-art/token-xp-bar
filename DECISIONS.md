# Décisions structurantes

Ce qui est tranché. Entrées les plus récentes en haut. Voir le CDC (dépôt `protocoles-dev`) pour la règle P12.

Format d'une entrée :

```markdown
## AAAA-MM-JJ — Titre court de la décision

**Décision :** ce qui a été choisi.
**Raison :** pourquoi.
**Alternatives écartées :** lesquelles, et pourquoi elles ont perdu.
**Ce qui invaliderait ce choix :** le signal qui devrait faire rouvrir la question.
```

---

## 2026-08-19 — Le jeu d'échecs vit DANS TokenBar, pas à côté

**Décision :** la fonctionnalité échecs est une extension de TokenBar (même dépôt, même installateur, même processus PowerShell), pas une application séparée.
**Raison :** demande explicite de Dova le 2026-08-15 — c'est un easter egg de TokenBar, déverrouillé par la saisie d'une adresse de serveur. Un exécutable de plus casserait la promesse « l'installateur ne présente qu'un seul fichier ».
**Alternatives écartées :** application indépendante (deux binaires à distribuer, deux raccourcis, l'easter egg n'a plus de sens) ; extension VS Code (écartée par Dova : « elle est comme la fenêtre de tokenbar »).
**Ce qui invaliderait ce choix :** si le poids du jeu dégradait mesurablement la barre (CPU, mémoire, démarrage) — auquel cas le jeu deviendrait un second processus lancé à la demande, mais toujours livré par le même installateur.

## 2026-08-19 — Rendu du plateau : vectoriel GDI+, fenêtre redimensionnable

**Décision :** le plateau et les pièces sont dessinés en vectoriel (`GraphicsPath` GDI+), dans une fenêtre WinForms librement redimensionnable ; aucune image bitmap, aucune police à glyphes d'échecs.
**Raison :** Nisse a des problèmes de vue et doit pouvoir agrandir la fenêtre à sa guise (demande de Dova, 2026-08-19). Du vectoriel reste net à n'importe quelle taille ; un bitmap devient flou dès qu'on dépasse sa résolution native. Une police (♔♕♖) ajoute un risque de glyphe manquant — déjà vécu avec ⏸ (voir mémoire `machine-glyphe-pause-tofu`).
**Alternatives écartées :** WebView2 + plateau HTML/JS (look chess.com facile, mais dépendance runtime et deux mondes dans un projet 100 % PowerShell) ; application C#/.NET WPF séparée (rendu plus riche, mais un binaire de plus à construire, signer et distribuer) ; sprites PNG haute résolution embarqués (flous au-delà de leur taille native).
**Ce qui invaliderait ce choix :** si le dessin vectoriel s'avérait trop lent au redimensionnement sur la machine de Nisse, ou si le rendu obtenu ne tenait pas la comparaison avec chess.com après validation visuelle de Dova.

## 2026-08-19 — Transport : service HTTP public sur le VPS + code secret partagé

**Décision :** l'état de la partie vit dans un mini service HTTP sur le VPS Hetzner, joignable par son IP publique, protégé par un code secret partagé entre les deux joueurs. TokenBar demande une adresse de serveur et un code.
**Raison :** Nisse n'a pas accès au VPS et ne doit rien avoir à installer. Coller une adresse + un code est exactement le geste imaginé par Dova pour déverrouiller l'easter egg. Le jeu doit être asynchrone (jouer même si l'autre est absent), donc un état persistant côté serveur est nécessaire.
**Alternatives écartées :** Tailscale (rien d'exposé sur Internet, mais Nisse doit créer un compte, installer le client et accepter une invitation — friction rédhibitoire pour un jeu) ; dépôt GitHub privé partagé comme boîte aux lettres (zéro serveur, mais lent et deux coups simultanés produisent un conflit git à démêler à la main).
**Ce qui invaliderait ce choix :** un abus depuis Internet (le service est public), ou une exigence de confidentialité plus forte — auquel cas retour à Tailscale.

## 2026-08-19 — Déverrouillage : geste caché une fois, puis icône permanente

**Décision :** l'accès au champ « serveur » se fait par un geste caché non documenté dans l'interface. Une fois un serveur enregistré, une petite icône échiquier s'affiche en permanence sous le pourcentage de la barre ; un clic ouvre le jeu, et un point rouge apparaît sur cette icône quand c'est au tour de Dova de jouer.
**Raison :** demande de Dova (2026-08-19) — elle veut le plaisir du secret à la découverte, mais pas d'un secret à refaire tous les jours.
**Alternatives écartées :** entrée « Connexion… » toujours visible dans le clic droit (découvrable, mais tue la surprise) ; geste secret à refaire à chaque fois (introuvable six mois plus tard).
**Ce qui invaliderait ce choix :** si le geste caché s'avérait déclenchable par accident pendant l'usage normal de la barre.
