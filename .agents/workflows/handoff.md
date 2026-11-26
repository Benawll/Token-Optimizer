---
description: Sauvegarde l'état de la session dans .agents/STATUS.md (< 400 tokens) et fournit le prompt de reprise sans créer de nouvelle session.
---

# Workflow `/handoff` (déterministe, sans création de session)

Exécute **uniquement** ces 3 actions dans la conversation actuelle, puis rends la main immédiatement.
**Interdiction absolue** d'appeler un outil de création ou d'ouverture de nouvelle conversation.

1. **Écrire ou mettre à jour `.agents/STATUS.md`** (format ultra-concis, **< 400 tokens**) avec exactement ces 6 sections :
   - `## Objectif en cours` (1–2 lignes)
   - `## Fichiers modifiés` (liste courte des chemins)
   - `## Décisions prises` (puces courtes)
   - `## État des tests/builds` (résultat exact vérifié ou `non exécuté`)
   - `## Prochaine action immédiate` (1 action concrète)
   - `## Modèle recommandé` : préciser `Gemini 4 Hydrogen (Medium)` si la suite est du code, `Gemini 4 Hydrogen (Low)` si mécanique/vérification, ou `Gemini 4 Neon (Medium)` uniquement sur blocage architectural complexe.

2. **Recommander le modèle de la session suivante** dans le chat en une seule ligne (cohérente avec `## Modèle recommandé` dans `.agents/STATUS.md`) :
   - `Gemini 4 Hydrogen (Medium)` si la suite est du code.
   - `Gemini 4 Hydrogen (Low)` si la suite est mécanique/vérification.
   - `Gemini 4 Neon (Medium)` **uniquement** s'il reste un blocage architectural complexe.

3. **Afficher dans le chat le prompt prêt à copier-coller** pour la nouvelle session :
   ```text
   Lis .agents/STATUS.md et exécute la prochaine action immédiate.
   ```
