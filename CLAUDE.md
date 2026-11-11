# Radar Project Guidelines

## Localization

**Any string added or modified in Swift code via `OWSLocalizedString` must also be added or modified in every translation file.**

Translation files are located at:
```
Signal/translations/<lang>.lproj/Localizable.strings
```

There are 45 language files:
`ar`, `be`, `bn`, `ca`, `cs`, `da`, `de`, `el`, `en`, `es`, `fa`, `fi`, `fr`, `ga`, `gu`, `he`, `hi`, `hr`, `hu`, `id`, `it`, `ja`, `ko`, `mr`, `ms`, `nb`, `nl`, `pl`, `pt_BR`, `pt_PT`, `ro`, `ru`, `sk`, `sr`, `sv`, `th`, `tr`, `ug`, `uk`, `ur`, `vi`, `yue`, `zh_CN`, `zh_HK`, `zh_TW`

### Rules

- When adding a new `OWSLocalizedString` key, insert the entry into **all 45** `.strings` files, sorted alphabetically by key, with an appropriate translation for each language.
- When changing the English value of an existing key, update the value in all language files accordingly.
- If a proper translation is not available for a language, use the English value as a fallback — never leave a key missing from any file.
- Use a script to apply changes across all files at once rather than editing them one by one.

## Implementation Approach

**Always discuss the approach with the user and get agreement before writing any code.**

- Describe what you intend to do (files to touch, approach, trade-offs) and wait for confirmation.
- For small obvious fixes (typos, single-line corrections), use judgment — but when in doubt, ask first.

---

## Flow Tracking Rule

Whenever a non-trivial code flow is explored together with the user (e.g. an end-to-end feature path, a data/sync pipeline, an auth or messaging flow, a build/release path, etc.), save a summary of the key files and call paths to a dedicated memory file (`flow_<name>.md`) under the project memory directory, and add a pointer to it in `MEMORY.md`.

Before proposing or making any code change, check all `flow_*.md` memory files to identify shared code paths that the change could impact, and explicitly flag any potential side-effects to the user.

## Side-Effect Analysis Rule (MANDATORY before any code change or suggestion)

Never modify — or propose modifying — a function without first mapping its **blast radius**. A change that looks local is rarely local. Perform every step below *before* editing, and **report the analysis in your response** (which callers hit the code, what it calls downstream, which features/entry points are affected, why existing behaviour is preserved, and any path you could not verify). If you cannot complete a step, say so explicitly instead of assuming it is safe. Do not call a change "safe" or "no side effects" until this is done. When in doubt, prefer the change with the **narrowest blast radius** — ideally a strict no-op for every existing path (gate new behaviour behind a condition only the new case satisfies).

### 1. Understand the whole function, not just the lines you touch
Read the entire function and the surrounding block. Enumerate everything it reads and writes: database rows, embedded/key-value stores, preferences, files on disk, in-memory/observable state, singletons, and any global/static state.

### 2. Trace the callees (downstream) in the same flow
For every function invoked before and after your edit in the same flow, open it and read what it does. Ask: **does my change alter state that a later step in the same flow reads, re-validates, or re-checks?** Adding, removing, or reordering a call can make a downstream step observe different state.
- **Concrete failure mode to watch for:** a change persisted/created a record *earlier* than before; a downstream callee in the same flow then re-ran an existence/validation check, found that record, and rejected the whole operation. The bug was invisible until the *downstream* function was actually read. Always open the callees — never trust their names.

### 3. Trace the callers (upstream) — usage across the entire codebase
`grep` **every** call site of the function you are modifying (and of any function whose return value, thrown exceptions, timing, or side-effects you changed) across the whole repository / all modules. For each caller, confirm your change preserves what it relies on: return shape, exceptions thrown or *not* thrown, ordering, and any side-effect it depended on happening — or on *not* happening.

### 4. Base classes, overrides, and shared/core modules
- If the function lives in a base/abstract class, protocol, or interface, it runs for **every subtype that inherits it** — enumerate them. Check whether subtypes **override** it: a change to the base never reaches overrides, and a change to one override never reaches the base or its siblings.
- Code in shared/core modules and shared controllers/services runs for **many features and entry points**. Enumerate which features and flows execute the code and reason about each — not just the one you happened to test.

### 5. Ordering, timing, async, idempotency
Write out the new sequence of state mutations after your edit and confirm no step now runs before a dependency it needs (e.g. an id/handle assigned *after* it is first read/used). Check for un-awaited async work, reads before writes complete, re-entrancy, duplicate inserts, and double-validation.

### 6. Persistence & migrations
If the change touches persisted data (databases, embedded/key-value stores, secure storage, files), consider schema/version bumps, key uniqueness, backward compatibility with **existing installs**, and whether a data migration or self-heal is required. Confirm old data still loads and that already-persisted (possibly already-corrupted) records are handled, not just fresh ones.

### 7. Cross-flow memory (ties into the Flow Tracking Rule)
Check every `flow_*.md` memory file for shared code paths the change could touch, and flag them.

### 8. Verify
Run the project's build / analyzer / linter / type-checker (and any code generation) on **every** module you touched. Where practical, exercise the actual flow end-to-end rather than trusting a static trace alone.
