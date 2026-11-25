---
name: token-outline
description: Extrait le squelette structurel d'un fichier volumineux (classes, interfaces, méthodes, fonctions et numéros de lignes) pour économiser 85 à 95 % des tokens avant d'appeler read_file sur la plage exacte.
---

# Skill : `token-outline`

Évite de lire des fichiers de 300 à 2 000+ lignes en entier : produit une carte exacte `L<ligne> : <déclaration>` puis permet un `read_file` chirurgical sur la seule fonction utile.

## Procédure

1. **Extraire le squelette** (remplacez `<skill_dir>` par le dossier contenant ce `SKILL.md`) :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "<skill_dir>\scripts\code-outline.ps1" -Path "<file_path>"
   ```
   *(Ajoutez `-MaxEntries 150` si le fichier est très riche.)*

2. **Lire uniquement la zone ciblée** avec `read_file` (`StartLine` / `EndLine`) à partir des numéros de ligne retournés.
