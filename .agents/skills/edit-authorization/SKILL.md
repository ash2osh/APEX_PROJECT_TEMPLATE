---
name: edit-authorization
description: Create, edit, and apply authorization schemes in an Oracle APEX apexlang project. Use when the user asks to add a new authorization scheme, change an existing one (rename, change the PL/SQL/SQL body or role list, change the type), gate a page/region/button/process/validation/list-entry/breadcrumb-entry behind a scheme, or remove authorization from a construct. Uses `uc-apx create/edit authorization` and `uc-apx edit <kind> --authz` instead of hand-editing.
---

# Editing authorization

Authorization in APEX has two halves: the **scheme** (defined once in `shared-components/authorizations.apx`) and the **references** to it (`security { authorizationScheme: @scheme }` on pages, regions, buttons, processes, etc.). This skill covers both — defining/changing schemes and applying them.

To *see* what already exists before changing it, use [skills/read/audit-authorization/SKILL.md](../../read/audit-authorization/SKILL.md).

## When to use this skill

- Add a brand-new authorization scheme.
- Change an existing scheme's name, type, body/roles, or error message.
- Gate (or un-gate) a page, region, button, process, validation, list entry, or breadcrumb entry.

**Do not** hand-edit `shared-components/authorizations.apx` — the commands below reparse and (optionally) run the official validator. **Do not** use this skill to delete a scheme — that's `uc-apx delete authorization <id>` (see [skills/edit/delete-component/SKILL.md](../delete-component/SKILL.md)).

## Defining schemes

```bash
# New scheme (body-shape types take --body; role-shape types take --names)
uc-apx create authorization --name "Administration Rights" --type plSqlFunctionBody \
  --body "return my_pkg.is_admin(:APP_USER);"
uc-apx create authorization --name "Editors" --type isInRoleOrGroup --names Editor --names Author

# Edit an existing scheme (only the flags you pass change; advanced/other blocks preserved)
uc-apx edit authorization --id administration-rights --name "Admin Rights"
uc-apx edit authorization --id administration-rights --body "return my_pkg.is_admin2(:APP_USER);"
uc-apx edit authorization --id editors --type isNotInRoleOrGroup        # same shape: roles kept
uc-apx edit authorization --id admins --error-message ""                # remove the error block
```

| `--type` | Payload flag | Settings shape |
|---|---|---|
| `plSqlFunctionBody` | `--body` (PL/SQL returning boolean) | body |
| `plSqlExpression` | `--body` (boolean PL/SQL expression) | body |
| `existsSqlQuery` / `notExistsSqlQuery` | `--body` (SQL query) | body |
| `isInRoleOrGroup` / `isNotInRoleOrGroup` | `--names` (repeatable) | roles |

`edit authorization` rewrites the `settings` block only when you pass `--type`, `--body`, or `--names`. Changing `--type` **across** shapes (body ↔ roles) requires the matching payload flag — the old settings can't be reinterpreted, so the command errors instead of guessing. `--body` accepts `@path/to/file.sql`.

## Applying schemes

Set or remove `security { authorizationScheme }` on a construct. Pass `--authz ""` (empty) to remove.

```bash
uc-apx edit page            --page 50 --authz administration-rights
uc-apx edit region          --page 50 --region access-control --authz administration-rights
uc-apx edit button          --page 50 --button save --authz contribution-rights
uc-apx edit process         --page 50 --process save-row --authz contribution-rights
uc-apx edit validation      --page 50 --validation salary-check --authz salary-admins
uc-apx edit list-entry      --id admin-dashboard --authz administration-rights
uc-apx edit breadcrumb-entry --id admin-dashboard --authz administration-rights
```

These leave sibling `security` properties (e.g. `pageAccessProtection`) intact.

## Negation

To gate a construct for everyone *except* a scheme's members, the value is `!@scheme` (e.g. a "forgot password" page gated `!@authenticated`). The `--authz` commands set the positive form; for the negated form, hand-edit the single `authorizationScheme:` line and then validate. Note negated uses don't show up in `uc-apx refs` — use `uc-apx auth usage` to see them.

## Decision matrix

| Goal | Command |
|---|---|
| New scheme | `create authorization` |
| Rename / change body / change roles / change type | `edit authorization` |
| Gate a page itself | `edit page --authz` |
| Gate a region/button/process/validation | `edit <kind> --page … --authz` |
| Gate a nav/breadcrumb entry | `edit list-entry`/`edit breadcrumb-entry --authz` |
| Remove a gate | same command with `--authz ""` |
| Remove a scheme entirely | `delete authorization <id>` |

## Common pitfalls

- **Don't gate the menu link but not the page (or vice versa).** `uc-apx validate` flags this as `authzNavMismatch`.
- **Don't gate a submit button without gating the process it triggers.** A hidden button doesn't stop a forged request; `validate` flags this as `authzButtonGateMismatch`. Apply the same scheme to the process with `edit process --authz`.
- **Don't change `--type` across shapes without the payload flag** — supply `--body` or `--names`.
- **Don't invent scheme ids.** Confirm with `uc-apx auth schemes` (or `list authorization`) first; a typo'd `@scheme` becomes a broken reference.

## Reference

- Command sources: [cmd/create_authorization.go](../../../cmd/create_authorization.go), [cmd/edit_authorization.go](../../../cmd/edit_authorization.go), [cmd/edit_page.go](../../../cmd/edit_page.go), [cmd/edit_authz_shared.go](../../../cmd/edit_authz_shared.go)
- Auditing authorization: [skills/read/audit-authorization/SKILL.md](../../read/audit-authorization/SKILL.md)
- Validation workflow: [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md)

## Validate before you declare done

After any change, run validate from the app root:

```bash
uc-apx validate --app-dir <project-root>
```

If `sql` (SQLcl 26.1.2+) is on `$PATH`, prefer the full check:

```bash
uc-apx validate --app-dir <project-root> --official
```

**Do not declare the change done until validate exits clean.** If validate errors, read the file and line it reports, fix the issue, and re-run. See [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md) for how to interpret each issue kind.
