---
name: validate-after-edit
description: Verify an apexlang application with `uc-apx validate` (and the official SQLcl `apex validate` when available) after any edit. Use after creating, modifying, or hand-editing any `.apx` file in an apexlang project, before declaring the change done. Explains how to interpret each issue kind the validator reports.
---

# Validating apexlang changes

After any edit to an apexlang project, you must run validate before declaring the change done. This skill is the canonical workflow that every other edit skill links to.

## When to use this skill

- You (or another skill) just modified a `.apx` file: scaffold, hand-edit, refactor.
- You want to sanity-check an apexlang project before importing it back into APEX Builder.
- A previous validate run reported errors and you want to interpret them.

**Do not** use this skill for general APEX troubleshooting — it does not run the app, query the DB, or check runtime behavior. It checks file structure and (with `--official`) the MMD schema.

## Two layers of validation

| Layer | Command | What it catches | Speed |
|---|---|---|---|
| Local (default) | `uc-apx validate --app-dir <root>` | Broken `@xxx` references, duplicate IDs, missing names, empty pages, duplicate page numbers | <100ms |
| Official (SQLcl) | `uc-apx validate --app-dir <root> --official` | Everything above **plus** invalid property names, wrong value types, invalid component nesting, MMD-schema violations | seconds (SQLcl boot) |

**Use `--official` as the completion gate whenever SQLcl 26.1.2+ is on `$PATH`.** The local check is structural-only and cannot catch invalid property names, wrong value types, missing required children, or invalid component nesting. A local pass with `--official` failing has shipped broken apps — don't declare done on local-only output when SQLcl is available.

If SQLcl is not available, the local layer is the best you have; tell the user it's a structural-only signal and that they should re-run with `--official` before importing into APEX Builder.

## Detecting SQLcl

```bash
command -v sql && echo "sql is available" || echo "sql is missing"
```

- If `sql` is on `$PATH` and is SQLcl 26.1.2 or newer → run `uc-apx validate --official`.
- If `sql` is missing → run `uc-apx validate` (local only). Optionally suggest the user install SQLcl 26.1.2+ for stricter checks.
- If `sql` is installed at a non-standard path → pass `--sql-bin /path/to/sql`.

## Exit codes and shape

- **Exit 0**: `valid: true`, zero errors. Warnings may still be present — read them, don't ignore.
- **Exit non-zero**: at least one error. Read every error before fixing.

JSON output shape (default output is minified JSON — no flag needed for agents; use `--json-pretty` for human-readable inspection):

```json
{
  "valid": false,
  "errors": [ { "severity": "error", "kind": "brokenReference", "message": "...", "file": "pages/p00042-foo.apx", "line": 17 } ],
  "warnings": [ ... ],
  "summary": { "errorCount": 1, "warningCount": 0 },
  "official": {
    "tool": "sqlcl apex validate",
    "success": false,
    "exitCode": 0,
    "stdout": "APEXLang Compile Errors:\nFile: ...\nLine: ...\nType: INVALID_PROPERTY\nError: ..."
  }
}
```

## Interpreting each issue kind (local)

| Kind | Meaning | How to fix |
|---|---|---|
| `brokenReference` | An `@xxx` reference doesn't resolve to any indexed component. | Confirm the target exists; check spelling; if it's a same-page sibling, confirm the alias matches an existing region/item identifier in the same `.apx` file. |
| `duplicateID` | Two components share an `ID`. | Most often an item/column name reused across pages — usually a false positive for the local check, which doesn't enforce scope. Investigate before "fixing"; rename only if both definitions truly live in the same scope. |
| `duplicatePageID` | Two `page N (` blocks claim the same number. | Pick a different page number for the newer file, or delete the duplicate. |
| `missingName` | A component that requires a `name:` property doesn't have one. As of 2026-05 the validator uses an allowlist of MMD kinds that take `name:` (`region`, `process`, `dynamicAction`, `lov`, `page`, `authorization`, `customAttribute`, …). Kinds that use a label-shaped property (`pageItem.label.label`, `button.buttonName`, `column.heading.heading`) — and kinds where `name:` is optional in MMD (`branch`, `entry`, `parameter`, `savedReport`) — are not on the allowlist and will not produce this warning. | Add `name: <human-readable>` near the top of the component's property list. **Do not** inject `name:` into a construct that wasn't flagged; the official validator will reject it. |
| `emptyPage` | A page (other than page 0) has zero children. Page 0 is the global page and is legitimately empty in many apps, so the check skips it. | Either flesh out the page with at least one region/button, or remove the page if unused. |
| `authzNavMismatch` | A list entry links to a page whose `security.authorizationScheme` differs from the entry's (one gated and the other not, different schemes, or opposite negation). The classic smell: a menu link visible to users who can't open the target page, or a page reachable unprotected via a gated link. | Decide which side is authoritative and align them with `uc-apx edit list-entry --authz` and/or `uc-apx edit page --authz`. Heuristic across **all** page-linking lists, so a content/card list that intentionally points to differently-gated pages is acceptable noise — confirm before "fixing". |
| `authzButtonGateMismatch` | A process / validation / computation / branch fires on `whenButtonPressed: @<btn>` where the button is gated by an authorization scheme the server-side logic isn't. APEX hides the button client-side, but the logic still runs on a forged request. Suppressed when the page's own auth already equals the button's. | Add the same scheme to the gated construct with `uc-apx edit process\|validation --authz <scheme>` (or gate the whole page). |
| `unusedAuthorization` | An `authorization` scheme is defined but nothing references it (positive **or** negated). Often a leftover `copy-of-…` scheme. | Reference it from a page/region/button/entry, or delete it with `uc-apx delete authorization <id>`. The check is negation-aware — a scheme used only via `!@scheme` counts as used. |

## Interpreting `--official` output

The SQLcl output uses `Type: <CODE>` lines. Common codes:

| Type | Meaning | How to fix |
|---|---|---|
| `INVALID_VERSION` | The app's `mmdVersion` (`.apex/apexlang.json`) is older than the installed SQLcl supports. | Use a SQLcl release that matches the export's mmdVersion, or re-export from a current APEX Builder. |
| `INVALID_PROPERTY` | A property name is not valid for this component type. | Check the spelling against an existing working example of the same component type. Common typos: `primaryKe`, `numbe`, `tempalte`. |
| `REFERENCE_NOT_FOUND` | An `@xxx` reference doesn't resolve. | Same fix as the local `brokenReference`. The official check is broader because it also validates references to system templates (`@/standard`). |
| `INVALID_VALUE` | The value doesn't match the property's allowed values (enum, datatype). | Check the MMD docs or an existing example; many properties only accept a fixed set of strings. |

## Failure recovery loop

1. Read the first error line carefully — file + line + kind.
2. Open the file at the reported line.
3. Apply the smallest fix that addresses the reported cause.
4. Re-run `uc-apx validate`.
5. Repeat until exit 0.

Resist the urge to fix multiple errors in one pass without re-running — a single root cause often produces several cascading errors.

## Common pitfalls

- **`brokenReference` baseline noise.** Every scaffolded app references system templates (`@/standard`, `@/title-bar`, `@/breadcrumb`, `@/required-floating`, …) that the local validator can't resolve — it has no inventory of APEX's built-in theme/template library. As of 2026-05 the local validator **skips these by default** so empty-app reports zero broken refs. If you need to audit them, pass `--strict-system-refs` to bring them back.
- **PL/SQL processes use `type: executeCode`, not `type: plsqlCode`.** The natural-sounding `plsqlCode` is rejected by `--official` with `INVALID_PROPERTY`. The canonical shape is `process X ( name: ... type: executeCode source { plsqlCode: ```plsql ... ``` } execution { sequence: 10 point: beforeHeader } )`. Use `uc-apx create process plsql ...` so you never type the wrong shape; for hand-edits, model on an existing example app.
- **`duplicateID` false positives.** The local check is scope-blind, so column names like `STORE_ID` reused across pages will all flag. Don't rename them based on the local check alone — confirm with `--official` or by inspection.
- **Don't fabricate properties to silence local warnings.** If the local check disagrees with `--official` (or with a working example), trust the official one. Hand-injecting `name:` into a `pageItem` or `column`, for example, makes the local check happy but the official one fail — Oracle's MMD does not allow it. Past agents have done exactly this; don't repeat it.
- **`emptyPage` is a warning, not an error.** Empty pages happen during refactors; the warning is a nudge, not a blocker.
- **Don't suppress warnings.** They surface in CI/automation; treat them like compiler warnings — investigate, then either fix or accept knowingly.
- **`--official` boots a JVM.** Each invocation takes a few seconds. Don't loop-call it on every keystroke — run it at well-defined checkpoints (after a coherent change, before "done").

## Reference

- Validator source: [cmd/validate.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/validate.go)
- Output types: [output/json.go](https://github.com/United-Codes/uc-apx/blob/main/output/json.go) — `ValidationResult`, `ValidationIssue`, `OfficialValidation`
- CLI overview: [CLAUDE.md](https://github.com/United-Codes/uc-apx/blob/main/CLAUDE.md)
