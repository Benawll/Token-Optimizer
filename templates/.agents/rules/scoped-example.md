---
description: Conventions SQL et migrations de base de données (chargé uniquement quand pertinent)
trigger: model_decision
---

# Règles Base de Données & Migrations

> [!NOTE]
> Grâce à `trigger: model_decision` dans le frontmatter YAML, cette règle n'est **pas** injectée en permanence dans `always_on` : elle n'est activée que lorsque la tâche touche à la base de données ou aux migrations.

## Invariants
- Toujours générer des migrations idempotentes et réversibles (`up` et `down`).
- Ne jamais modifier une migration déjà appliquée en production ; créer une nouvelle migration incrémentale.
- Vérifier les index sur toutes les clés étrangères ajoutées.
- Tester la migration sur une base locale avec sortie concise avant de conclure.
