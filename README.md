# 🎮 TokenBar — jauge de consommation Claude

Une petite **barre d'XP façon jeu vidéo** qui affiche ta consommation Claude
(limite **« Session 5h »**) en direct, flottante en haut à droite de l'écran,
**uniquement quand VS Code est ta fenêtre active**.

![Aperçu de la barre](preview.png)

La jauge se remplit du **vert** (0 %) au **rouge** (100 %), avec le pourcentage
à droite. Au **survol**, elle affiche le temps restant avant la remise à zéro
et ta consommation hebdomadaire.

---

## 📥 Installation (Windows) — un seul fichier

1. **[⬇️ Télécharge TokenBar-Installer.bat](../../releases/latest/download/TokenBar-Installer.bat)**
   — le clic lance le téléchargement directement, ce lien pointe toujours sur
   la dernière version.
2. **Double-clique dessus.**
3. Si Windows affiche un écran bleu *« Windows a protégé votre ordinateur »* :
   **Informations complémentaires → Exécuter quand même**
   *(normal pour un fichier venu d'internet — il est sain, le code est juste
   au-dessus dans ce dépôt).*
4. C'est tout : la barre se lance immédiatement, une icône est posée sur ton
   Bureau, et elle redémarrera automatiquement avec Windows. Ouvre VS Code
   pour la voir apparaître en haut à droite. ✅

Pas de ZIP à extraire, pas de dossier à fouiller : un fichier, un double-clic.
Pour désinstaller : **[⬇️ Télécharge Desinstaller.bat](../../releases/latest/download/Desinstaller.bat)**.

---

## ✨ Fonctionnalités

- ❤️ Cœur pixel 8-bit + jauge fine à contour noir, dégradé progressif vert → rouge.
- 📊 **Vraie donnée officielle** (identique au site claude.ai et au panneau
  « Account & Usage » de VS Code) : lue en local, aucun mot de passe demandé.
- 👀 Visible **seulement quand VS Code est actif** (disparaît quand tu changes de fenêtre).
- ⏱️ Survol → temps avant reset + conso hebdomadaire. Glisser → déplacer.
  Clic → rafraîchir. Clic droit → menu.
- 🚀 Démarrage automatique avec Windows + icône sur le Bureau, comme un vrai logiciel.
- 🔌 **S'adapte tout seul à ton compte** (Pro ou Max) : aucune config, aucune limite à saisir.
- 🪶 **Légère** : moins de 5 % d'un cœur CPU même en session active (cache
  incrémental — elle ne relit jamais deux fois les mêmes données).

---

## ⚙️ Comment ça marche

Claude Code stocke ta consommation réelle en local dans
`~/.claude.json` (champ `cachedUsageUtilization`). La barre lit ce fichier et
surveille sa date de modification pour se mettre à jour **dans la seconde**
dès que Claude Code y écrit une nouvelle valeur.

> ℹ️ Le chiffre avance **par paliers de quelques minutes** : c'est Claude Code
> qui rafraîchit sa donnée de temps en temps (exactement comme le panneau
> officiel de VS Code). Si le % reste figé un moment, c'est simplement qu'il
> n'y a pas eu de nouvelle consommation.

---

## 📋 Prérequis

- **Windows** (10 / 11) — utilise PowerShell + WinForms (déjà inclus, rien à installer).
- **VS Code** avec **Claude Code**, **connecté à ton compte** (`claude` → `/login`).
  C'est lui qui fournit le chiffre officiel.

> 🔌 **Aucune configuration de compte.** La barre lit automatiquement le compte
> connecté à Claude Code — **Pro ou Max**, peu importe. La limite en tokens
> diffère selon le plan : la barre l'**apprend toute seule** en quelques
> rafraîchissements et s'y cale (aucun réglage manuel).

---

## 🛠️ Structure

Pour juste **utiliser** TokenBar, un seul fichier suffit :
[`TokenBar-Installer.bat`](../../releases/latest/download/TokenBar-Installer.bat).
Tout ce qui suit, c'est le code source pour les curieux (ou pour bidouiller) :

| Fichier | Rôle |
|---|---|
| `TokenBar.ps1` | La barre (interface graphique). |
| `Get-TokenUsage.ps1` | Lecture de la conso officielle (+ repli local). |
| `Start-TokenBar.vbs` | Lanceur silencieux (sans fenêtre console). |
| `Install-Autostart.ps1` | Active/retire le démarrage automatique + raccourcis. |
| `TokenBar.ico` | Icône (Bureau, démarrage, fenêtre). |
| `Installer.bat` / `Desinstaller.bat` | Installation/désinstallation depuis une copie locale du dépôt. |
| `Build-Installer.ps1` | Génère `TokenBar-Installer.bat` (empaquette les fichiers ci-dessus en un seul, à relancer après toute modification). |

> 🕯️ Ce tableau est incomplet, et ce n'est pas un oubli. TokenBar sait faire
> autre chose que compter des tokens — mais il ne le dira à personne tant
> qu'on ne le lui aura pas demandé comme il faut.

---

## 📄 Licence

MIT — fais-en ce que tu veux. 🙂
