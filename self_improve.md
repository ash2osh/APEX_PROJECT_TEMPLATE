# Self-Improvement Notes

This file is the durable learning log for this project. It supplements
`agents.md`; it does not override direct user, system, or project instructions.

## At the Start of Work

1. Read `agents.md` and this file before making a non-trivial change.
2. Inspect the current Git status and recent history so stale snapshots,
   generated output, or earlier assumptions are not mistaken for current
   behavior.
3. For `.apx` (APEXlang) work, verify syntax and line-ending assumptions with
   the actual parser/compiler. For SQLcl or database work, confirm the exact
   requested connection before executing anything.
4. Prefer the smallest complete correction and verify it with the narrowest
   relevant check before broader validation. Edit APEX source in place under
   `apps/`; keep generated or modified SQL and PL/SQL deployment scripts under
   `ai_generate/YYYY-MM-DD/`; never hand-edit the generated `database/` mirror.

## Learning From Corrections

When a user correction, review finding, compiler failure, deployment issue, or
database investigation exposes a recurring risk:

1. Trace the issue to the active file, parser path, database object, or
   deployment step before changing behavior.
2. Fix the implementation and add or update the narrowest applicable check.
3. Record a lesson only when it is repository-specific, reusable, and supported
   by observed evidence. State the trigger, preferred behavior, and verification
   that prevents recurrence.
4. Merge overlapping lessons and remove stale guidance when the architecture or
   tooling changes.

## What Not to Record

- Secrets, credentials, tokens, connection details, personal data, or customer
  information.
- Temporary environment outages or one-off command failures with no durable
  workflow implication.
- Speculation, unverified diagnoses, generic programming advice, or large
  command outputs.
- Task-by-task status logs or rules already stated authoritatively in `agents.md`.

## Durable Lessons

Add lessons below only when the evidence supports them.

### Lesson Template

```text
### Short reusable lesson

- Trigger: what exposed the risk.
- Evidence: the observed behavior or verification result.
- Preferred behavior: what future agents should do.
- Verification: the check that proves the lesson is being followed.
```

No lessons recorded yet.
