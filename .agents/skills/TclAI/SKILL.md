```markdown
# TclAI Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill covers the key development patterns and workflows used in the TclAI TypeScript codebase. While the project does not use a major framework, it demonstrates clear modularization, persistent state management, localization, and UI logic separation. The repository emphasizes maintainability, testability, and internationalization, with regular workflows for refactoring, persistence, and UI enhancements.

## Coding Conventions

- **File Naming:**  
  Use `snake_case` for all file names.  
  _Example:_  
  ```
  lib/llm_ui/llm_logic.tcl
  tests/test_llm_ui.tcl
  ```

- **Import Style:**  
  Use relative imports for modules.  
  _Example:_  
  ```typescript
  import { json_pretty } from './llm_logic';
  ```

- **Export Style:**  
  Use named exports for functions and constants.  
  _Example:_  
  ```typescript
  export function json_pretty(data: any): string { ... }
  ```

- **Commit Messages:**  
  Freeform style, typically concise (average ~59 characters).

## Workflows

### Refactor UI and Logic Separation
**Trigger:** When modularizing code for maintainability or introducing new logic/UI boundaries  
**Command:** `/refactor-ui-logic`

1. **Extract core logic** (e.g., JSON handling, networking) from the UI file into a new or existing logic file, such as `lib/llm_ui/llm_logic.tcl`.
2. **Update the UI file** (`lib/llm_ui/llm_ui.tcl`) to use the new logic module, replacing direct logic with calls to the new namespace.
3. **Update the application entry point** (`llm_app.tcl`) to reference the new logic namespace if needed.
4. **Update or add tests** to cover the refactored logic and UI (`tests/test_llm_logic.tcl`, `tests/test_llm_ui.tcl`).
5. **Update localization files** if new UI elements or error messages are introduced.

_Example:_
```typescript
// In llm_logic.ts
export function fetchData() { ... }

// In llm_ui.ts
import { fetchData } from './llm_logic';
```

### Implement Persistent User Settings
**Trigger:** When adding or updating features that require saving user state or preferences across sessions  
**Command:** `/persist-settings`

1. **Create or update JSON files** for persistence (e.g., `preference.json`, `lastchat.json`, `history.json`).
2. **Implement or update logic** in `llm_logic.tcl` and/or `llm_ui.tcl` to read/write these files.
3. **Add fallback mechanisms** (e.g., system locale detection) if preference files are missing.
4. **Update UI components** to load and save state as needed.
5. **Update or add tests** for persistence logic.

_Example:_
```typescript
// Save preferences
export function savePreferences(prefs: object) {
  fs.writeFileSync('preference.json', JSON.stringify(prefs));
}

// Load preferences with fallback
export function loadPreferences() {
  try {
    return JSON.parse(fs.readFileSync('preference.json', 'utf8'));
  } catch {
    return detectSystemLocale();
  }
}
```

### Update Localization Files for UI Changes
**Trigger:** When adding new UI features, buttons, or error dialogs that require translated text  
**Command:** `/update-localization`

1. **Add or update message keys** in all relevant localization files (`lib/llm_ui/msgs/en.msg`, `zh_cn.msg`, `zh_tw.msg`).
2. **Update UI code** to use the new message keys.
3. **Test UI** to ensure correct message rendering in all supported languages.

_Example:_
```typescript
// en.msg
show_json_button = "Show JSON"

// llm_ui.ts
const buttonLabel = getMessage('show_json_button');
```

### Add or Improve JSON Display in UI
**Trigger:** When exposing API response data or debugging information to users in a readable format  
**Command:** `/add-json-display`

1. **Implement or update a pretty-printing function** for JSON (e.g., `json_pretty` in `llm_logic.tcl`).
2. **Add or modify a UI button** (e.g., "Show JSON") in `llm_ui.tcl`.
3. **Update the UI layout** to accommodate the new control (e.g., right-align button).
4. **Update localization files** for new button text.
5. **Test the feature** in the UI.

_Example:_
```typescript
// llm_logic.ts
export function json_pretty(data: any): string {
  return JSON.stringify(data, null, 2);
}

// llm_ui.ts
<button onClick={() => showModal(json_pretty(responseData))}>
  {getMessage('show_json_button')}
</button>
```

## Testing Patterns

- **Test Files:**  
  Test files use the `*.test.ts` pattern and are placed alongside source files or in a `tests/` directory.
- **Framework:**  
  The specific testing framework is not detected, but tests are written in TypeScript and cover both logic and UI modules.
- **Coverage:**  
  Tests are updated or added when refactoring logic, implementing persistence, or changing UI behavior.

_Example:_
```typescript
// tests/test_llm_logic.test.ts
import { json_pretty } from '../lib/llm_ui/llm_logic';

test('json_pretty formats JSON', () => {
  expect(json_pretty({ a: 1 })).toBe('{\n  "a": 1\n}');
});
```

## Commands

| Command                | Purpose                                                        |
|------------------------|----------------------------------------------------------------|
| /refactor-ui-logic     | Separate UI code from core logic for better maintainability    |
| /persist-settings      | Add or update persistent storage for user settings and history |
| /update-localization   | Synchronize localization files with new or changed UI elements |
| /add-json-display      | Implement or enhance JSON pretty-printing and display in UI    |
```
