---
trigger: manual
description: Conditional workflow for editing apexlang (.apx) files with the optional uc-apx CLI.
---

# uc-apx Workflow (Optional Tooling)

`uc-apx` is a third-party structural CLI for Oracle APEX apps stored in
apexlang (`.apx`) format (https://github.com/United-Codes/uc-apx). It is
not bundled and is not guaranteed to be installed. Never assume its presence
in a fresh clone.

## Availability check (do this first)

```bash
command -v uc-apx >/dev/null 2>&1 && uc-apx version
```

- If this fails: edit APEXlang source in place under `apps/` using the general
  `apex` guidance, or set `INSTALL_UC_APX=true` in `.env` and invoke the
  [`install-uc-apx` skill](../skills/install-uc-apx/SKILL.md).
- If it succeeds: continue below.

## Installation and skills

The only supported template flow is the opt-in
[`install-uc-apx` skill](../skills/install-uc-apx/SKILL.md). It is gated by
`INSTALL_UC_APX=true`, keeps the binary user-managed, and synchronizes skills
project-locally. Do not add `--global` and do not vendor generated uc-apx
skills into the template.

## Core commands (when installed)

Run against the configured app directory,
`apps/$APEX_PARSING_SCHEMA/$APEX_APP_SLUG`:

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

## Separate validation step

```bash
uc-apx validate --app-dir "apps/$APEX_PARSING_SCHEMA/$APEX_APP_SLUG"
```

Validation is useful before handing off an application edit, but it is never
part of `export_apps.sh` or `export_apps.ps1`. Export stages and replaces the
app without invoking validation, as required by this template.
