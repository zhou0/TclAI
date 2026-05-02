---
name: refactor-ui-and-logic-separation
description: Workflow command scaffold for refactor-ui-and-logic-separation in TclAI.
allowed_tools: ["Bash", "Read", "Write", "Grep", "Glob"]
---

# /refactor-ui-and-logic-separation

Use this workflow when working on **refactor-ui-and-logic-separation** in `TclAI`.

## Goal

Separates UI code from core logic by extracting non-UI logic into a dedicated logic file and updating UI components to use the new logic module.

## Common Files

- `lib/llm_ui/llm_logic.tcl`
- `lib/llm_ui/llm_ui.tcl`
- `llm_app.tcl`
- `tests/test_llm_logic.tcl`
- `tests/test_llm_ui.tcl`
- `lib/llm_ui/msgs/en.msg`

## Suggested Sequence

1. Understand the current state and failure mode before editing.
2. Make the smallest coherent change that satisfies the workflow goal.
3. Run the most relevant verification for touched files.
4. Summarize what changed and what still needs review.

## Typical Commit Signals

- Extract core logic (e.g., JSON handling, networking) from UI file into a new or existing logic file (lib/llm_ui/llm_logic.tcl).
- Update UI file (lib/llm_ui/llm_ui.tcl) to use the logic module, replacing direct logic with calls to the new namespace.
- Update application entry point (llm_app.tcl) to use new namespace references if needed.
- Update or add tests to cover the refactored logic and UI.
- Update localization files if new UI elements or error messages are introduced.

## Notes

- Treat this as a scaffold, not a hard-coded script.
- Update the command if the workflow evolves materially.