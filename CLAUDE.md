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
