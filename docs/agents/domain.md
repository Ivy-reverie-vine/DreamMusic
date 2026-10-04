# Domain Docs

This repository uses a single-context domain documentation layout.

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read the relevant records in `docs/adr/` before changing code in that area.
- Use the terminology defined in `CONTEXT.md` in issue titles, plans, hypotheses, tests, and implementation notes.

If a needed domain term is not defined, treat that as a vocabulary gap and record it for domain-modeling rather than silently inventing a competing term.

## File structure

```text
/
├── CONTEXT.md
├── docs/adr/
└── src/
```

There is no `CONTEXT-MAP.md`; do not infer multiple contexts unless one is added deliberately.

## ADR conflicts

If a plan contradicts an existing ADR, call out the contradiction explicitly and identify which decision must be reopened. Do not silently override an accepted ADR.
