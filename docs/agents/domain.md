# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`GLOSSARY-MAP.md`** at the repo root: it points at one `GLOSSARY.md` per context. Read each one relevant to the topic.
- **`docs/adr/`**: system-wide ADRs. Also read ADRs that touch the area you're about to work in, in `apps/<app>/docs/adr/` or `packages/<package>/docs/adr/`.
- **`apps/herder/docs/ARCHITECTURE.md`**: the rulebook for the macOS app. Read it before changing anything there.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Multi-context repo:

```
/
├── GLOSSARY-MAP.md                    ← points at each context's GLOSSARY.md
├── docs/adr/                          ← system-wide decisions
├── apps/herder/
│   ├── GLOSSARY.md
│   └── docs/adr/                      ← app-specific decisions (beside ARCHITECTURE.md)
└── packages/<package>/
    ├── GLOSSARY.md
    └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the relevant `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
