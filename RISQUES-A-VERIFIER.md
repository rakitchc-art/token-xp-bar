# Risques à vérifier

La maison des GO CONDITIONNEL : ce qui reste en suspens et devra être tranché. Entrées les plus récentes en haut.

Format d'une entrée :

```markdown
## AAAA-MM-JJ — Titre court du point en suspens

**Origine :** la tâche et la porte qui ont produit le ⚠️.
**Risque :** ce qui peut mal se passer si on ne tranche jamais.
**À vérifier ou trancher :** la question précise à laquelle il faut répondre.
**Statut :** EN SUSPENS — ou — TRANCHÉ le AAAA-MM-JJ → résultat.
```

---

## 2026-08-19 — Le serveur d'échecs n'est pas encore déployé ni éprouvé en réel

**Origine :** le serveur et le client sont vérifiés de bout en bout, mais uniquement contre un serveur local (`127.0.0.1`). Le VPS n'a pas pu être joint : Tailscale est arrêté sur le poste de Dova.
**Risque :** tout ce qui ne peut se manifester qu'en vrai reste devant nous — port fermé par le pare-feu de l'hébergeur, service qui ne redémarre pas au reboot, latence qui rend le délai de 7 s trop court, adresse publique qui change.
**À vérifier ou trancher :** relancer Tailscale, déposer le service sur le VPS, ouvrir le port, puis jouer un vrai coup depuis deux machines différentes. Tant que ce parcours n'a pas été joué en réel, la fonctionnalité n'est pas livrée.
**Statut :** PARTIELLEMENT TRANCHÉ le 2026-08-19. Tailscale s'est révélé inutile : le VPS répond sur son IP publique. Le service est déployé, actif, relancé au démarrage, en HTTPS sur 8137 ; `ufw` est inactif et aucun pare-feu d'hébergeur ne bloque le port — vérifié depuis ce poste, pas supposé. Le client s'y connecte réellement, l'épinglage y refuse une mauvaise empreinte et le serveur y refuse un mauvais code. **Reste en suspens :** une partie jouée à deux depuis deux machines différentes.

## 2026-08-19 — La liaison avec le serveur d'échecs est en clair

**Origine :** décision du 2026-08-19 (service HTTP public + code partagé), prise pour que Nisse n'ait rien à installer.
**Risque :** le code partagé circule en clair sur Internet. Quiconque observe le réseau entre un joueur et le serveur peut le lire, et donc jouer à la place de l'un des deux. Aucune donnée personnelle n'est en jeu — l'enjeu se limite à la partie d'échecs et à l'écriture dans le fichier d'état du serveur.
**À vérifier ou trancher :** est-ce que ça reste acceptable ? Si non, deux réponses possibles sans rien changer au client : un reverse-proxy TLS devant le service (Caddy, une ligne de configuration), ou le repli sur Tailscale.
**Statut :** TRANCHÉ le 2026-08-19 → **non, ce n'était pas acceptable** (décision de Dova). La liaison est désormais en TLS, avec un certificat auto-signé épinglé côté client à la première connexion. Ni le code ni les coups ne circulent en clair. Il reste une porte étroite : le tout premier échange, avant que l'empreinte ne soit notée — elle ne se fermerait qu'avec un vrai certificat, donc un nom de domaine, écarté volontairement. Éprouvé par `scripts/Test-Epinglage.ps1` (27 contrôles, dont le refus effectif d'un certificat qui change).

## 2026-08-19 — Le code partagé est stocké en clair dans config.json

**Origine :** le dialogue de connexion enregistre l'adresse et le code dans `config.json`, à côté de la position de la barre.
**Risque :** toute personne ayant accès au poste peut lire le code. `config.json` est ignoré par git (vérifié), donc il ne peut pas partir sur GitHub par accident — c'est le point le plus dangereux et il est fermé.
**À vérifier ou trancher :** vu l'enjeu (jouer aux échecs), un chiffrement par DPAPI serait probablement disproportionné. À rouvrir seulement si le même serveur devait porter autre chose que des parties d'échecs.
**Statut :** EN SUSPENS — jugé proportionné.

## 2026-08-19 — La zone cliquable du pion est celle de ses pixels pleins

**Origine :** la fenêtre de la barre utilise une couleur de transparence ; les pixels transparents ne reçoivent aucun clic, ils le laissent passer à la fenêtre du dessous.
**Risque :** un clic visant un creux du pion (entre la tête et la base) ne fait rien du tout, ce qui donne l'impression d'un bouton capricieux.
**À vérifier ou trancher :** à l'usage. Si c'est agaçant, la parade est de peindre les creux dans une couleur à un point de la couleur de transparence — visuellement identique, mais opaque donc cliquable.
**Statut :** EN SUSPENS.
