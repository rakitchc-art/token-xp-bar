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
| **Adresse du serveur** | `12.34.56.78:8137`, ou un nom de domaine. Le port par défaut est 8137. |
| **Code partagé** | Le même secret des deux côtés. C'est la seule chose qui protège le serveur. |

Le bouton **Tester** contacte le serveur et affiche qui joue les blancs et les
noirs, avant d'enregistrer quoi que ce soit. Le bouton **Oublier** efface les
trois champs : le jeu redevient invisible, comme s'il n'avait jamais existé.

Une fois enregistré, un **petit pion** apparaît sous le pourcentage. Un clic
dessus ouvre la partie. Une **pastille rouge** s'allume sur le pion quand c'est
à toi de jouer.

---

## Jouer

- **Clic** sur une de tes pièces : les cases où elle peut aller s'affichent
  (un disque sur une case vide, un anneau autour d'une pièce à prendre).
- **Clic** sur une de ces cases : le coup est joué et envoyé.
- **Promotion** : quand un pion atteint la dernière rangée, les quatre pièces
  possibles s'empilent sur la case ; tu cliques celle que tu veux.
- La fenêtre **s'agrandit librement** : plateau, pièces, texte et boutons
  grandissent ensemble.
- Le dernier coup de l'adversaire reste **surligné en jaune** — pratique quand
  on revient plusieurs heures après.
- Le roi en échec est entouré d'un **halo rouge**.

Les coups illégaux sont impossibles : le moteur est vérifié par 20 compteurs
perft de référence, dont 197 281 positions à quatre coups de profondeur.

Quand une partie se termine, le bouton **Nouvelle partie** en relance une, et
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
| `ECHECS_PORT` | port d'écoute | `8137` |
| `ECHECS_ETAT` | fichier d'état JSON | `etat.json` à côté du script |
| `ECHECS_HOTE` | interface d'écoute | `0.0.0.0` |

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

Il protège : le code partagé est comparé à temps constant, le corps des
requêtes est plafonné à 64 Ko, chaque adresse IP est limitée à 120 requêtes par
minute, et le fichier d'état est écrit en deux temps (fichier temporaire puis
renommage) pour qu'une coupure ne laisse jamais un JSON tronqué.

Il ne protège pas : **la liaison est en HTTP en clair**. Quiconque observe le
réseau entre les deux joueurs peut lire le code partagé. Pour une partie
d'échecs entre amis c'est un risque assumé ; si ça devait changer, la réponse
serait de mettre un reverse-proxy TLS devant (Caddy fait ça en une ligne) ou de
passer par un réseau privé type Tailscale.

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
