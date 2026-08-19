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

## 2026-08-19 — Liaison chiffrée par certificat auto-signé, épinglé à la première connexion

**Décision :** le serveur présente un certificat qu'il fabrique lui-même, valable 10 ans. TokenBar note son empreinte SHA-256 à la première connexion et refuse ensuite tout certificat différent — la règle de SSH. Seul le dialogue de connexion, quand quelqu'un est devant l'écran, a le droit d'accepter un certificat inconnu ; le sondage de fond ne l'a jamais.
**Raison :** Dova a demandé que la liaison soit sécurisée (2026-08-19). Un vrai certificat reconnu exigerait un nom de domaine — un achat, une configuration DNS et un renouvellement à surveiller. L'épinglage donne la même protection contre l'écoute et contre l'interception, sans rien acheter et sans rien à renouveler. La validité de 10 ans est délibérée : un renouvellement casserait l'épinglage chez les deux joueurs.
**Alternatives écartées :** HTTPS classique avec nom de domaine (coût récurrent, DNS, service supplémentaire) ; chiffrement applicatif avec une clé dérivée du code partagé (permettrait une attaque hors ligne sur une phrase secrète courte, et revient à assembler soi-même de la cryptographie là où TLS existe) ; Tailscale (Nisse devrait installer un client).
**Ce qui invaliderait ce choix :** l'achat d'un nom de domaine, qui rendrait Let's Encrypt possible et fermerait la fenêtre de la toute première connexion. Ou une réinstallation du serveur : le certificat changerait, et les deux joueurs devraient refaire « Oublier » puis reconfigurer.

## 2026-08-19 — Seuls deux joueurs nommés peuvent jouer

**Décision :** le serveur reçoit la liste des deux noms autorisés (`ECHECS_JOUEURS`). Les deux places sont attribuées d'office, et tout autre nom est refusé même avec le bon code. Le nom est reconnu sans tenir compte de la casse, mais c'est toujours l'orthographe de la liste qui est enregistrée.
**Raison :** demande de Dova — « on ne peut jouer qu'entre nous ». Sans liste, le code seul suffisait à prendre une place libre. La normalisation de casse évite qu'une faute de frappe crée un troisième joueur avec son propre score.
**Alternatives écartées :** s'en remettre au seul code partagé (une place libre restait prenable) ; comptes et mots de passe individuels (démesuré pour deux personnes).
**Ce qui invaliderait ce choix :** vouloir jouer à plus de deux, ou plusieurs parties en parallèle.

## 2026-08-19 — Le serveur ignore les règles des échecs

**Décision :** le serveur tient une liste ordonnée de coups et arbitre uniquement à qui c'est le tour (par la parité du nombre de coups). Il ne sait ni ce qu'est un roque ni ce qu'est un mat. Les règles sont vérifiées par les deux clients, qui **rejouent** la liste reçue dans leur propre moteur avant de l'afficher.
**Raison :** écrire un second moteur d'échecs en JavaScript obligerait à maintenir deux implémentations en accord parfait ; la première divergence produirait des parties impossibles à débloquer. Le rejeu donne en prime une garantie forte : une liste contenant l'impossible est refusée en bloc, avec un message clair, plutôt que d'aboutir à un échiquier faux. Éprouvé en sabotant à la main le fichier d'état du serveur.
**Alternatives écartées :** moteur complet côté serveur (deux implémentations à synchroniser) ; serveur qui fait confiance au client sans rejeu côté réception (un état corrompu s'afficherait comme s'il était valide).
**Ce qui invaliderait ce choix :** l'arrivée d'un troisième client écrit dans une autre langue, ou un besoin d'arbitrage que la parité ne suffit plus à trancher.

## 2026-08-19 — Notation affichée en français, notation stockée en anglais

**Décision :** la liste des coups affiche `Cf3`, `Fc4`, `Dh4#` (Cavalier, Fou, Dame). En interne et sur le réseau, tout reste en notation UCI, neutre (`g1f3`, `d8h4`).
**Raison :** l'interface est entièrement en français ; afficher `Nf3` y détonne. Mais mélanger les deux dans le stockage rendrait une partie enregistrée illisible par n'importe quel autre outil d'échecs.
**Alternatives écartées :** tout en anglais (incohérent avec le reste de l'interface) ; tout en français y compris sur le réseau (partie non réutilisable ailleurs).
**Ce qui invaliderait ce choix :** un joueur qui préférerait la notation anglaise — ce serait alors un réglage, pas un changement de stockage.

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
