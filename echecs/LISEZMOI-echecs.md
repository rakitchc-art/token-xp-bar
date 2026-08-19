# Les échecs, dans TokenBar

Une partie d'échecs asynchrone entre deux personnes, cachée dans la barre.
Pas de chronomètre : chacun joue quand il veut, même si l'autre est absent.

---

## Ce qu'il faut savoir en premier

Le jeu n'apparaît **nulle part** tant qu'aucun serveur n'est enregistré. Sans
serveur, TokenBar est exactement la barre qu'il a toujours été — c'est vérifié
au pixel près à chaque modification.

**Le geste pour ouvrir la porte :** maintenir **Ctrl + Maj**, puis
**double-cliquer sur le petit cœur** à gauche de la barre. Une fenêtre
« Connexion » s'ouvre.

Trois champs à remplir :

| Champ | Quoi mettre |
|---|---|
| **Ton nom de joueur** | Ce que tu veux, mais **différent** de celui de ton adversaire, et **toujours le même** d'une partie à l'autre (c'est lui qui porte ton score). |
| **Adresse du serveur** | `12.34.56.78:8137`, ou un nom de domaine. Le port par défaut est 8137, et la liaison est en **HTTPS** sauf si on écrit `http://` explicitement. |
| **Code partagé** | Le même secret des deux côtés. **La casse et les espaces en trop ne comptent pas** : `Le Nom Du Vent` et `le nom du vent`, c'est pareil. |

Le bouton **Tester** contacte le serveur et affiche qui joue les blancs et les
noirs. Le bouton **Enregistrer** refait cet essai avant de sauvegarder : des
réglages qui ne fonctionnent pas ne sont jamais enregistrés. Le bouton
**Oublier** efface tout : le jeu redevient invisible, comme s'il n'avait
jamais existé.

À la toute première connexion, TokenBar note l'**empreinte du certificat** du
serveur et la garde. Ensuite, il refuse tout certificat différent avec un
message explicite — même mécanique que SSH. Si un jour tu vois
« le certificat du serveur a CHANGE », c'est soit que le serveur a été
réinstallé (alors clique **Oublier** puis reconfigure), soit que quelqu'un
s'interpose.

Une fois enregistré, une **petite flèche** apparaît sous le pourcentage. Un
clic déplie le plateau juste sous la barre, un autre le replie. Une **pastille
rouge** s'allume sur la flèche quand c'est à toi de jouer.

Il n'y a **aucune fenêtre séparée** : rien dans la barre des tâches, rien qui
vole le premier plan, et aucun temps d'ouverture.

---

## Jouer

- **Clic** sur une de tes pièces : les cases où elle peut aller s'affichent
  (un disque sur une case vide, un anneau autour d'une pièce à prendre).
- **Clic** sur une de ces cases : le coup est joué. Il s'affiche
  **immédiatement** ; l'envoi au serveur part ensuite, en arrière-plan. Une
  connexion lente ne fige donc jamais le plateau.
- **Promotion** : quand un pion atteint la dernière rangée, les quatre pièces
  possibles s'empilent sur la case ; tu cliques celle que tu veux.
- **Agrandir** : la poignée en bas à gauche du plateau se tire à la souris.
  Vers la gauche et vers le bas pour agrandir — le plateau grandit de ce
  côté-là parce que la barre reste collée au bord droit de l'écran. La taille
  choisie est retenue.
- Le dernier coup de l'adversaire reste **surligné en jaune** — pratique quand
  on revient plusieurs heures après.
- Le roi en échec est entouré d'un **halo rouge**.
- **Clic droit sur le plateau** : retourner le plateau, nouvelle partie,
  abandonner, revenir aux réglages de connexion.

Les coups illégaux sont impossibles : le moteur est vérifié par 20 compteurs
perft de référence, dont 197 281 positions à quatre coups de profondeur.

### Comment on sait où on en est, sans un mot

| Signal | Ce que ça veut dire |
|---|---|
| pastille rouge sur la flèche | **c'est à toi de jouer** |
| case rouge sous un roi | ce roi est en **échec** |
| deux cases jaunes | le **dernier coup** joué |
| chevron de la flèche éteint, gris | le serveur ne répond pas ; la barre réessaie toute seule |
| liseré **vert** autour du plateau | tu as gagné |
| liseré **rouge** | tu as perdu |
| liseré **bleu-gris** | partie nulle |

Pendant la partie, le plateau n'a **aucun bord** : on ne voit que le damier.
Le liseré n'apparaît qu'à la fin, parce que c'est la seule chose qui ne
pourrait se deviner ni à la position ni ailleurs.

Chaque fin de partie a en plus un **liseré clair à l'intérieur** du premier :
une information portée par la seule couleur serait invisible pour qui distingue
mal le rouge du vert.

Quand une partie se termine, **clic droit → Nouvelle partie** en relance une, et
les couleurs s'échangent automatiquement. Le score cumulé suit la règle
classique : victoire 1 point, nulle ½, défaite 0.

---

## Installer le serveur

Le serveur est un unique fichier Node sans aucune dépendance
(`serveur/echecs-serveur.js`). Il ne connaît pas les règles des échecs : il
tient la liste des coups et arbitre à qui c'est le tour. Ce sont les deux
clients qui vérifient les règles.

Il lui faut trois choses par variables d'environnement :

| Variable | Rôle | Défaut |
|---|---|---|
| `ECHECS_CODE` | le code partagé | **aucun — le serveur refuse de démarrer sans** |
| `ECHECS_JOUEURS` | les deux seuls noms autorisés, séparés par une virgule | vide = les deux premiers venus |
| `ECHECS_CERT` / `ECHECS_CLE` | certificat et clé TLS | vide = liaison **en clair**, annoncée bruyamment au démarrage |
| `ECHECS_PORT` | port d'écoute | `8137` |
| `ECHECS_ETAT` | fichier d'état JSON | `etat.json` à côté du script |
| `ECHECS_HOTE` | interface d'écoute | `0.0.0.0` |

`ECHECS_JOUEURS` est le verrou : avec lui, les deux places sont attribuées
d'office et **personne d'autre ne peut jouer, même en connaissant le code**.
Le nom est reconnu sans tenir compte de la casse, mais c'est toujours
l'orthographe de la liste qui est enregistrée — sinon `dova` et `Dova`
deviendraient deux joueurs avec deux scores.

### Sur un serveur Linux, en service permanent

```bash
mkdir -p /root/projets/echecs-tokenbar
# y déposer echecs-serveur.js

cat > /etc/systemd/system/echecs-tokenbar.service <<'EOF'
[Unit]
Description=Echecs TokenBar
After=network.target

[Service]
Type=simple
WorkingDirectory=/root/projets/echecs-tokenbar
Environment=ECHECS_CODE=CHANGE-MOI
Environment=ECHECS_PORT=8137
Environment=ECHECS_ETAT=/root/projets/echecs-tokenbar/etat.json
ExecStart=/usr/bin/node /root/projets/echecs-tokenbar/echecs-serveur.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now echecs-tokenbar
systemctl status echecs-tokenbar
```

Puis ouvrir le port : `ufw allow 8137/tcp` (ou l'équivalent chez ton
hébergeur).

### Ce que le serveur protège, et ce qu'il ne protège pas

Il protège : **la liaison est chiffrée** (TLS, certificat auto-signé épinglé
côté client) — ni le code ni les coups ne circulent en clair. Le code partagé
est comparé à temps constant, le corps des requêtes est plafonné à 64 Ko,
chaque adresse IP est limitée à 120 requêtes par minute, seuls les deux noms
déclarés peuvent jouer, et le fichier d'état est écrit en deux temps (fichier
temporaire puis renommage) pour qu'une coupure ne laisse jamais un JSON
tronqué. Une configuration TLS à moitié fournie fait **refuser le démarrage**
plutôt que de basculer en clair sans le dire.

Il ne protège pas : le tout premier échange. Le certificat n'étant reconnu par
aucune autorité, la confiance s'établit à la première connexion — quelqu'un
déjà en position d'intercepter à cet instant précis pourrait s'y glisser. Une
fois l'empreinte notée, cette porte est fermée. Pour la fermer aussi à la
première connexion, il faudrait un vrai certificat, donc un nom de domaine.

Le certificat est valable **10 ans**, volontairement : un renouvellement
casserait l'épinglage chez les deux joueurs.

---

## Si quelque chose cloche

**« Le serveur ne répond pas »** — vérifier l'adresse et le port, puis que le
service tourne (`systemctl status echecs-tokenbar`) et que le port est ouvert.

**« Le serveur ne te connaît pas dans cette partie »** — les deux places sont
déjà prises par d'autres noms. Vérifier l'orthographe exacte de ton nom de
joueur : il est sensible à la casse.

**« Ce n'est pas ton tour »** — l'adversaire n'a pas encore joué, ou son coup
n'est pas encore arrivé. La barre se resynchronise toute seule.

**« La partie reçue contient un coup impossible »** — le fichier d'état du
serveur a été abîmé. Rien n'est affiché plutôt que d'afficher un échiquier
faux. Arrêter le service, supprimer `etat.json`, redémarrer : une partie neuve
repart (les scores sont dans ce même fichier, donc ils repartent aussi à zéro).

**Les erreurs d'affichage** sont écrites dans
`%LOCALAPPDATA%\TokenBar\echecs-erreurs.log`.
