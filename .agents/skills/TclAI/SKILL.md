```markdown
# TclAI Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches you the core development patterns and conventions used in the TclAI TypeScript codebase. You'll learn how to structure files, write imports/exports, follow commit and test conventions, and apply best practices for maintainable code. While no specific framework is used, the repository demonstrates clear patterns for scalable TypeScript projects.

## Coding Conventions

### File Naming
- Use **snake_case** for all file names.
  - Example: `my_module.ts`, `user_service.ts`

### Import Style
- Use **relative imports** for referencing other modules.
  - Example:
    ```typescript
    import { doSomething } from './utils';
    ```

### Export Style
- Use **named exports** instead of default exports.
  - Example:
    ```typescript
    // In math_utils.ts
    export function add(a: number, b: number): number {
      return a + b;
    }

    // In another file
    import { add } from './math_utils';
    ```

### Commit Patterns
- Commit messages are freeform, sometimes with prefixes.
- Average commit message length: 66 characters.

## Workflows

_No automated workflows detected in this repository._

## Testing Patterns

- Test files use the `.test.ts` suffix.
  - Example: `math_utils.test.ts`
- The testing framework is not explicitly specified.
- Organize tests alongside or near the code they validate.
- Example test file:
  ```typescript
  import { add } from './math_utils';

  describe('add', () => {
    it('adds two numbers', () => {
      expect(add(2, 3)).toBe(5);
    });
  });
  ```

## Commands
| Command         | Purpose                                 |
|-----------------|-----------------------------------------|
| /run-tests      | Run all test files (`*.test.ts`)        |
| /new-module     | Scaffold a new module in snake_case     |
| /format-code    | Format code according to conventions    |
| /list-tests     | List all test files in the codebase     |

```