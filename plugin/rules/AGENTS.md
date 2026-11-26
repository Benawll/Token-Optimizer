# Token Optimizer Rules

1. **Batch parallel calls**: Issue independent searches, file reads, and edits in parallel in a single turn.
2. **Search before reading**: Locate targets with `rg`/grep first, then read bounded line ranges (`StartLine`/`EndLine`) unless the file is under 200 lines. Never dump whole directories or lockfiles.
3. **Surgical edits**: Use targeted `edit_file` diffs. Never reprint unchanged file sections in responses or tool calls.
4. **Quiet CLI output**: Chain dependent commands with `&&`. Pass quiet flags (`-q`, `--quiet`, `--silent`, `--no-progress`) and cap verbose output (`| Select-Object -Last 50` / `| tail -n 50`).
5. **Isolate noisy tasks**: Delegate broad codebase surveys, heavy log analysis, and web browsing to isolated subagents (`research`, `browser`).
6. **Concise output, full rigor**: Skip pleasantries and prompt restatements. Never skip required tests, builds, or verification steps.
7. **Micro-Optimisation Continue (Modèle & Thinking)** : À chaque consigne utilisateur **sans exception**, évaluer la tâche et afficher systématiquement en tout début de réponse le badge strict :
   `[Audit Modèle : Modèle Recommandé | Thinking: Low/Medium/High | Statut: ✅ Optimal ou ⚠️ À modifier]`
   - **Verbalisation orale obligatoire (Voice/Live)** : Ne pas se contenter du badge écrit entre crochets (souvent ignoré par la synthèse vocale). Prononcer explicitement à haute voix la première phrase (ex. : *"Modèle Flash en Low validé."* ou *"Attention, bascule sur Orchestrator en Medium."*).
   - Même lorsque le modèle actuel est déjà parfait pour la tâche, afficher et prononcer obligatoirement cette validation pour confirmer à l'utilisateur que la vérification a bien été exécutée. Signaler le moindre gain de palier :
   - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Low`): Single-file edits, CLI runs, tests, formatting, audits/scans.
   - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Medium`): Routine feature coding, multi-step scripts, standard API logic.
   - `Orchestrator` (`Medium`): Multi-file refactorings, cross-component updates.
   - `Orchestrator` (`High`): Deep architectural redesigns, root-cause forensics on complex failure loops.
