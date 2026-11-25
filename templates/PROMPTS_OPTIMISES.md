# Templates de Prompts Optimisés (Orchestrator / Neon / Hydrogen)

Ces modèles réduisent les allers-retours (*rework*) en donnant dès le 1er tour les cibles (`@`), les contraintes et la commande de validation silencieuse.

## 1. Feature ciblée (Orchestrator `Neon Medium + Hydrogen`)
```text
Objectif : [décrire le résultat attendu en 1 phrase]
Cibles : @[fichier1] @[dossier]
Contraintes : [respecter les conventions existantes, pas de nouvelles dépendances]
Validation : exécuter `[ex: dotnet test --verbosity quiet / pytest -q]` après édition.
```

## 2. Bugfix rapide
```text
Symptôme : [message d'erreur exact ou comportement incorrect]
Repro : `[commande]` | Fichier probable : @[fichier]
Attendu : corriger la cause racine + vérifier que `[test]` passe.
```

## 3. Refactoring chirurgical
```text
Refactorer @[fichier] (fonction/classe [Nom]) pour [but précis].
Ne pas toucher au comportement public. Vérifier avec `[commande_test]`.
```

## 4. Exploration sans polluer la session principale
```text
Utilise le subagent `research` pour cartographier [flux/module] dans @[dossier].
Renvoie uniquement : fichiers impliqués, points d'entrée (ligne) et risques.
```

## 5. Handoff vers une nouvelle session (couper l'effet boule de neige)
À demander quand une session atteint 30–50 tours :
```text
Fais un handoff ultra-compact (max 10 lignes) pour une nouvelle session :
- État validé, - Fichiers modifiés, - Ce qu'il reste à faire, - Prochaine commande à lancer.
```
