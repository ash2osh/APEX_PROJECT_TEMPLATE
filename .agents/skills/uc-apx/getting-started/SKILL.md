---
name: getting-started
description: Entry point for reading or editing an Oracle APEX apexlang application with the `uc-apx` CLI. Use FIRST on any task that touches `.apx` files — it shows worked commands, routes you to the right read/edit/verify skill, and states the mandatory validate gate. Start here before scaffolding, hand-editing, or validating anything.
---

# Getting started — working on an apexlang app with `uc-apx`

Apexlang applications (`.apx` files, usually with `application.apx` at the app root) are read and edited with the **`uc-apx`** CLI. Read this skill first; it routes you to the task-specific skills.

## The CLI

`uc-apx` is expected on your `$PATH`. Verify with `uc-apx version`; if it's missing, build it (`go build -o uc-apx .` in the CLI repo) or install it before continuing.

Point it at the app with `--app-dir <path>` (defaults to `.`, so omit it when you're already in the app root). Worked examples:

```
uc-apx overview --app-dir <app>     # app-level summary + component counts
uc-apx pages    --app-dir <app>     # list every page
uc-apx shape region --app-dir <app>  # observed properties for a construct kind
uc-apx validate --app-dir <app>     # structural validation
uc-apx --help                       # full subcommand list
```

## Working discipline

- **Scaffold, don't hand-write.** Prefer the `uc-apx create …` / `uc-apx edit …` commands over authoring `.apx` by hand — they re-parse their output and fail fast on a broken splice. Reserve hand-edits for what no command covers yet (the edit skills mark those cases).
- **Check `--help` first.** Before using a subcommand you haven't run, `uc-apx <cmd> --help` to see its flags rather than guessing.
- **Validate in small cycles.** Run `uc-apx validate` after each significant change instead of batching — small cycles beat chasing cascading errors at the end. See the validate gate below.

## Which skill for which task

| Skill | When to use |
|---|---|
| [read/navigate-app](../navigate-app/SKILL.md) | First contact with the app, "what pages exist?", finding files. |
| [read/investigate-component](../investigate-component/SKILL.md) | A symptom → which construct is responsible. |
| [read/inspect-construct-schema](../inspect-construct-schema/SKILL.md) | About to hand-edit; need to know which property names are idiomatic. |
| [edit/create-page](../create-page/SKILL.md) | Adding a new page. |
| [edit/add-region-or-item-to-page](../add-region-or-item-to-page/SKILL.md) | Adding regions, items, buttons, processes, branches to an existing page. |
| [edit/edit-shared-component](../edit-shared-component/SKILL.md) | LOVs, lists, breadcrumbs, authorizations, app-items, page-groups. |
| [edit/delete-component](../delete-component/SKILL.md) | Removing any existing construct (region, item, button, process, page, …). |
| [verify/validate-after-edit](../validate-after-edit/SKILL.md) | After every editing pass. **Mandatory before you declare done.** |

## Validate gate

Every editing pass ends with:

```
uc-apx validate --app-dir <app>
```

Non-zero exit = not done. Fix what it reports, then re-run. See [verify/validate-after-edit](../validate-after-edit/SKILL.md) for how to interpret each issue kind, and for the authoritative `--official` SQLcl check when it's available.
