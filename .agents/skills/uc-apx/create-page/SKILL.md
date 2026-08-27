---
name: create-page
description: Scaffold new Oracle APEX apexlang pages in a project using the `uc-apx create page` CLI. Use whenever the user asks to add a new page (form, report, dashboard, etc.) to an apexlang application, or when you need a deterministic starting point for a new `.apx` page file instead of hand-writing the DSL.
---

# `uc-apx create page` — Creating pages in apexlang projects

Use `uc-apx create page` to produce a new `pages/pNNNNN-<slug>.apx` file from a bundled template. The command handles boilerplate (required `appearance` / `security` blocks, breadcrumb region, page-id substitution throughout `PNNNNN_*` identifiers) so you can focus on the business logic.

## When to use this skill

- The user asks to "create a page", "add a form page", "add a new report", "scaffold a dashboard", etc. in an apexlang project (has `.apx` files and usually an `application.apx` at the app root).
- You need a correct, minimal starting point for a new page before customizing columns / items / processes.

**Do not** use this skill when:

- The user wants to modify an existing page — edit the `.apx` file directly.
- The user is working in an APEX project that is _not_ apexlang (no `.apx` files).

## Synopsis

```
uc-apx create page --id <n> --name <name> --type <type> [flags] [--app-dir <path>]
```

**Required flags**

| Flag     | Description                                                                                       |
| -------- | ------------------------------------------------------------------------------------------------- |
| `--id`   | Page number (1–99998). Must not collide with an existing page in the app.                         |
| `--name` | Display name, e.g. `"Departments"`. Used for `name:`, and (by default) `title:`.                  |
| `--type` | One of: `blank`, `form`, `classic-report`, `interactive-report`, `interactive-grid`, `dashboard`, `modal-dialog`. |

**Common optional flags**

| Flag           | Default                     | Notes                                                                         |
| -------------- | --------------------------- | ----------------------------------------------------------------------------- |
| `--alias`      | uppercase slug of `--name`  | e.g. `Employee Details` → `EMPLOYEE-DETAILS`                                  |
| `--title`      | `--name`                    | Browser / breadcrumb title                                                    |
| `--file`       | `pages/p<NNNNN>-<slug>.apx` | Relative to `--app-dir`                                                       |
| `--page-group` | omitted                     | Id **or display name** of an existing pageGroup; injected as `pageGroup: @<id>`. **Validated** — an unknown group is rejected (create it first with `uc-apx create page-group <id> --name <Display>`). A display-name input is normalized to the group id. |
| `--table`      | omitted (required for `form`) | Applies **only** to `--type form`. Rejected on `blank` / `classic-report` / `interactive-report` / `interactive-grid` / `dashboard` / `modal-dialog` with a pointer at the per-region scaffolder — those page templates ship bare-shell and pick up their tables later via `uc-apx create region <type>`. |
| `--dry-run`    | false                       | Print rendered content, do not write                                          |
| `--force`      | false                       | Overwrite existing target file. Does **not** bypass duplicate-id check.       |

**Global flags**

- `--app-dir` — project root (default: current directory)
- `--json-pretty` — emit indented JSON (for human inspection; default is minified JSON)
- `--toon` — emit TOON format (compact human-readable alternative)

## Choosing `--type`

| `--type`             | Use for                                                                                      |
| -------------------- | -------------------------------------------------------------------------------------------- |
| `blank`              | Starting point when you'll build a custom layout. Includes breadcrumb only.                  |
| `form`               | Modal drawer (pageMode: modalDialog), auto-row DML, cancel / create / save / delete buttons. |
| `classic-report`     | Read-only tabular report (`type: classicReport`).                                            |
| `interactive-report` | Rich search + row selection report (`type: interactiveReport`).                              |
| `interactive-grid`   | Inline-editable grid with auto-row processing (`type: interactiveGrid`).                     |
| `dashboard`          | KPIs + chart series scaffold (`type: chart` regions).                                        |
| `modal-dialog`       | Blank modal page with a footer buttons region, a `Close` button, and a `cancelDialog` dynamic action. Use for non-form dialogs (confirmation, info, custom content). For a CRUD modal use `form` instead. |

## Concrete examples

**New Interactive Report (SQL-only — scaffold page, then region):**

```bash
uc-apx create page --id 42 --name "Departments" --type interactive-report
uc-apx create region interactive-report --page 42 --name "Departments" \
    --sql "select deptno, dname, loc from dept order by dname" \
    --column "DEPTNO:number,DNAME:varchar2:14,LOC:varchar2:13"
```

`create region interactive-report` (and `classic-report`) only scaffold the sqlQuery shape — author the SELECT yourself, including any WHERE / ORDER BY. The page-level `--table` flag is no longer honored on these types.

**New modal form page that the IR above will drill into:**

```bash
uc-apx create page --id 43 --name "Department Form" --type form --table DEPT
```

**Blank page in a page group, with explicit alias:**

```bash
uc-apx create page --id 100 --name "Settings" --type blank --alias SETTINGS --page-group administration
```

### Managing page groups

`--page-group` is validated, so the group must exist first. The full page-group lifecycle:

```bash
uc-apx page-groups                                  # see groups + members + the ungrouped bucket
uc-apx create page-group administration --name "Administration"   # define a new group
uc-apx edit page --page 100 --page-group administration           # assign/move an existing page
uc-apx edit page --page 100 --clear-page-group                    # remove a page's group
uc-apx delete page-group administration              # remove the group (blocks if pages still reference it)
```

Assign and clear accept the group id **or** display name; a name is normalized to the id in the written `pageGroup: @<id>` reference.

**Blank modal dialog (non-form modal, e.g. confirmation):**

```bash
uc-apx create page --id 160 --name "Confirm Delete" --type modal-dialog
```

Creates a modal page with `pageMode: modalDialog`, a footer `buttons` region using `@/buttons-container`, a `Close` button wired to a `cancel-dialog` dynamic action (`action: cancelDialog`), and a `content` region in `slot: BODY` for you to drop content into.

To wire the parent page that opens this modal, use the standalone CLI commands instead of hand-editing:

```bash
# Button on the parent that opens the modal (passing a PK to the modal's PK item):
uc-apx create button redirect --page 100 --region <parent-region> \
    --label "Open Confirm" --target-page 160 --item-pair P160_ID=#ID#

# Add additional close-style buttons to the modal (auto-emits cancel-dialog DA):
uc-apx create button cancel --page 160 --region buttons --label "Close"

# Parent-side refresh after the modal closes (event: apexafterclosedialog):
uc-apx create dynamic-action refresh-on-dialog-close \
    --page 100 --refresh-region <parent-region> --trigger-button open-confirm
```

For a row-level "Edit pencil" column on an IR/CR that opens the modal per row, use `--trigger-region <region>` instead of `--trigger-button`, so the DA fires regardless of which row was clicked.

**Preview without writing:**

```bash
uc-apx create page --id 42 --name "Departments" --type blank --dry-run
```

**From an AI agent (default output is minified JSON — no flag needed):**

```bash
uc-apx create page --id 42 --name "Departments" --type interactive-report
```

## Interpreting the result

On success the command prints a result like:

```json
{
  "file": "pages/p00042-departments.apx",
  "pageId": 42,
  "name": "Departments",
  "alias": "DEPARTMENTS",
  "type": "interactive-report",
  "nextSteps": [
    "Add a list entry to shared-components/lists.apx so this page appears in navigation.",
    "Add a breadcrumb entry to shared-components/breadcrumbs.apx with parentEntry: @home (or your preferred parent)."
  ]
}
```

**Act on `nextSteps`.** The command intentionally does not touch `shared-components/`. After scaffolding:

- For non-modal pages (`blank`, `classic-report`, `interactive-report`, `interactive-grid`, `dashboard`) you usually need to append entries to `shared-components/lists.apx` and `shared-components/breadcrumbs.apx`.
- For modal `form` pages, wire a link column from the parent IR/IG row so the form opens for the selected row. No navigation entries needed.
- For `modal-dialog` pages, wire a button (or link) on the parent page with `behavior.action: redirectThisApp`, `target.page: <modal-id>` (use `uc-apx create button redirect`). If the parent should refresh after the dialog closes, run `uc-apx create dynamic-action refresh-on-dialog-close --page <parent> --refresh-region <region> --trigger-button|--trigger-region <id>`.

## Error cases to expect

| Error                                                      | Fix                                                                                  |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `page 42 already exists in pages/...`                      | Pick a different `--id`, or edit the existing page.                                  |
| `file pages/... already exists (use --force to overwrite)` | Use `--force` **only** if you intend to replace the file. Confirms with user first.  |
| `--id must be between 1 and 99998`                         | Page numbers are zero-indexed via `p00000` (global page) through `p99998`.           |
| `unknown page type "xyz"`                                  | Use one of the seven supported types.                                                |
| `generated page failed to parse: ...`                      | Bug in the tool. File is cleaned up automatically; report the template + flags used. |

## Common pitfalls

- **Don't invent custom `pageTemplate:` values.** The templates use `@/standard` (or `@/drawer` for form). Change only if you know the target theme exposes the template alias.
- **Don't rely on the default `SAMPLE` placeholder.** If the type is table-backed, pass `--table` with the real table.
- **Filename slug is best-effort.** Non-ASCII in `--name` is preserved in the content (`name:` value) but stripped from the filename slug — override with `--file` if you need specific casing/characters.
- **`--force` is narrow.** It only overrides the "file exists" check. It does **not** let you create a page with a duplicate ID in a different file.
- **Scaffolding is deliberately minimal.** The templates are starting points, not finished features. Expect to add columns, items, processes, validations, and customize appearance after generating.

## Verification checklist after scaffolding

1. `uc-apx page <id>` — confirms the new page parses and resolves.
2. `uc-apx tree <id>` — shows regions/items/buttons structure.
3. `uc-apx validate` — catches duplicate IDs and broken references across the app.
4. (If non-modal) Add list + breadcrumb entries; re-run `uc-apx validate`.

## Reference

- Command source: [cmd/create_page.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/create_page.go)
- Bundled templates: [assets/page-templates/](https://github.com/United-Codes/uc-apx/tree/main/assets/page-templates)
- Validation workflow: [skills/verify/validate-after-edit/SKILL.md](../validate-after-edit/SKILL.md)

## Validate before you declare done

After scaffolding, run validate from the app root:

```bash
uc-apx validate --app-dir <project-root>
```

If `sql` (SQLcl 26.1.2+) is on `$PATH`, prefer the full check:

```bash
uc-apx validate --app-dir <project-root> --official
```

**Do not declare the change done until validate exits clean.** If validate errors, read the file and line it reports, fix the issue, and re-run. See [skills/verify/validate-after-edit/SKILL.md](../validate-after-edit/SKILL.md) for how to interpret each issue kind.
