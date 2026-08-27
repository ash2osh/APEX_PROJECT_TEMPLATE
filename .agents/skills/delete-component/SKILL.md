---
name: delete-component
description: Remove a region, page item, button, process, dynamic action, computation, validation, branch, column, lov, list, breadcrumb, authorization, page group, list/breadcrumb entry, or whole page from an apexlang app. Use when the user asks to "delete", "remove", "drop", "get rid of", or "prune" any existing apexlang construct. The `uc-apx delete` family handles every kind; never hand-edit `.apx` files for deletion.
---

# Deleting components from an apexlang app

The `uc-apx delete <kind>` family is the inverse of `uc-apx create <kind>`. Every subcommand:

1. Looks up the target by id (or name where applicable).
2. **Blocks by default** when any other construct references the target. `--force` overrides with a stderr warning listing what it's about to break.
3. Splices the construct out of its file (or removes the whole file, for `delete page`), preserving canonical blank-line separators between siblings.
4. Reparses to fail-fast on a broken splice — and restores the original on parse failure so you never end up with a half-deleted file on disk.

Use `--dry-run` first whenever you're not 100% sure what will go.

## When to use this skill

- The user asks to delete / remove / drop / get rid of an apexlang construct.
- A previous create command was a mistake and needs to be reversed.
- An obsolete page / LOV / breadcrumb needs to be retired.

**Do not** use this skill when:

- You only want to remove a single block from a construct (e.g. "drop the LOV from this column but keep the column itself"). Use `uc-apx edit column` instead — `delete` only operates at whole-construct granularity.
- The user wants to rename or move a construct. There is no `mv` — recreate at the new location, then delete the old one, both with `uc-apx`.

## Decision matrix

| To remove… | Command | Required flags |
|---|---|---|
| a region (with all its children) | `uc-apx delete region <id>` | `--page <p>` |
| a pageItem | `uc-apx delete page-item <id-or-name>` | `--page <p>` |
| a button | `uc-apx delete button <id-or-name>` | `--page <p>` |
| a process | `uc-apx delete process <id-or-name>` | `--page <p>` |
| a dynamic action | `uc-apx delete dynamic-action <id-or-name>` | `--page <p>` |
| a computation | `uc-apx delete computation <id-or-name>` | `--page <p>` |
| a validation | `uc-apx delete validation <id-or-name>` | `--page <p>` |
| a branch | `uc-apx delete branch <id-or-name>` | `--page <p>` |
| a column inside an IG / CR / IR | `uc-apx delete column <id>` | `--page <p> --region <r>` |
| a whole page (file + cross-refs scan) | `uc-apx delete page <id-or-alias-or-name>` | — |
| a shared-component LOV | `uc-apx delete lov <id-or-name>` | — |
| a shared-component list | `uc-apx delete list <id-or-name>` | — |
| a shared-component breadcrumb | `uc-apx delete breadcrumb <id-or-name>` | — |
| a shared-component authorization scheme | `uc-apx delete authorization <id-or-name>` | — |
| a page group | `uc-apx delete page-group <id-or-name>` | — (blocks while pages still reference it; clear them first with `uc-apx edit page --clear-page-group`) |
| a list entry | `uc-apx delete list-entry <id>` | `--list <l>` (defaults to the only list if unambiguous) |
| a breadcrumb entry | `uc-apx delete breadcrumb-entry <id>` | `--breadcrumb <b>` (defaults to the only breadcrumb if unambiguous) |

Every command also accepts the global `--app-dir <path>` and the shared `--dry-run` and `--force` flags.

## Dry-run first

`--dry-run` runs the entire ref-check + splice pipeline, prints the same DeleteResult JSON (or TOON with `--toon`), then exits without writing. Use it when:

- You're not sure the target id is right (the dry-run errors clearly when not).
- You want to see the referrer report before deciding whether `--force` is appropriate.
- You're scripting and want to verify "yes, this delete would succeed cleanly" before the destructive run.

```
uc-apx --app-dir my-app delete region predictions --page 50 --dry-run
```

## Ref-safety (the `--force` decision)

Every delete consults the cross-reference index for incoming references. There are two flavours:

1. **`@alias` references** — captured by the built-in reverse index. Examples: `lov: @colors`, `layout.region: @breadcrumb`, `appearance.parentEntry: @home`.
2. **Bare integer page references** — for `delete page` only. The scanner walks every node's properties (and nested block properties) for an allowlist of property names that hold a page number as a plain integer: `page`, `targetPage`, `dialogTargetPage`, `homePage`, `errorPage`, `sessionExpiredPage`, `pageNumber`. Catches branches, breadcrumb entries, list entries, the app's home page, and most cross-page button redirects.

When **any** referrer exists, the command blocks and exits non-zero with a referrer list. The default expectation is: read the list, decide whether to update or delete the referrers first (with another `uc-apx delete`, or an `Edit` to rewrite the property), then retry.

Use `--force` when:

- You're deliberately tearing down a whole feature and the referrers will be deleted next.
- The referrer is in code (SQL / PL/SQL / JavaScript) that you've already updated by hand.
- You're operating on a freshly-scaffolded fixture and want to undo the scaffold quickly.

`--force` writes the file and prints the referrer list as a stderr warning. After a forced delete, `apex validate --official` is **very likely to reject the file** — that's expected, and it's how you find the remaining edges to fix.

## Whole-page delete caveat

`uc-apx delete page` is *file removal*, not a splice. The int-page allowlist is deliberately finite (seven property names) — references inside SQL queries, PL/SQL bodies, JavaScript, or HTML are **not** visible to it. After every page deletion:

1. Run `uc-apx validate --official` to surface anything the allowlist missed.
2. Spot-check the app's `homePage` attribute, any pages whose branches might land here, and any list / breadcrumb / button that links to the deleted page number.

If `--official` reports new errors, fix them by editing or by running more `uc-apx delete` commands.

## Mandatory validate gate

After **every** successful delete (whether forced or not), run:

```
uc-apx --app-dir <root> validate --official
```

Treat `official.success == true` as the success criterion. The local `validate` (without `--official`) is structural-only and misses most things the SQLcl validator catches. See [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md) for the canonical gate.

If SQLcl is not on `$PATH`, fall back to `uc-apx validate` (no `--official`), but flag this to the user — local-only is lossy and the work isn't truly verified.

## Concrete examples

**Drop a region after confirming what it does:**
```
uc-apx --app-dir app page 50               # see what's on the page
uc-apx --app-dir app refs predictions      # see who points at @predictions
uc-apx --app-dir app delete region predictions --page 50 --dry-run
uc-apx --app-dir app delete region predictions --page 50
uc-apx --app-dir app validate --official
```

**Retire an unused LOV:**
```
uc-apx --app-dir app refs old-colors       # confirm zero refs
uc-apx --app-dir app delete lov old-colors
uc-apx --app-dir app validate --official
```

**Reverse a freshly created button (no ref-safety drama because nothing has been wired up yet):**
```
uc-apx --app-dir app delete button save-changes --page 50
```

**Tear down a whole page and follow up on its dangling refs:**
```
uc-apx --app-dir app delete page 14 --dry-run    # read the referrer list
# fix or delete the referrers, then…
uc-apx --app-dir app delete page 14
uc-apx --app-dir app validate --official         # mandatory follow-up
```

## Common pitfalls

- **Forgetting `--region` on `delete column`.** Cobra will error with "required flag(s) not set"; just add it.
- **Using `--force` reflexively.** If the dry-run lists referrers, treat that as load-bearing information — the referrers usually need to be addressed too. `--force` is appropriate only when you've already decided what to do with them.
- **Trusting local validate after a forced delete.** Always run `--official`. A clean local-only run on a `--force`-mutated app is meaningless.
- **Confusing `delete page` with deleting a page's content.** `delete page` removes the whole `.apx` file. To empty a page, delete its children individually.

## Reference

- Source: [cmd/delete.go](../../../cmd/delete.go), [cmd/delete_helpers.go](../../../cmd/delete_helpers.go), and the per-kind files (`delete_page_children.go`, `delete_column.go`, `delete_page.go`, `delete_shared_components.go`).
- Tests: [delete_e2e_test.go](../../../delete_e2e_test.go) — happy paths, ref-blocked, --force, --dry-run, official-validate gate.
- Cross-link: [skills/edit/add-region-or-item-to-page/SKILL.md](../add-region-or-item-to-page/SKILL.md) covers the inverse (create).
