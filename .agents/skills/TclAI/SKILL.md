```markdown
# TclAI Development Patterns

> Auto-generated skill from repository analysis

## Overview
This skill teaches the core development patterns and conventions used in the TclAI TypeScript codebase. You'll learn how to structure files, write and organize code, follow commit conventions, and run tests in alignment with the repository's established practices. While no specific framework is detected, the codebase emphasizes clarity, consistency, and maintainability.

## Coding Conventions

### File Naming
- Use **snake_case** for all file names.
  - Example: `my_module.ts`, `user_service.ts`

### Import Style
- Use **relative imports** for referencing other modules.
  - Example:
    ```typescript
    import { myFunction } from './utils';
    ```

### Export Style
- Use **named exports** rather than default exports.
  - Example:
    ```typescript
    // In user_service.ts
    export function getUser() { ... }
    export const USER_ROLE = 'admin';
    ```

### Commit Messages
- Follow the **conventional commit** style.
- Use the `feat` prefix for new features.
  - Example:  
    ```
    feat: add user authentication middleware
    ```

## Workflows

### Creating a New Feature
**Trigger:** When implementing new functionality  
**Command:** `/new-feature`

1. Create a new file using snake_case naming.
2. Write your TypeScript code, using named exports.
3. Use relative imports to include dependencies.
4. Write a corresponding test file named `your_file.test.ts`.
5. Commit your changes with a message like:  
   ```
   feat: short description of the new feature
   ```

### Writing and Running Tests
**Trigger:** When adding or updating code  
**Command:** `/run-tests`

1. Locate or create a test file matching `*.test.*` for your module.
2. Write tests using the project's preferred (unspecified) testing framework.
3. Run the tests using the project's test runner (refer to project documentation or package scripts).

## Testing Patterns

- Test files should follow the `*.test.*` naming convention, e.g., `user_service.test.ts`.
- The specific testing framework is not specified; check project dependencies for details.
- Place tests alongside or near the modules they cover.

  Example:
  ```typescript
  // user_service.test.ts
  import { getUser } from './user_service';

  test('getUser returns correct user', () => {
    expect(getUser()).toEqual({ name: 'Alice' });
  });
  ```

## Commands

| Command         | Purpose                                      |
|-----------------|----------------------------------------------|
| /new-feature    | Start a new feature following conventions    |
| /run-tests      | Run all tests in the codebase                |
```
