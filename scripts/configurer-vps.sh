#!/bin/sh
# ===========================================================================
#  configurer-vps.sh -- pose le code partage et la liste des joueurs sur le
#  serveur distant, puis redemarre le service.
#
#     ECHECS_CODE='...' ECHECS_JOUEURS='A,B' ./configurer-vps.sh root@machine
#
#  Le code passe par une variable d'environnement, jamais en argument : les
#  arguments d'un processus sont lisibles par n'importe qui sur la machine.
#
#  -Reinitialiser efface la partie en cours (et donc les scores). Sans lui,
#  la partie et les scores sont conserves.
# ===========================================================================

set -e

HOTE="$1"
[ -n "$HOTE" ] || { echo "Usage : ECHECS_CODE=... $0 utilisateur@machine [--reinitialiser]" >&2; exit 2; }
[ -n "$ECHECS_CODE" ] || { echo "ECHECS_CODE non fourni." >&2; exit 2; }

RESET=""
[ "$2" = "--reinitialiser" ] && RESET="rm -f \$D/etat.json; echo 'partie remise a zero'"

n=1
while [ $n -le 3 ]; do
  echo "--- tentative $n ---"
  if ssh -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 \
         -o ServerAliveCountMax=6 "$HOTE" "
      set -e
      D=/root/projets/echecs-tokenbar
      printf 'ECHECS_CODE=%s\nECHECS_JOUEURS=%s\n' '$ECHECS_CODE' '$ECHECS_JOUEURS' > \$D/code.env
      chmod 600 \$D/code.env
      $RESET
      systemctl restart echecs-tokenbar
      sleep 2
      echo '--- service ---'
      systemctl is-active echecs-tokenbar
      echo '--- journal ---'
      journalctl -u echecs-tokenbar -n 6 --no-pager | tail -4
      echo '--- ecoute ---'
      ss -ltn | grep 8137 || echo 'PAS EN ECOUTE'
      echo '--- empreinte du certificat ---'
      openssl x509 -in \$D/cert.pem -noout -fingerprint -sha256 | sed 's/.*=//' | tr -d ':' | tr 'a-f' 'A-F'
    "; then
    echo "--- configuration reussie ---"
    exit 0
  fi
  n=$((n + 1))
  echo "coupure ; nouvelle tentative dans 30 s"
  sleep 30
done

echo "Echec apres 3 tentatives." >&2
exit 1
