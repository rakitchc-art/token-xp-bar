#!/bin/sh
# ===========================================================================
#  deployer.sh -- installe le serveur d'echecs en service permanent.
#
#  A lancer SUR le serveur Linux, depuis le dossier contenant
#  echecs-serveur.js. Rejouable : relancer ce script met simplement le
#  service a jour, sans jamais toucher au code partage deja en place.
#
#  Le secret ne vit PAS dans l'unite systemd (qui est lisible par tout le
#  monde) mais dans un fichier a part, en lecture pour root seulement.
# ===========================================================================

set -e

DOSSIER=/root/projets/echecs-tokenbar
SERVICE=/etc/systemd/system/echecs-tokenbar.service
SOURCE="$(cd "$(dirname "$0")" && pwd)/echecs-serveur.js"

if [ ! -f "$SOURCE" ]; then
  echo "echecs-serveur.js introuvable a cote de ce script." >&2
  exit 2
fi

mkdir -p "$DOSSIER"
cp "$SOURCE" "$DOSSIER/echecs-serveur.js"

# Le fichier de secret n'est cree que s'il n'existe pas : relancer le
# deploiement ne doit jamais effacer un code deja convenu entre les joueurs.
if [ ! -f "$DOSSIER/code.env" ]; then
  printf 'ECHECS_CODE=\n' > "$DOSSIER/code.env"
  echo "code.env cree, VIDE : le service refusera de demarrer tant qu'aucun"
  echo "code n'y est ecrit. C'est voulu -- un secret n'a pas de valeur par defaut."
fi
chmod 600 "$DOSSIER/code.env"

cat > "$SERVICE" <<EOF
[Unit]
Description=Echecs TokenBar
After=network.target

[Service]
Type=simple
WorkingDirectory=$DOSSIER
EnvironmentFile=$DOSSIER/code.env
Environment=ECHECS_PORT=8137
Environment=ECHECS_HOTE=0.0.0.0
Environment=ECHECS_ETAT=$DOSSIER/etat.json
ExecStart=/usr/bin/node $DOSSIER/echecs-serveur.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable echecs-tokenbar >/dev/null 2>&1

echo "Deploiement termine."
echo "  dossier : $DOSSIER"
echo "  service : echecs-tokenbar (active au demarrage)"
echo
echo "Pour poser le code partage et demarrer :"
echo "  printf 'ECHECS_CODE=%s\\n' 'LE-CODE' > $DOSSIER/code.env"
echo "  chmod 600 $DOSSIER/code.env"
echo "  systemctl restart echecs-tokenbar && systemctl --no-pager status echecs-tokenbar"
