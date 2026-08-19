#!/usr/bin/env node
// ===========================================================================
//  echecs-serveur.js — la boîte aux lettres de la partie.
//
//  Volontairement IGNORANT des règles du jeu. Il ne sait ni ce qu'est un
//  roque ni ce qu'est un mat : il tient une liste ordonnée de coups, et
//  refuse qu'un joueur écrive deux fois de suite. Les règles sont vérifiées
//  par les deux clients, qui rejouent la liste dans leur propre moteur.
//
//  Pourquoi : écrire un second moteur d'échecs ici obligerait à maintenir
//  deux implémentations en accord parfait. La première divergence entre les
//  deux produirait des parties impossibles à débloquer.
//
//  Aucune dépendance : seulement les modules livrés avec Node.
//
//  Configuration, par variables d'environnement, sans valeur par défaut
//  cachée pour le secret :
//     ECHECS_CODE   le code partagé entre les deux joueurs   (OBLIGATOIRE)
//     ECHECS_PORT   port d'écoute                            (défaut 8137)
//     ECHECS_ETAT   fichier d'état JSON                      (défaut ./etat.json)
//     ECHECS_HOTE   interface d'écoute                       (défaut 0.0.0.0)
// ===========================================================================

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CODE = process.env.ECHECS_CODE;
const PORT = parseInt(process.env.ECHECS_PORT || '8137', 10);
const HOTE = process.env.ECHECS_HOTE || '0.0.0.0';
const ETAT = process.env.ECHECS_ETAT || path.join(__dirname, 'etat.json');

// Un secret n'a pas de valeur de repli. Démarrer sans code produirait un
// serveur ouvert à tout Internet, et rien à l'écran ne le dirait.
if (!CODE || CODE.length < 6) {
  console.error('ECHECS_CODE manquant ou trop court (6 caracteres minimum).');
  process.exit(2);
}

const CORPS_MAX = 64 * 1024;      // au-delà, la requête est coupée
const REQ_PAR_MINUTE = 120;       // par adresse IP

// ---------------------------------------------------------------------------
//  État
// ---------------------------------------------------------------------------

function etatNeuf(joueurBlanc, joueurNoir, scores) {
  return {
    partieId: new Date().toISOString().replace(/[:.]/g, '-'),
    joueurs: { w: joueurBlanc, b: joueurNoir },
    coups: [],
    termine: false,
    resultat: '',
    scores: scores || {},
    majUtc: new Date().toISOString(),
  };
}

function lireEtat() {
  try {
    const brut = fs.readFileSync(ETAT, 'utf8');
    const e = JSON.parse(brut);
    if (!Array.isArray(e.coups)) throw new Error('coups absent');
    return e;
  } catch (err) {
    return null;
  }
}

function ecrireEtat(e) {
  e.majUtc = new Date().toISOString();
  // Écriture en deux temps : un fichier temporaire puis un renommage. Une
  // coupure pendant l'écriture laisserait sinon un JSON tronqué, donc une
  // partie perdue au lieu d'une partie non enregistrée.
  const tmp = ETAT + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(e, null, 2), 'utf8');
  fs.renameSync(tmp, ETAT);
}

// La couleur au trait se déduit du nombre de coups joués : pair = blancs.
// C'est la seule « règle » que le serveur connaisse, et elle est vraie pour
// toute partie d'échecs sans avoir à comprendre les pièces.
function couleurAuTrait(e) {
  return e.coups.length % 2 === 0 ? 'w' : 'b';
}

function couleurDe(e, joueur) {
  if (e.joueurs.w === joueur) return 'w';
  if (e.joueurs.b === joueur) return 'b';
  return null;
}

// ---------------------------------------------------------------------------
//  Garde-fous
// ---------------------------------------------------------------------------

const compteurs = new Map();

function tropDeRequetes(ip) {
  const maintenant = Date.now();
  let c = compteurs.get(ip);
  if (!c || maintenant > c.finFenetre) {
    c = { n: 0, finFenetre: maintenant + 60000 };
    compteurs.set(ip, c);
  }
  c.n += 1;
  // Ménage : sans ça la table grossit indéfiniment sur un serveur exposé.
  if (compteurs.size > 5000) {
    for (const [cle, val] of compteurs) {
      if (maintenant > val.finFenetre) compteurs.delete(cle);
    }
  }
  return c.n > REQ_PAR_MINUTE;
}

function codeValide(fourni) {
  if (typeof fourni !== 'string') return false;
  // Comparaison à temps constant, sur des empreintes de même longueur : une
  // comparaison de chaînes ordinaire fuite la longueur du secret.
  const a = crypto.createHash('sha256').update(fourni).digest();
  const b = crypto.createHash('sha256').update(CODE).digest();
  return crypto.timingSafeEqual(a, b);
}

function nomValide(n) {
  return typeof n === 'string' && /^[A-Za-z0-9 _.-]{1,32}$/.test(n);
}

function coupValide(c) {
  // Notation UCI : deux cases, plus éventuellement la pièce de promotion.
  return typeof c === 'string' && /^[a-h][1-8][a-h][1-8][nbrq]?$/.test(c);
}

// ---------------------------------------------------------------------------
//  Requêtes
// ---------------------------------------------------------------------------

function repondre(res, code, objet) {
  const corps = JSON.stringify(objet);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(corps),
    'Cache-Control': 'no-store',
  });
  res.end(corps);
}

function traiter(chemin, d, res) {
  let e = lireEtat();

  if (chemin === '/etat') {
    if (!e) {
      e = etatNeuf(d.joueur, 'adversaire', {});
      ecrireEtat(e);
    }
    return repondre(res, 200, { ok: true, etat: e });
  }

  if (!e) return repondre(res, 409, { ok: false, erreur: 'aucune partie en cours' });

  if (chemin === '/coup') {
    if (!coupValide(d.coup)) return repondre(res, 400, { ok: false, erreur: 'coup malforme' });
    if (e.termine) return repondre(res, 409, { ok: false, erreur: 'partie terminee', etat: e });

    const couleur = couleurDe(e, d.joueur);
    if (!couleur) return repondre(res, 403, { ok: false, erreur: 'joueur inconnu de cette partie', etat: e });
    if (couleur !== couleurAuTrait(e)) {
      return repondre(res, 409, { ok: false, erreur: 'ce n est pas ton tour', etat: e });
    }
    // Contrôle de version : le client annonce combien de coups il avait vus.
    // S'ils ne correspondent pas, c'est qu'il a joué sur une position perimee.
    if (typeof d.apresVersion === 'number' && d.apresVersion !== e.coups.length) {
      return repondre(res, 409, { ok: false, erreur: 'position perimee', etat: e });
    }

    e.coups.push(d.coup);
    if (d.resultat === '1-0' || d.resultat === '0-1' || d.resultat === '1/2-1/2') {
      e.termine = true;
      e.resultat = d.resultat;
      appliquerScore(e);
    }
    ecrireEtat(e);
    return repondre(res, 200, { ok: true, etat: e });
  }

  if (chemin === '/abandon') {
    const couleur = couleurDe(e, d.joueur);
    if (!couleur) return repondre(res, 403, { ok: false, erreur: 'joueur inconnu', etat: e });
    if (e.termine) return repondre(res, 200, { ok: true, etat: e });
    e.termine = true;
    e.resultat = couleur === 'w' ? '0-1' : '1-0';
    e.abandon = d.joueur;
    appliquerScore(e);
    ecrireEtat(e);
    return repondre(res, 200, { ok: true, etat: e });
  }

  if (chemin === '/nouvelle') {
    if (!e.termine && e.coups.length > 0) {
      return repondre(res, 409, { ok: false, erreur: 'la partie en cours n est pas finie', etat: e });
    }
    // Alternance des couleurs d'une partie à l'autre, comme demandé.
    const neuf = etatNeuf(e.joueurs.b, e.joueurs.w, e.scores);
    ecrireEtat(neuf);
    return repondre(res, 200, { ok: true, etat: neuf });
  }

  if (chemin === '/rejoindre') {
    // Le second joueur se présente : il prend la place libre.
    if (!nomValide(d.joueur)) return repondre(res, 400, { ok: false, erreur: 'nom invalide' });
    if (couleurDe(e, d.joueur)) return repondre(res, 200, { ok: true, etat: e });
    if (e.coups.length > 0) {
      return repondre(res, 409, { ok: false, erreur: 'partie deja engagee', etat: e });
    }
    if (e.joueurs.b === 'adversaire') { e.joueurs.b = d.joueur; }
    else if (e.joueurs.w === 'adversaire') { e.joueurs.w = d.joueur; }
    else return repondre(res, 409, { ok: false, erreur: 'les deux places sont prises', etat: e });
    ecrireEtat(e);
    return repondre(res, 200, { ok: true, etat: e });
  }

  return repondre(res, 404, { ok: false, erreur: 'inconnu' });
}

function appliquerScore(e) {
  const w = e.joueurs.w, b = e.joueurs.b;
  if (!e.scores[w]) e.scores[w] = 0;
  if (!e.scores[b]) e.scores[b] = 0;
  if (e.resultat === '1-0') e.scores[w] += 1;
  else if (e.resultat === '0-1') e.scores[b] += 1;
  else if (e.resultat === '1/2-1/2') { e.scores[w] += 0.5; e.scores[b] += 0.5; }
}

const serveur = http.createServer((req, res) => {
  const ip = req.socket.remoteAddress || 'inconnue';
  if (tropDeRequetes(ip)) return repondre(res, 429, { ok: false, erreur: 'trop de requetes' });
  if (req.method !== 'POST') return repondre(res, 404, { ok: false, erreur: 'inconnu' });

  const chemin = (req.url || '').split('?')[0];

  let corps = '';
  let coupe = false;
  req.on('data', (bloc) => {
    corps += bloc;
    if (corps.length > CORPS_MAX) { coupe = true; req.destroy(); }
  });
  req.on('end', () => {
    if (coupe) return;
    let d;
    try { d = JSON.parse(corps || '{}'); } catch (err) {
      return repondre(res, 400, { ok: false, erreur: 'json invalide' });
    }
    if (!codeValide(d.code)) return repondre(res, 401, { ok: false, erreur: 'code refuse' });
    if (!nomValide(d.joueur)) return repondre(res, 400, { ok: false, erreur: 'nom de joueur invalide' });
    try { traiter(chemin, d, res); } catch (err) {
      console.error('erreur:', err && err.stack ? err.stack : err);
      repondre(res, 500, { ok: false, erreur: 'erreur interne' });
    }
  });
});

serveur.listen(PORT, HOTE, () => {
  console.log('echecs-serveur en ecoute sur ' + HOTE + ':' + PORT);
  console.log('etat : ' + ETAT);
});
