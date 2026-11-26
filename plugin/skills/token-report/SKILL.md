---
name: token-report
description: Analyse les transcripts locaux d'Antigravity (transcript.jsonl) pour mesurer la consommation réelle par modèle, générer un dashboard visuel HTML, préparer un handoff de session compact et archiver localement les vieilles sessions.
---

# Skill : `token-report`

Produit un bilan chiffré de l'utilisation réelle des tokens sur vos conversations Antigravity locales.

## Procédure

1. **Analyse JSON rapide** (remplacez `<skill_dir>` par le dossier contenant ce `SKILL.md`) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\report-tokens.ps1" -Latest 10
   ```
   *(Ajoutez `-ConversationId "<uuid>"` pour cibler une session précise.)*

2. **Générer et ouvrir le mini-dashboard visuel HTML** (0 token modèle, généré dans `%TEMP%` pour ne jamais polluer le plugin avec vos données personnelles) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\generate-dashboard.ps1" -Latest 15 -Open
   ```
   Donnez ensuite un lien cliquable `file:///...` vers le fichier HTML généré.

3. **Faire un Handoff (< 300 tokens) et créer la nouvelle conversation** avant de fermer une session marathon :
   - Quand l'utilisateur demande de **faire un handoff**, **créer automatiquement la nouvelle conversation** avec `-CreateConversation` (ne proposer le copier-coller qu'en fallback si `ANTIGRAVITY_LS_ADDRESS` est indisponible), puis donner un lien cliquable `[Nouvelle session](conversation://<newConversationId>)` :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\handoff-session.ps1" -ConversationId "<uuid>" -CreateConversation -NextStep "<prochaine étape>"
   ```
   *(Ou appeler `ConversationService/CreateConversation` avec `$env:ANTIGRAVITY_PROJECT_ID` selon le skill `conversations` si vous passez un résumé personnalisé via `-PromptText`.)*

4. **Archivage local optionnel (disque & fluidité UI uniquement)** :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\archive-sessions.ps1" -OlderThanDays 30
   ```
   *(Ajoutez `-Apply` uniquement sur demande explicite. L'archivage ne crée **pas** de nouvelle conversation : pour démarrer un sujet indépendant, ouvrez simplement un nouveau chat vierge.)*
