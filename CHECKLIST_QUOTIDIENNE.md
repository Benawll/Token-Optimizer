# Checklist Quotidienne — Antigravity Token Optimizer

> Référence rapide 1 page pour garder une consommation minimale sans perdre en qualité sur **Orchestrator**, **Neon** et **Hydrogen**.

---

## 1. Choix du modèle en 10 secondes

* **Tâche mécanique / simple** (renommage, doc, formatage, test unitaire isolé) $\rightarrow$ **Hydrogen (`low` / `medium`)**
* **Travail quotidien** (feature, refactor multi-fichiers, bug standard) $\rightarrow$ **Orchestrator (Neon `medium` + Hydrogen)**
* **Architecture, sécurité, concurrence, debug ardu** $\rightarrow$ **Neon (`high`)**
* **Blocage persistant après échec en `high`** $\rightarrow$ **Neon (`xhigh`)** *(exceptionnel uniquement)*

---

## 2. Réflexes pendant chaque tâche

### Avant d'envoyer le 1er prompt
- [ ] **Pointer avec `@`** les fichiers/dossiers exacts concernés (évite les tours d'exploration).
- [ ] **Formuler un prompt complet** : objectif + contraintes + commande de test attendue.
- [ ] **Tâche complexe ou ambiguë ?** Lancer **`/plan`** ou **`/grill-me`** avant le code pour éviter le rework.
- [ ] **Données volumineuses en entrée ?** Préférer table Markdown, YAML ou TOON au JSON verbeux.

### Pendant l'exécution
- [ ] **Sorties CLI silencieuses :** Vérifier que les tests/builds tournent avec `-q` / `--quiet` ou limités aux dernières lignes d'erreur.
- [ ] **Exploration lourde ou navigation web :** Laisser un **subagent** (`research` ou `browser` sur `flash`) isoler le bruit.
- [ ] **Piste risquée / expérimentale :** Lancer **`/fork`** avant de tester, puis **`/resume`** si la piste est mauvaise.
- [ ] **Session qui s'allonge :** Exécuter **`/compact`** dès que le fil dépasse 10–15 échanges chargés.

### Fin de tâche
- [ ] **1 tâche validée = Nouvelle session** pour la tâche suivante (coupe l'effet boule de neige).

---

## 3. Hygiène du projet (vérification hebdomadaire)

- [ ] **`.antigravityignore`** à jour (exclusions : `node_modules/`, `dist/`, `build/`, `target/`, lockfiles, logs, sourcemaps, médias).
- [ ] **`GEMINI.md` / `AGENTS.md` < 2–4 KB** (loin de la limite de 24 KB par fichier et du budget global de 20 000 tokens).
- [ ] **Aucune donnée dynamique** (date, compteur, état live) au début de `GEMINI.md` ou des prompts système $\rightarrow$ préserve le **caching implicite (-95%)**.
- [ ] **Procédures multi-étapes** rangées dans `.agents/skills/*/SKILL.md` (chargées à la demande).
- [ ] **Serveurs MCP inutilisés désactivés** dans les paramètres globaux ou scopés par plugin projet.
