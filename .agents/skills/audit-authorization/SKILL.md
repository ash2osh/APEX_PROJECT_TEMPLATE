---
name: audit-authorization
description: Get a whole-app view of authorization in an Oracle APEX apexlang project — which authorization schemes exist, where each is applied, which are unused, and which pages have no authorization. Use when the user asks "what auth schemes do we have", "where is scheme X used", "which pages are unprotected", "find unused authorization schemes", or wants a security/authorization review. Uses `uc-apx auth` instead of grepping for `authorizationScheme`.
---

# Auditing authorization

Authorization in APEX is scattered: schemes live in `shared-components/authorizations.apx`, but the references (`security { authorizationScheme: @scheme }`) are spread across every page, region, button, process, list entry, and breadcrumb. This skill gives you the whole-app view in one command instead of grepping.

## When to use this skill

- The user wants to know what authorization schemes exist and how heavily each is used.
- The user asks where a specific scheme is applied (so they can change or remove it safely).
- The user wants a security pass: unused schemes, pages with no authorization.
- You're about to edit or delete an authorization scheme and need its usage first.

**Do not** use this skill to *change* authorization — that's [skills/edit/edit-authorization/SKILL.md](../../edit/edit-authorization/SKILL.md). Use this to *understand* it first.

## The 3-command toolbox

| Command | Use it when |
|---|---|
| `uc-apx auth schemes` | You want every scheme with a usage count. The `usedBy[]` list is omitted by default (token-cheap) — add `--detail` for all schemes, or `--scheme <id>` to focus one. Add `--unused` for leftover schemes. |
| `uc-apx auth usage` | You want a flat list of every construct that carries an `authorizationScheme`. Add `--scheme <id>` to filter. |
| `uc-apx auth audit` | You want the anomalies: unused schemes + pages with no authorization. |

## Why not `refs` / `grep`?

**Negation does not parse as a reference.** A page gated by `authorizationScheme: !@is-admin` (everyone *except* admins) is a real use of `is-admin`, but `uc-apx refs is-admin` and a naive `grep '@is-admin'` both miss or miscount it. The `auth` commands read raw values and report each use with a `negated` flag, so counts and the unused-scheme audit are correct. Prefer them over `refs` for any authorization coverage question.

## Worked example — scheme inventory

```bash
uc-apx --app-dir . auth schemes            # summary: counts only, no usedBy
uc-apx --app-dir . auth schemes --detail   # include usedBy for every scheme
uc-apx --app-dir . auth schemes --scheme administration-rights   # one scheme + its usedBy
```

```json
// default (summary): usedBy omitted, usageCount kept
{"schemes":[
  {"id":"administration-rights","type":"plSqlFunctionBody","usageCount":139},
  {"id":"application-sentry","usageCount":1,"appDefault":true},
  {"id":"copy-of-administration-rights","usageCount":0}
],"total":6}
```

- `usageCount` counts positive **and** negated uses, plus the app-level default.
- `appDefault: true` marks the scheme set on the application itself (`authorization { scheme: @x }`) — it is "used" even with no per-component reference, so it is never reported unused.
- `usedBy[]` (only with `--detail` / `--scheme`) carries each use's `kind`, `pageId`, `property` (e.g. `security.authorizationScheme`), `negated`, and `file:line`.

## Worked example — security pass

```bash
uc-apx --app-dir . auth audit
```

```json
{"unusedSchemes":[{"id":"copy-of-administration-rights","usageCount":0}],
 "unprotectedPages":[{"kind":"page","id":"13"}, ...],
 "summary":{"schemeCount":6,"unusedCount":1,"unprotectedPageCount":39}}
```

- **`unprotectedPages`** = pages with no `security.authorizationScheme`, excluding the global page 0 and deliberately-public pages (those carry `security { authentication: public }`, e.g. login). A page here isn't necessarily a bug — many pages inherit access from the app authentication — but it's the list to review.
- **`unusedSchemes`** = schemes nothing references (most often a leftover `copy-of-…`). Remove with `uc-apx delete authorization <id>` or start using them.

## Decision matrix

| You want… | Command |
|---|---|
| Every scheme + how used | `auth schemes` |
| Only unused schemes | `auth schemes --unused` |
| One scheme's usages | `auth schemes --scheme <id>` (or `auth usage --scheme <id>`) |
| Flat list of all auth references | `auth usage` |
| Unused schemes + unprotected pages | `auth audit` |
| Consistency warnings (nav-link vs page, button-gate vs process) | `uc-apx validate` — see [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md) |

## Common pitfalls

- **Don't equate "unprotected page" with "vulnerability".** Pages inherit the app authentication; the audit only flags the absence of a *page-level authorization scheme*. Treat it as a review list.
- **Don't use `refs` to decide a scheme is unused** — it misses negated uses. Use `auth schemes --unused`.
- **`copy-of-<scheme>` schemes** are created by APEX's "copy" action and are usually dead — but confirm with `auth schemes --scheme copy-of-…` before deleting.

## Reference

- Command source: [cmd/auth.go](../../../cmd/auth.go)
- Scanning logic (negation-aware): [cmd/authz_scan.go](../../../cmd/authz_scan.go)
- Consistency checks: [cmd/validate_authz.go](../../../cmd/validate_authz.go)
- Changing authorization: [skills/edit/edit-authorization/SKILL.md](../../edit/edit-authorization/SKILL.md)
