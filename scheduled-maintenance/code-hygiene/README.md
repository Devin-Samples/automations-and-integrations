# Code Hygiene — Dead Code and Import Cleanup

Scheduled Devin sessions that identify and remove unused imports, unreachable code, deprecated API usage, and other code hygiene issues — keeping your codebase clean without manual toil.

## Overview

Code hygiene debt accumulates silently: unused imports after refactors, dead functions behind feature flags that shipped months ago, deprecated API calls that still work but will break on the next upgrade. This pattern uses Devin's scheduled sessions to perform a monthly sweep across your codebase.

### What Gets Cleaned

| Category | Examples |
|----------|---------|
| **Unused imports** | `import { foo } from './bar'` where `foo` is never referenced |
| **Dead code** | Functions, classes, or variables that are never called or referenced |
| **Unreachable code** | Code after `return`, `throw`, or `break` statements |
| **Deprecated API usage** | Calls to functions/methods marked as deprecated by the library |
| **Unused variables** | Declared but never read variables |
| **Commented-out code** | Large blocks of commented-out code (not documentation comments) |
| **Redundant type casts** | Unnecessary type assertions or casts |

---

## Devin Scheduled Session Configuration

### Recommended Cadence

**Monthly** — Code hygiene issues are low-urgency and rarely cause runtime failures. Monthly sweeps keep the codebase clean without generating excessive PR noise.

```
Cron expression: 0 9 1 * *    (1st of every month at 09:00 UTC)
```

### Using the Devin API

```bash
curl -s -X POST "https://api.devin.ai/v1/schedules" \
  -H "Authorization: Bearer $DEVIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "cron": "0 9 1 * *",
    "title": "Monthly code hygiene sweep — my-app",
    "prompt": "You are performing a scheduled code hygiene sweep on this repository. Identify and remove: unused imports, dead/unreachable code, unused variables, and deprecated API usage. Do NOT remove code that is used in tests, referenced dynamically, or part of a public API. Run the test suite after cleanup to verify nothing breaks. Open a PR titled \"chore: monthly code hygiene cleanup\" with a summary of all changes organized by category.",
    "repos": [
      { "url": "https://github.com/my-org/my-app" }
    ]
  }'
```

---

## Example Prompt

```text
You are performing a scheduled code hygiene sweep on this repository. Follow these steps:

1. ANALYSIS PHASE — Identify the following issues WITHOUT making changes yet:
   a. Unused imports (imported but never referenced in the file)
   b. Unused variables and constants (declared but never read)
   c. Dead functions/methods (defined but never called from anywhere in the codebase)
   d. Unreachable code (code after return/throw/break statements)
   e. Deprecated API usage (calls to deprecated functions — check compiler warnings)
   f. Large blocks of commented-out code (>5 lines)

2. SAFETY CHECKS — Before removing anything, verify:
   - The symbol is not referenced via dynamic imports, reflection, or string-based lookups
   - The symbol is not part of a public API or exported interface
   - The symbol is not used in test files (if removing from source, ensure tests still pass)
   - The symbol is not referenced in configuration files or build scripts
   - For deprecated APIs: identify the recommended replacement and migrate to it

3. CLEANUP PHASE — Make the changes:
   - Remove unused imports
   - Remove dead code (functions, classes, variables)
   - Remove unreachable code
   - Replace deprecated API calls with their recommended alternatives
   - Remove large blocks of commented-out code
   - Do NOT reformat or restyle code that isn't being cleaned up

4. VERIFICATION PHASE:
   - Run the linter / type checker
   - Run the full test suite
   - If any test fails, revert the specific change that caused the failure

5. OPEN A PR titled "chore: monthly code hygiene cleanup" with:
   - A summary table: category | file | description of change
   - Total counts: X unused imports removed, Y dead functions removed, etc.
   - A section noting any items skipped (e.g., dynamically referenced symbols)
   - A section noting any deprecated API migrations performed
```

---

## Language-Specific Strategies

### TypeScript / JavaScript

**Tooling:** The TypeScript compiler (`tsc --noUnusedLocals --noUnusedParameters`) and ESLint (`no-unused-vars`, `no-unused-imports`) catch most issues.

**Key areas:**
- **Unused exports**: Modules that export symbols no other module imports. Use `ts-unused-exports` or `knip` to detect these.
- **Barrel file bloat**: `index.ts` re-export files that export symbols no consumer uses.
- **Dead feature flags**: Code behind feature flags that were permanently enabled or removed.
- **Type-only imports**: Imports used only as types should use `import type { ... }`.

**Example prompt addition for TypeScript:**

```text
For this TypeScript project, also check for:
- Unused exports using `npx knip` if available, or by searching for exports that have
  no corresponding import anywhere in the codebase
- Barrel file (index.ts) re-exports that are never imported by consumers
- Imports that should be `import type` (used only in type positions)
- Any `// @ts-ignore` or `// @ts-expect-error` comments that are no longer needed
  (the underlying error may have been fixed)
```

### Python

**Tooling:** `autoflake` (unused imports/variables), `vulture` (dead code), `ruff` (comprehensive linter with auto-fix).

**Key areas:**
- **Unused imports**: Common after refactors. `autoflake --remove-all-unused-imports` handles these.
- **Dead functions**: Functions defined but never called. `vulture` gives a confidence score.
- **`__all__` consistency**: Module `__all__` lists that include symbols no longer defined.
- **Wildcard imports**: `from module import *` that pulls in more than needed.

**Example prompt addition for Python:**

```text
For this Python project, also check for:
- Run `ruff check --select F401,F841 .` to find unused imports and variables
- If vulture is available, run `vulture . --min-confidence 80` for dead code detection
- Check for wildcard imports (`from x import *`) and replace with explicit imports
- Verify `__all__` lists match actual module exports
- Look for bare `except:` clauses that should be `except Exception:`
```

### Java / Kotlin

**Tooling:** IDE inspections (IntelliJ), SpotBugs, PMD, or the compiler's `-Xlint:all` flag.

**Key areas:**
- **Unused private methods**: Private methods that are never called within the class.
- **Unused fields**: Especially common after removing features or refactoring DTOs.
- **Deprecated annotations**: Methods/classes using `@SuppressWarnings("deprecation")` — check if the deprecation can be addressed instead.
- **Dead catch blocks**: `catch` clauses for exceptions that can never be thrown.

**Example prompt addition for Java:**

```text
For this Java/Kotlin project, also check for:
- Unused private methods and fields
- Imports that IntelliJ would flag as unused (wildcards that can be narrowed)
- @SuppressWarnings("deprecation") — check if the deprecated API has a replacement
- Dead catch blocks for checked exceptions no longer thrown
- Unused @Autowired fields in Spring beans
```

---

## Example PR Output

A typical code hygiene PR looks like:

### PR Title
```
chore: monthly code hygiene cleanup
```

### PR Body
```markdown
## Code Hygiene Sweep — January 2025

### Summary

| Category | Files Changed | Items Removed |
|----------|:------------:|:-------------:|
| Unused imports | 12 | 23 |
| Dead functions | 4 | 6 |
| Unused variables | 7 | 9 |
| Unreachable code | 2 | 3 |
| Deprecated API migration | 1 | 1 |
| Commented-out code | 3 | 3 |
| **Total** | **22** | **45** |

### Changes by File

| File | Change |
|------|--------|
| `src/utils/helpers.ts` | Removed unused imports: `lodash.merge`, `path` |
| `src/services/auth.ts` | Removed dead function `legacyTokenRefresh()` (0 callers) |
| `src/api/routes.ts` | Removed unreachable code after early return in `handleError()` |
| `src/models/user.ts` | Migrated `crypto.createCipher()` → `crypto.createCipheriv()` |
| `src/config/index.ts` | Removed 15-line commented-out Redis config block |

### Skipped Items

- `src/plugins/loader.ts:dynamicRequire()` — referenced via string-based dynamic import
- `src/api/v1/legacy.ts:formatV1Response()` — exported as public API, may have external consumers

### Verification

- Linter: passed
- Type checker: passed
- Test suite: 342/342 passed
```

---

## Tips

- **Don't over-clean**: Code that *looks* dead but is loaded via reflection, dependency injection, or dynamic imports should be left alone. Instruct Devin to err on the side of caution.
- **Separate from feature work**: Keep hygiene PRs separate from feature PRs so they are easy to review and revert if needed.
- **Track trends**: If monthly sweeps consistently find 50+ unused imports, consider enabling stricter linter rules (`no-unused-vars: error`) to prevent accumulation.
- **Exclude generated code**: Add instructions to skip auto-generated files (e.g., GraphQL codegen, protobuf stubs, OpenAPI clients).
- **Review before merge**: Even though these are automated cleanups, a human should review the PR — especially deprecated API migrations and dead code removal.
