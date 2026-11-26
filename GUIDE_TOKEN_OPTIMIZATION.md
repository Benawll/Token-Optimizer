# Guide Complet : Économiser des Tokens sur Google Antigravity (Hydrogen & Neon)

Ce guide recense les **meilleures méthodes éprouvées** pour réduire drastiquement votre consommation de tokens (et préserver vos quotas) sur **Google Antigravity** avec la famille **Gemini 4** (`Hydrogen` et `Neon`), tout en conservant **un maximum de performance et de fiabilité**.

---

## 1. Économie des tokens sur Gemini 4 & Antigravity (Les fondamentaux)

Avant d'optimiser, il faut comprendre **ce qui coûte réellement des tokens** dans Antigravity : ce n'est pas la longueur de votre prompt initial, mais le **travail agentique** (fichiers indexés/lus, schémas d'outils, historique ré-envoyé à chaque tour, et *thinking tokens* facturés en sortie).

### Tarification & mécanique des modèles

| Modèle / Mode | Rôle optimal | Input (1M tokens) | Output (1M tokens) | Input mis en cache | Gain / Impact |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Gemini 4 Hydrogen** | Défaut quotidien (`Medium` pour coder, `Low` pour le mécanique) | \$1.50 | \$7.50 | — | 2× moins cher que Neon (dispo aussi sur les tiers gratuits) |
| **Gemini 4 Neon** | Planification, architecture, revue, blocage complexe (`Medium`) | \$3.00 | \$15.00 | **\$0.15 (-95%)** | Raisonnement frontier (`low` à `xhigh`) |
| **Orchestrator (Neon + Hydrogen)** | Tâches courtes uniquement *(à éviter sur les sessions longues)* | Routage dynamique | Routage dynamique | Inclus | Ses bascules internes cassent le cache > 40k tokens |

### Trois règles économiques majeures

1. **Ratio 5:1 Output / Input :** Les tokens générés en sortie coûtent **5× plus cher** que les tokens en entrée. Sur Gemini 4, les **thinking tokens** (raisonnement interne) sont comptabilisés et facturés au **tarif output**.
2. **Fenêtre de contexte unifiée (1 048 576 tokens) :** L'entrée, le raisonnement interne et la sortie partagent **le même pool** d'1M de tokens. Des logs géants ou des sorties verbeuses compriment directement l'espace utile.
3. **Effet boule de neige quadratique :** Chaque tour d'une conversation ré-envoie l'intégralité de l'historique (messages + résultats d'outils + snapshots). Une session de 30 tours coûte exponentiellement plus cher qu'une session ciblée de 6 tours — et dégrade la précision (*context rot*).

---

## 2. Niveau 1 : Optimisations à ZÉRO perte de performance (Gains purs)

Ces techniques n'altèrent jamais la qualité du code ou du raisonnement : elles suppriment uniquement le gaspillage structurel.

### 1) Exploiter le Prompt Caching Implicite (-95% sur l'input)
Sur Gemini 4, le caching de contexte est **automatique et implicite** dès qu'un préfixe partagé atteint **4 096 tokens** (jusqu'à **-95%** sur le coût input sur Neon : \$0.15/M au lieu de \$3.00/M).

* **Règle d'or — Préfixe 100% statique :** Placez tout ce qui ne change pas au **tout début** du contexte (instructions système, `GEMINI.md`, documentation de référence, schémas stables) et rejetez tout élément dynamique (date/heure, timestamps, UUID, état runtime, logs variables) à la **fin**. Un seul timestamp qui change en début de prompt invalide tout le cache !
* **Supprimez le cache explicite hérité (SDK/API) :** Les appels `client.caches.create()` et `cached_content=...` (Gemini 2.5 / 3.x) sont **dépréciés sur Gemini 4** et renvoient une erreur **HTTP 400** sur Neon et Hydrogen. Laissez le caching implicite travailler sans frais de stockage horaire.

### 2) Garder un modèle fixe par session (`1 session = 1 modèle`)
* **Pour coder :** utilisez **`Gemini 4 Hydrogen (Medium)`** par défaut (scripts, UI, features, debug).
* **Pour le mécanique :** utilisez **`Gemini 4 Hydrogen (Low)`** (Git, documentation, formatage, vérifications rapides).
* **Évitez `Orchestrator` sur les sessions longues :** ses bascules internes entre modèles cassent le préfixe de cache implicite dès que le contexte dépasse ~40k tokens.
* **Escalade propre :** en cas de blocage architectural complexe, lancez **`/handoff`** et ouvrez une nouvelle session sur **`Gemini 4 Neon (Medium)`**.

### 3) Filtrer le workspace avec `.antigravityignore`
Antigravity scanne et indexe votre espace de travail. Sans filtrage, les dépendances, builds et lockfiles consomment des dizaines de milliers de tokens en arrière-plan.

Créez un `.antigravityignore` à la racine du projet (voir le modèle prêt à l'emploi dans `templates/.antigravityignore`) pour exclure :
* Dépendances : `node_modules/`, `.venv/`, `venv/`, `vendor/`, `target/`
* Builds & caches : `dist/`, `build/`, `.next/`, `.nuxt/`, `__pycache__/`, `.pytest_cache/`, `coverage/`
* Lockfiles géants : `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `uv.lock`, `Cargo.lock`
* Artefacts lourds : `*.map`, `*.min.js`, `*.log`, médias/binaires, `.git/`

### 4) Cibler le contexte avec les mentions `@` et les lectures chirurgicales
* **Utilisez `@fichier` et `@dossier` :** Pointer explicitement le bon fichier dans votre prompt évite 3 à 5 tours de recherche aveugle (`grep`, listage de dossiers, lectures exploratoires).
* **Évitez le "Context Dump" :** Ne demandez jamais *"lis tous les fichiers de `src/` pour comprendre le projet"*. Demandez une recherche ciblée (`rg`), puis une lecture bornée sur les lignes utiles, et ne chargez un fichier entier que s'il est petit ou indispensable.

### 5) Réduire le nombre de tours : Batching & Chaînage Shell
Moins de tours = moins de ré-envois de l'historique.
* **Batching parallèle :** Encouragez l'agent (via `GEMINI.md`) à regrouper ses recherches, lectures et éditions indépendantes dans un **seul tour** plutôt que d'enchaîner 6 tours séquentiels.
* **Chaînage shell & sorties silencieuses :** Chaînez les commandes dépendantes avec `&&` et utilisez les options silencieuses (`--quiet`, `-q`, `--no-progress`, `--silent`) ou filtrez la sortie (`Select-Object -Last 50` / `tail -n 50`). Une commande `npm test` ou `cargo build` qui crache 3 000 lignes de logs dans le contexte pollue tous les tours suivants.

### 6) Disclosure Progressive : Rules vs. Skills & Budgets natifs
Antigravity applique des plafonds stricts sur les règles :
* **24 KB max par fichier de règle** (après expansion des inclusions `@[label](path)` — tronqué au-delà).
* **Budget agrégé de 20 000 tokens** partagé entre toutes les règles globales et `always_on` (`defaultRulesBudget`). Au-delà, les règles excédentaires sont rétrogradées en simples pointeurs que l'agent doit lire manuellement.

Pour économiser sans rien perdre :
* **Rules (`GEMINI.md`, `AGENTS.md`, `.agents/rules/*.md`) :** Réservez-les aux **invariants stricts** (stack, commandes test/build, interdits architecturaux). Gardez `GEMINI.md` sous **2 à 4 KB**.
* **Scoping des règles :** Placez les règles spécifiques d'un module dans son sous-dossier (`frontend/AGENTS.md`) ou utilisez le frontmatter YAML dans `.agents/rules/*.md` (`trigger: model_decision` ou `include_only` par glob) pour ne pas les charger hors contexte.
* **Skills (`.agents/skills/<nom>/SKILL.md`) :** Déplacez toutes les procédures multi-étapes (migrations DB, déploiement, audit, revue) dans des **Skills**. Antigravity n'injecte que leur nom et courte description par défaut (*progressive disclosure*) : le contenu complet n'est chargé que lorsque la tâche l'exige.

### 7) Élaguer les serveurs MCP et Plugins inutilisés (La "taxe de schémas")
Chaque serveur MCP actif injecte la définition JSON complète de **tous ses outils** dans le system prompt **à chaque tour**, même quand vous ne l'appelez pas. 3 ou 4 MCP lourds peuvent consommer plusieurs milliers de tokens fixes par tour.
* Désactivez les MCP et plugins globaux dont vous n'avez pas besoin au quotidien.
* Packagez les MCP spécifiques dans un **plugin projet** plutôt qu'en global (`~/.gemini/config/mcp_config.json`).
* Pour des actions simples (ex. interroger une base locale ou un utilitaire), préférez un **script CLI appelé via une Skill** plutôt qu'un serveur MCP permanent exposant 30 outils.

### 8) Isoler le bruit dans des Subagents
Les subagents (`research`, `browser`, ou personnalisés via `invoke_subagent`) s'exécutent dans une **fenêtre de contexte isolée**.
* Déléguez l'exploration large de codebase, l'analyse de gros logs ou la recherche documentaire au subagent `research`.
* Déléguez les interactions web au subagent `browser` (qui tourne par défaut sur **`flash`**, rapide et peu coûteux).
* Votre conversation principale ne reçoit que le **résumé propre**, jamais les dizaines d'étapes intermédiaires ni les captures DOM.

---

## 3. Niveau 2 : Calibration fine (Perte de performance quasi nulle)

### 9) Calibrer le Thinking Effort (`low` / `medium` / `high` / `xhigh`)
Sur Gemini 4, `Hydrogen` et `Neon` utilisent par défaut `high` (`Neon` supporte aussi `xhigh`). Or passer de `high` à `xhigh` n'apporte souvent qu'environ **+1%** sur les benchmarks tout en faisant exploser la latence et les **thinking tokens** (facturés au tarif output).

> [!NOTE]
> Sur Neon, les anciens paramètres de sampling (`temperature`, `top_p`, `top_k`) dans les plages standards sont ignorés côté serveur : pilotez le comportement via `thinking_level`.

#### Matrice de décision recommandée

| Type de tâche | Modèle recommandé | Thinking Effort | Pourquoi |
| :--- | :--- | :---: | :--- |
| Tâches mécaniques : Git, docs, renommages, vérifications rapides | **Hydrogen** | `low` | Coût minimal, vitesse maximale, zéro besoin de sur-réflexion |
| Développement quotidien (défaut) : coder, éditer scripts/UI, déboguer | **Hydrogen** | `medium` | **Meilleur ROI global** : rapide, fiable, cache stable sur toute la session |
| Planification, architecture système, ou blocage complexe après échec | **Neon** | `medium` | Jugement frontier ciblé (ouvrir via `/handoff`, éviter `Orchestrator` sur sessions longues) |
| Bug critique exceptionnel après échec en `Medium` | **Neon** | `high` | Dernier recours ciblé uniquement |

### 10) Gérer le contexte comme de la RAM : Sessions fraîches, `/handoff`, `/fork`
* **1 tâche = 1 session :** Dès qu'une feature ou un bug est terminé et validé, ouvrez une **nouvelle conversation**. Ne traînez pas l'historique d'hier sur la tâche d'aujourd'hui.
* **`/handoff` aux seuils `15/25/40` tours ou `60k/85k` tokens :** Dès qu'une conversation dépasse ces jalons (ou après > 5 min d'inactivité sur > 50k tokens), lancez `/handoff` pour sauvegarder l'état dans `.agents/STATUS.md` (< 400 tokens) et repartir sur un fil neuf (remplace `/compact`).
* **`/fork` + `/resume` :** Avant une tentative risquée ou exploratoire, lancez `/fork`. Si l'approche échoue, revenez sur la session d'origine avec `/resume` sans avoir pollué son contexte avec des impasses.

### 11) Éliminer le bruit en sortie (Anti-Fluff & Micro-Diffs)
* Exigez dans `GEMINI.md` des **réponses concises**, sans formules de politesse ni réexplication du code non modifié.
* Imposez des **éditions chirurgicales** (`edit_file` ciblé) au lieu de réécrire des fichiers entiers (`write_file` complet).
* **Attention :** Ne demandez *jamais* de supprimer les tests, les vérifications ou la réflexion utile — vous paieriez cette "économie" en tours de correction supplémentaires.

### 12) Prompting structuré & Formats compacts
* **Spécifiez dès le 1er message :** Objectif exact + `@fichiers` + contraintes + critère de validation (ex. *"exécute `pytest tests/test_auth.py -q`"*). Sur les tâches floues, lancez **`/plan`** ou **`/grill-me`** avant d'écrire une ligne de code : clarifier 2 minutes évite 10 tours de rework.
* **Formats compacts :** Pour injecter des tableaux de données ou schémas dans un prompt, préférez le **Markdown tabulaire**, le **YAML** ou le format **TOON** (*Token-Oriented Object Notation*, sans accolades ni guillemets redondants) plutôt que du JSON verbeux.

---

## 4. Niveau 3 : Automatisation & Garde-fous (`hooks.json`)

Antigravity permet d'intercepter le cycle de vie de l'agent via `.agents/hooks.json` :

1. **Préférez `SessionStart` à `PreInvocation` pour le contexte statique :** `SessionStart` injecte vos instructions une seule fois au début de la session et préserve votre **préfixe de cache**. Un hook `PreInvocation` qui injecterait des infos changeantes à chaque tour casserait le cache implicite.
2. **Filtrez les commandes bruyantes via `PreToolUse` (`run_command`) :** Vous pouvez vérifier qu'une commande de test/build ne génère pas une sortie illimitée ou bloquer des commandes coûteuses par erreur.
3. **Surveillez `MAX_TOKEN_BUDGET_EXCEEDED` dans `Stop` :** Pour les tâches autonomes longues (`/goal`, `/schedule`), utilisez l'événement `Stop` afin d'éviter les boucles infinies si le budget est atteint.

---

## 5. Anti-patterns à éviter (Les fausses économies qui coûtent PLUS cher)

1. **Sous-dimensionner ou casser le cache :** Envoyer `Hydrogen Low` sur un problème d'architecture ou laisser `Orchestrator` basculer de modèle sur une session longue (> 40k) consomme **2× à 3× plus de tokens** qu'une session fixe bien calibrée (`Hydrogen Medium` ou `Neon Medium`).
2. **Supprimer les règles utiles pour raccourcir `GEMINI.md` :** Un `GEMINI.md` trop vague provoque des erreurs de convention que vous devrez corriger sur plusieurs tours.
3. **Casser le cache préfixe :** Mettre l'heure courante, un compteur ou des données volatiles en haut de `GEMINI.md` ou du prompt système annule les **-95% de remise cache** sur Neon.
4. **Micro-lectures répétées :** Lire un fichier de 250 lignes en 5 appels de 50 lignes génère 5 tours d'API (et 5× le ré-envoi du contexte) au lieu d'un seul appel.
5. **Laisser 5 serveurs MCP activés "au cas où" :** Taxe permanente de plusieurs milliers de tokens à chaque tour.

---

## 6. Plan d'action d'implémentation (en 4 étapes)

1. **Quick Wins (10 min) :** Passez par défaut sur **`Gemini 4 Hydrogen (Medium)`** pour coder (**`Low`** pour le mécanique), désactivez les MCP globaux inutilisés et copiez `templates/.antigravityignore` à la racine de vos projets.
2. **Socle Projet (15 min) :** Adaptez `templates/GEMINI.md` (< 2 KB) à votre stack et vos commandes de test silencieuses.
3. **Workflow Équipe (30 min) :** Déplacez vos procédures répétitives dans `.agents/skills/` et scopez vos règles spécialisées dans `.agents/rules/` (`model_decision` ou glob).
4. **Hygiène & Automatisation (Continu) :** Appliquez la [CHECKLIST_QUOTIDIENNE.md](./CHECKLIST_QUOTIDIENNE.md) (mentions `@`, sessions fraîches, `/handoff` aux seuils `15/25/40` tours / `60k/85k` tok, `/fork`, délégation `research`/`browser`) et utilisez le plugin `token-optimizer` (ou `.agents/hooks.json`).
