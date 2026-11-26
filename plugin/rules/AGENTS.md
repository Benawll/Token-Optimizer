# Token Optimizer Rules

1. **Batch parallel calls**: Issue independent searches, file reads, and edits in parallel in a single turn.
2. **Search before reading**: Locate targets with `rg`/grep first, then read bounded line ranges (`StartLine`/`EndLine`) unless the file is under 200 lines. Never dump whole directories or lockfiles.
3. **Surgical edits**: Use targeted `edit_file` diffs. Never reprint unchanged file sections in responses or tool calls.
4. **Quiet CLI output**: Chain dependent commands with `&&`. Pass quiet flags (`-q`, `--quiet`, `--silent`, `--no-progress`) and cap verbose output (`| Select-Object -Last 50` / `| tail -n 50`).
5. **Isolate noisy tasks**: Réserver les sous-agents (`research`, `browser`) aux **explorations massives ponctuelles** (`5+` fichiers, gros logs, navigation web). Jamais pour une lecture simple (un sous-agent repart à 0 % de cache).
6. **Concise output, full rigor**: Skip pleasantries and prompt restatements. Never skip required tests, builds, or verification steps.
7. **Stabilité Cache & Modèle (`1 session = 1 modèle + 1 niveau de raisonnement`)** : À chaque consigne utilisateur, afficher et prononcer en tout début de réponse le badge strict :
   `[Audit Modèle : Modèle Actif | Thinking: Low/Medium/High | Statut: ✅ Optimal ou ⚠️ Nouvelle session recommandée]`
   - **Verbalisation orale obligatoire (Voice/Live)** : Prononcer explicitement à haute voix la première phrase (ex. : *"Modèle Neon Medium validé."*).
   - **Interdiction de switch en milieu de fil** : Changer de modèle ou d'effort (`Low`/`Medium`/`High`) sur une session en cours casse 100 % du cache implicite (~5× plus cher). Ne jamais recommander de basculer en plein fil : si un autre palier est préférable, ou après une **pause > 5 minutes** (*5-min implicit cache cliff*) sur un gros fil (`> 40k`), recommander d'ouvrir une **nouvelle session ciblée** (ou `/compact` / `handoff`).
   - Éviter aussi d'éditer `AGENTS.md`/`GEMINI.md` ou de réinstaller le plugin au milieu d'une session active.
   - Guide de choix **au démarrage d'une nouvelle session uniquement** :
     - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Low`): Single-file edits, CLI runs, tests, formatting, audits/scans.
     - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Medium`): Routine feature coding, multi-step scripts, standard API logic.
     - `Orchestrator` / `Gemini 4 Neon` (`Medium`/`High`): Multi-file refactorings, deep architectural redesigns, complex root-cause forensics.
8. **Workflow Économe en 5 Étapes — Porte Obligatoire (Commandes slash)** :
   - **Étape 1 — Porte `/grill-me` (OBLIGATOIRE avant d'éditer)** : Pour toute demande de refonte, design UI/UX, architecture ou chantier multi-fichiers dont les choix ne sont pas encore verrouillés, **ne jamais commencer à coder directement** — proposer explicitement `/grill-me` (ou poser 3 questions de cadrage concises) avant le premier `write_file`/`edit_file`.
   - **Étape 2 (Build)** : Suivre l'arbitrage du badge (Flash / Hydrogen / Orchestrator).
   - **Étape 3 — Porte `/btw` (Questions & Détours)** : Sur toute question rapide hors-sujet en milieu de session, rappeler `/btw` en 1 ligne (sans alourdir la réponse) et déléguer la navigation web à `/browser`.
   - **Étape 4 (Itération massive)** : Recommander `/swarm` quand plusieurs chantiers parallèles peuvent être distribués.
   - **Étape 5 (Clôture)** : Livrer sur Git et suggérer `/automation` pour pérenniser les tâches récurrentes.
