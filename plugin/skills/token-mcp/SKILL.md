---
name: token-mcp
description: Gère des profils de serveurs MCP (minimal, gamedev, full, none) avec sauvegarde complète afin de supprimer la taxe de schémas MCP inutilisés sur les projets non-3D/Unity.
---

# Skill : `token-mcp`

Chaque serveur MCP actif injecte les schémas de tous ses outils dans le prompt système **à chaque tour**. Cette skill permet de basculer proprement vers un profil adapté au projet courant sans jamais perdre votre configuration d'origine.

## Commandes

1. **Vérifier l'état et le profil recommandé** (lecture seule) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\mcp-profile.ps1" -Action status -WorkspacePath "<workspace_root>"
   ```

2. **Basculer automatiquement selon les stacks du projet** (`gamedev` si Unity/Blender détecté, sinon `minimal`) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\mcp-profile.ps1" -Action auto -WorkspacePath "<workspace_root>"
   ```

3. **Choisir un profil explicite** (`minimal`, `gamedev`, `full`, `none`) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\mcp-profile.ps1" -Action switch -Profile full
   ```

> [!NOTE]
> La sauvegarde complète est conservée dans `~/.gemini/config/mcp_profiles/full-catalog.json` pour restaurer `full` à tout moment. Demandez confirmation à l'utilisateur avant d'exécuter `-Action auto` ou `-Action switch`, et précisez que la prise en compte intervient au rechargement / nouvelle session.
