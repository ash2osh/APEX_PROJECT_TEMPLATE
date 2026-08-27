---
trigger: manual
description: Conditional workflow for editing apexlang (.apx) files with the optional uc-apx CLI.
---

# uc-apx Workflow (Optional Tooling)

`uc-apx` is a third-party structural CLI for Oracle APEX apps stored in
apexlang (`.apx`) format (https://github.com/United-Codes/uc-apx). It is
**not** guaranteed to be installed. Never assume its presence in a fresh
clone of this template.

## Availability check (do this first)

```bash
command -v uc-apx >/dev/null 2>&1 && uc-apx version
```

- If this fails (no output / command not found): stop using this workflow.
  Fall back to plain SQLcl `apex export -exptype APEXLANG` / `apex import`
  and the general `apex` skill for reading and editing `.apx` files by hand.
- If it succeeds: continue below.

## Installing uc-apx (optional, once per machine)

Download a release for your platform from
https://github.com/United-Codes/uc-apx and place the binary on `PATH` as
`uc-apx`. Then, once per project, install its bundled coding-agent skills:

```bash
uc-apx skills sync --agent claude-code
```

(Use `--agent universal` for non-Claude clients, and add `--global` to
install into `~/.claude/skills` once for all projects instead of this repo's
`.claude/skills`.)

## Core commands (when installed)

Run from the application directory, e.g. `--app-dir apps/{{SCHEMA}}/{{APP_SLUG}}`:

- `uc-apx overview` — summary of the application.
- `uc-apx search <term>` — search names, SQL, and PL/SQL across the app.
- `uc-apx shape <kind>` — observed properties / a reference template for a
  component type. Use this before hand-writing a new component so the
  syntax matches what the app already uses, rather than guessing property
  names.
- `uc-apx create <kind> ...` / `uc-apx edit <kind> ...` / `uc-apx delete <kind> ...`
  — scaffold, modify, or remove components in place.
- `uc-apx deps <id>` / `uc-apx refs <id>` — dependency graph / reverse
  references for a component, before deleting or renaming it.
- `uc-apx schema` — the database objects (tables, views, packages, …) the
  app uses.

## Mandatory gate after any edit

```bash
uc-apx validate --app-dir apps/{{SCHEMA}}/{{APP_SLUG}}
```

Never hand off or import a `.apx` change without a clean `validate` run.
