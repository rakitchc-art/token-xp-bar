#!/bin/sh
# ===========================================================================
#  deployer-vps.sh -- envoie le serveur d'echecs sur une machine distante et
#  l'installe en service, en UNE SEULE connexion SSH.
#
#  Pourquoi une seule : le serveur visé coupe les connexions quand elles
#  s'enchainent trop vite (protection anti-force-brute). Trois commandes ssh
#  d'affilee echouent la ou une seule passe.
#
#  L'adresse de la machine est un ARGUMENT, jamais ecrite ici : ce fichier
#  part sur un depot public.
#
#     ./deployer-vps.sh root@mon.serveur
# ===========================================================================

set -e

HOTE="$1"
if [ -z "$HOTE" ]; then
  echo "Usage : $0 utilisateur@machine" >&2
  exit 2
fi

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
JS="$RACINE/serveur/echecs-serveur.js"
SH="$RACINE/serveur/deployer.sh"

for f in "$JS" "$SH"; do
  [ -f "$f" ] || { echo "introuvable : $f" >&2; exit 2; }
done

B64JS=$(base64 -w0 "$JS")
B64SH=$(base64 -w0 "$SH")

# Trois tentatives : la coupure est intermittente, pas definitive.
n=1
while [ $n -le 3 ]; do
  echo "--- tentative $n ---"
  if ssh -o BatchMode=yes -o ConnectTimeout=25 -o ServerAliveInterval=10 \
         -o ServerAliveCountMax=6 "$HOTE" "
      set -e
      mkdir -p /root/projets/echecs-tokenbar/depot
      printf '%s' '$B64JS' | base64 -d > /root/projets/echecs-tokenbar/depot/echecs-serveur.js
      printf '%s' '$B64SH' | base64 -d > /root/projets/echecs-tokenbar/depot/deployer.sh
      chmod +x /root/projets/echecs-tokenbar/depot/deployer.sh
      node --check /root/projets/echecs-tokenbar/depot/echecs-serveur.js && echo 'syntaxe du serveur : OK'
      sh /root/projets/echecs-tokenbar/depot/deployer.sh
      echo '--- etat du service ---'
      systemctl --no-pager status echecs-tokenbar 2>&1 | head -6 || true
      echo '--- fail2ban ---'
      (fail2ban-client status sshd 2>/dev/null | head -8) || echo 'fail2ban absent'
    "; then
    echo "--- deploiement reussi ---"
    exit 0
  fi
  n=$((n + 1))
  sleep 20
done

echo "Echec apres 3 tentatives." >&2
exit 1
