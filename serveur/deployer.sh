#!/bin/sh
# ===========================================================================
#  deployer.sh -- installe le serveur d'echecs en service permanent, en HTTPS.
#
#  A lancer SUR le serveur Linux, depuis le dossier contenant
#  echecs-serveur.js. Rejouable : relancer ce script met le service a jour
#  sans jamais toucher au code partage ni au certificat deja en place.
#
#  Le certificat est fabrique ici meme, valable 10 ans. Il n'est reconnu par
#  aucune autorite -- c'est voulu : le client note son empreinte a la premiere
#  connexion et refuse ensuite tout certificat different, comme le fait SSH.
#  Une validite longue evite qu'un renouvellement casse cet epinglage.
#
#  Le secret ne vit PAS dans l'unite systemd (lisible par tout le monde) mais
#  dans un fichier a part, en lecture pour root seulement.
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

# --- certificat -----------------------------------------------------------
if [ ! -f "$DOSSIER/cert.pem" ] || [ ! -f "$DOSSIER/cle.pem" ]; then
  echo "Fabrication du certificat (10 ans)..."
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$DOSSIER/cle.pem" -out "$DOSSIER/cert.pem" \
    -subj "/CN=echecs-tokenbar" >/dev/null 2>&1
else
  echo "Certificat deja present : conserve (le remplacer casserait l'epinglage)."
fi
chmod 600 "$DOSSIER/cle.pem"
chmod 644 "$DOSSIER/cert.pem"

# --- secret et liste des joueurs -----------------------------------------
if [ ! -f "$DOSSIER/code.env" ]; then
  printf 'ECHECS_CODE=\nECHECS_JOUEURS=\n' > "$DOSSIER/code.env"
  echo "code.env cree, VIDE : le service refusera de demarrer tant qu'aucun"
  echo "code n'y est ecrit. C'est voulu -- un secret n'a pas de valeur par defaut."
fi
chmod 600 "$DOSSIER/code.env"

# --- service --------------------------------------------------------------
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
Environment=ECHECS_CERT=$DOSSIER/cert.pem
Environment=ECHECS_CLE=$DOSSIER/cle.pem
ExecStart=/usr/bin/node $DOSSIER/echecs-serveur.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable echecs-tokenbar >/dev/null 2>&1

echo
echo "Deploiement termine."
echo "  dossier : $DOSSIER"
echo "  service : echecs-tokenbar (active au demarrage, HTTPS sur 8137)"
echo
echo "Empreinte SHA-256 du certificat (celle que le client doit epingler) :"
openssl x509 -in "$DOSSIER/cert.pem" -noout -fingerprint -sha256 \
  | sed 's/.*=//' | tr -d ':' | tr 'a-f' 'A-F'
