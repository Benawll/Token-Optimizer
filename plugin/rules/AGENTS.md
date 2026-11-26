# Token Optimizer Rules

1. **Batch parallel calls**: Issue independent searches, file reads, and edits in parallel in a single turn.
2. **Search before reading**: Locate targets with `rg`/grep first, then read bounded line ranges (`StartLine`/`EndLine`) unless the file is under 200 lines. Never dump whole directories or lockfiles.
3. **Surgical edits**: Use targeted `edit_file` diffs. Never reprint unchanged file sections in responses or tool calls.
4. **Quiet CLI output**: Chain dependent commands with `&&`. Pass quiet flags (`-q`, `--quiet`, `--silent`, `--no-progress`) and cap verbose output (`| Select-Object -Last 50` / `| tail -n 50`).
5. **Isolate noisy tasks**: Delegate broad codebase surveys, heavy log analysis, and web browsing to isolated subagents (`research`, `browser`).
6. **Concise output, full rigor**: Skip pleasantries and prompt restatements. Never skip required tests, builds, or verification steps.
7. **Adaptive Model & Thinking Guidance**: Evaluate task complexity on every new user request. Display a strict recommendation tag (`[Recommandation : Modèle | Thinking: Exact]`) when switching improves cost or execution:
   - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Low`): Single-file edits, syntax fixes, localized tweaks, CLI runs.
   - `Gemini 3.8 Flash` / `Gemini 4 Hydrogen` (`Medium`): Routine feature coding, multi-step script dev, standard testing.
   - `Orchestrator` (`Medium`): Multi-file refactorings, cross-component updates, data contract migrations.
   - `Orchestrator` (`High`): Deep architectural redesigns, root-cause forensics on complex failure loops.
