---
name: implement-persistent-user-settings
description: Workflow command scaffold for implement-persistent-user-settings in TclAI.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /implement-persistent-user-settings

Use this workflow when working on **implement-persistent-user-settings** in `TclAI`.

## Goal

Introduces or updates persistent storage for user preferences, session state, and chat history, often involving JSON files and fallback mechanisms.

## Common Files

- `preference.json`
- `lastchat.json`
- `history.json`
- `lib/llm_ui/llm_logic.tcl`
- `lib/llm_ui/llm_ui.tcl`
- `llm_app.tcl`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Create or update JSON files for persistence (e.g., preference.json, lastchat.json, history.json).
- Implement or update logic in llm_logic.tcl and/or llm_ui.tcl to read/write these files.
- Add fallback mechanisms (e.g., system locale detection) if preference files are missing.
- Update UI components to load and save state as needed.
- Update or add tests for persistence logic.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.