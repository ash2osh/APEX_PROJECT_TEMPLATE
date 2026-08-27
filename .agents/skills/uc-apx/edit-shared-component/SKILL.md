---
name: edit-shared-component
description: Hand-edit shared components in an apexlang project — authentications, app-items, page-groups, and existing-LOV-entry edits. Use when the user asks to add or modify a value in `shared-components/*.apx` and no `uc-apx create <thing>` scaffolder exists. For NEW LOVs / breadcrumbs / lists / authorizations use the dedicated `uc-apx create <thing>` commands instead — they're safer than hand-editing.
---

# Editing shared components

Shared components live in `shared-components/*.apx` and are referenced from pages via `@<id-or-alias>`. Most shared components now have dedicated scaffolders — **always prefer those over hand-edits**:

- New shared-component LOV → `uc-apx create lov --name <NAME> --source static-values|sql ...`
- New top-level breadcrumb → `uc-apx create breadcrumb --name <Name>`
- New entry under an existing breadcrumb → `uc-apx create breadcrumb-entry --page <n> --label <Label> [--parent <entry-id>]`
- New top-level list → `uc-apx create list --name <Name>`
- New entry under an existing list → `uc-apx create list-entry --list <id> --label <Label> --page <n>` (or `--url <url>`)
- Authorization (new scheme, editing one, or applying it) → see [skills/edit/edit-authorization/SKILL.md](../edit-authorization/SKILL.md) (`uc-apx create/edit authorization`, `uc-apx edit <kind> --authz`)

This skill is the hand-edit playbook for the cases the CLI doesn't scaffold yet (authentications, app-items, page-groups, modifying an existing LOV's entries, etc.).

## When to use this skill

- The user asks to add or modify an entry in:
  - `shared-components/authentications.apx`
  - `shared-components/app-items.apx`
  - `page-groups.apx`
  - `shared-components/lovs.apx` — only when **modifying an existing LOV's entries**; for a new LOV use `uc-apx create lov`.
- A scaffold skill told you to make a shared-component edit as a "next step" and no scaffolder fits.

**Do not** use this skill when:

- The user wants a new LOV → `uc-apx create lov`.
- The user wants a new breadcrumb or a new entry under an existing breadcrumb → `uc-apx create breadcrumb` / `uc-apx create breadcrumb-entry`.
- The user wants a new list or a new list entry → `uc-apx create list` / `uc-apx create list-entry`.
- The user wants to create, edit, or apply an authorization scheme → [skills/edit/edit-authorization/SKILL.md](../edit-authorization/SKILL.md).
- The change is to a page (`pages/*.apx`) — use [skills/edit/add-region-or-item-to-page/SKILL.md](../add-region-or-item-to-page/SKILL.md).
- The user wants to create an entire new page — use [skills/edit/create-page/SKILL.md](../create-page/SKILL.md).

## The 4-step hand-edit playbook

```
1. Discover existing instances     → uc-apx shape <kind>, uc-apx list <kind>
2. Pick a similar one as template  → uc-apx component <id>
3. Hand-edit the .apx file         → Read + Edit
4. Validate                        → uc-apx validate (--official if SQLcl is present)
```

### Step 1: discover the shape

Before adding a new LOV, list, etc., see what's already there:

```bash
uc-apx list lov --app-dir <root>           # all LOVs by name + file
uc-apx shape lov --app-dir <root>         # which properties/blocks LOVs use in this app
```

If you don't pattern-match against an existing instance, the chance of inventing a property name the validator rejects is high.

### Step 2: pick a template instance

Find the closest existing example to your target:

```bash
# I need a static-values LOV
uc-apx search "location: staticValues" --app-dir <root>

# I need a table-backed LOV
uc-apx search "tableName:" --app-dir <root>

# Dump the full structure of one you like
uc-apx component <id> --app-dir <root>
```

Copy its shape verbatim, then change only the values you need.

### Step 3: hand-edit

Open the relevant `shared-components/*.apx` file. New constructs go at the end of the file (or near related ones — file order rarely matters semantically but consistent placement helps reviews).

**Syntax cheat-sheet (LOV example):**

```
lov APEX$13966104307485518519 (
    name: SALES HISTORY NAVIGATION
    source {
        location: staticValues
    }

    entry APEX$13966104548790518521 (
        sequence: 10
        display: Classic Report
        return: 50
    )
)
```

**For a table-backed LOV:**

```
lov APEX$27767758778551122165 (
    name: OOW_DEMO_STORES.STORE_NAME
    source {
        tableName: OOW_DEMO_STORES
    }
    columnMapping {
        return: ID
        display: STORE_NAME
        defaultSort: STORE_NAME
    }
)
```

**Assigning a new ID.** Use the convention used elsewhere in this app — almost always `APEX$<20-ish digits>`. The digits in real exports come from APEX (timestamp-derived). For hand-authored IDs, pick a unique number not already present:

```bash
# Sanity-check uniqueness before committing your edit
uc-apx component APEX$<your-new-id> --app-dir <root>
# Should return "not found". If it returns a node, pick a different number.
```

You can also use a human-readable alias for shared components that get referenced by name in pages (LOV names are often referenced as `@LOV_NAME`). When in doubt, copy the ID style from a neighbor in the same file.

**Indentation.** 4 spaces per nesting level. Properties and child constructs go on their own lines. Don't put multiple properties on one line.

**Code blocks** (SQL/PL/SQL in `sourceQuery:`, `plsqlFunctionBody:`, etc.):

````
sqlQuery: 
    ```sql
    select id, name
    from departments
    order by name
    ```
````

The triple-backtick fence + language tag is required for syntax-aware editors.

### Step 4: validate

This step is **not optional**. See [skills/verify/validate-after-edit/SKILL.md](../validate-after-edit/SKILL.md) for the full workflow.

## Concrete examples

### Add a list entry so a new page appears in navigation

Use the scaffolder:

```bash
uc-apx create list-entry \
    --list navigation-menu \
    --label Departments \
    --page 42 \
    --parent home \
    --sequence 50 \
    --app-dir <root>
```

Find existing list IDs with `uc-apx list list` and entry IDs with `uc-apx component <list-id>`. If the app has exactly one list, `--list` is optional.

### Add a breadcrumb entry

Use the scaffolder — it always emits the validator-correct `appearance { parentEntry: @<id> }` block:

```bash
uc-apx create breadcrumb-entry \
    --page 42 \
    --label Departments \
    --parent home \
    --app-dir <root>
```

If the app has more than one breadcrumb, also pass `--breadcrumb <id>`.

### Add a static-values entry to an existing LOV

Open the LOV in `shared-components/lovs.apx` and add an `entry` block inside it:

```
entry APEX$<unique-digits> (
    sequence: 70                  # pick the next free multiple of 10
    display: New Option
    return: NEW
)
```

## Common pitfalls

- **Don't invent property names.** Always pattern-match against an existing instance from `uc-apx shape` or `uc-apx component`.
- **`sequence:` matters.** Lists, breadcrumbs, and LOV entries render in sequence order. Pick a value that places yours where the user expects.
- **`@aliasName` references must resolve.** If you reference `@home` but no list/breadcrumb entry with id `home` exists, validate will flag `brokenReference`.
- **Don't hand-edit `.apex/apexlang.json`.** Never touch the `mmdVersion` file.
- **Don't reuse an existing ID.** `uc-apx validate` catches duplicate IDs but only after the fact. Pre-check with `uc-apx component <id>`.

## Validate before you declare done

After editing, run validate from the app root:

```bash
uc-apx validate --app-dir <project-root>
```

If `sql` (SQLcl 26.1.2+) is on `$PATH`, prefer the full check:

```bash
uc-apx validate --app-dir <project-root> --official
```

**Do not declare the change done until validate exits clean.** If validate errors, read the file and line it reports, fix the issue, and re-run. See [skills/verify/validate-after-edit/SKILL.md](../validate-after-edit/SKILL.md) for how to interpret each issue kind.

## Reference

- Index source: [index/index.go](https://github.com/United-Codes/uc-apx/blob/main/index/index.go)
- Validate skill: [skills/verify/validate-after-edit/SKILL.md](../validate-after-edit/SKILL.md)
- Schema inspection: [skills/read/inspect-construct-schema/SKILL.md](../inspect-construct-schema/SKILL.md)
