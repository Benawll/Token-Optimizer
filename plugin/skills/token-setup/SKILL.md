---
name: token-setup
description: Audite, détecte les stacks (multi-stack généraliste) et synchronise sans perte .antigravityignore et GEMINI.md (< 2 KB) pour éliminer les fuites de tokens sur tout projet Antigravity.
---

# Skill : `token-setup`

Regroupe en une seule skill sans doublon la détection de stack, l'audit de workspace et la synchronisation sans perte des exclusions et règles projet.

## Commandes (`<skill_dir>` = dossier de ce `SKILL.md`)

1. **Audit complet d'un projet** (`.antigravityignore`, budget règles 24 KB / 20k tokens, top 15 gros fichiers exposés, MCP globaux) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\setup-workspace.ps1" -WorkspacePath "<workspace_root>" -Mode audit
   ```

2. **Prévisualiser la synchronisation `.antigravityignore` & règles** (dry-run) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\setup-workspace.ps1" -WorkspacePath "<workspace_root>" -Mode sync
   ```

3. **Appliquer la synchronisation sans perte** (crée `.antigravityignore` ou ajoute uniquement les motifs des nouvelles stacks sans jamais écraser les règles existantes) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\setup-workspace.ps1" -WorkspacePath "<workspace_root>" -Mode sync -Apply
   ```

## Bonnes pratiques
- Ne jamais ouvrir ni lire le contenu complet des gros fichiers détectés par `-Mode audit`.
- Garder `GEMINI.md` / `AGENTS.md` **100 % statique** et sous **2–4 KB** (ne pas répéter les règles globales déjà fournies par le plugin `token-optimizer`).
