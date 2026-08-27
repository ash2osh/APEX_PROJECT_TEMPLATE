---
name: analyze-db-dependencies
description: Use `uc-apx schema` to find which database objects (tables, views, packages, functions) an apexlang app touches and where each is used. Reach for it for impact analysis ("what breaks if I drop table X", "which pages call package Y", "what does this app read"), data-model orientation before an edit, or auditing external-schema coupling. It is a heuristic static scan of SQL/PL-SQL text — no database connection — so treat results as leads to verify, not gospel.
---

# Analyzing an app's database dependencies

`uc-apx schema` statically scans every SQL and PL/SQL fragment in the app — region
sources, processes, computations, validations, LOVs, dynamic actions,
`source.tableName`, where-clauses — and reports the database objects referenced,
each with the constructs that use it.

## When to use this skill

- **Impact analysis** — "If I rename/drop `EBA_CUST_CUSTOMERS`, what regions/processes break?" → `uc-apx schema --object EBA_CUST_CUSTOMERS`.
- **Data-model orientation** — new to an app, want the list of tables/views/packages it depends on before editing. → `uc-apx schema`.
- **External-coupling audit** — which objects are *not* shipped by the app's own install scripts (so they must already exist in the target schema). → look for `local: false` objects.
- **Find callers of a package** — "where is `EBA_CUST_FW` invoked?" → `uc-apx schema --object EBA_CUST_FW`.

This is the DB-object counterpart to [inspect-construct-schema](../inspect-construct-schema/SKILL.md): that one tells you the *apexlang* shape of a construct; this one tells you the *database* objects the app reads and writes.

## Synopsis

**Tiered output.** `schema` is summary-first to stay token-cheap: the bare command lists
objects + counts only and **omits** the per-object `usages[]`. Drill in for usage sites
with `--object <NAME>` (one object) or `--detail` (every object). Lead with the summary,
then drill into the object you care about — don't reach for `--detail` reflexively (on a
large app it's ~20× the bytes).

```bash
uc-apx schema --app-dir <root>                      # summary: app objects + refCount, no usages
uc-apx schema --app-dir <root> --object <NAME>      # one object + its usage sites
uc-apx schema --app-dir <root> --detail             # every object + all usage sites (large)
uc-apx schema --app-dir <root> --type table         # only one inferred type
uc-apx schema --app-dir <root> --builtins           # only the APEX/Oracle built-ins it calls
```

Output shape (minified JSON by default; `--json-pretty` / `--toon` for humans). The
`usages[]` array shown below is present only with `--object` / `--detail`. APEX/Oracle
built-ins are excluded from this default list (the summary still counts them via
`builtinCount` — run `--builtins` to see them):

```jsonc
{
  "objects": [
    {
      "name": "EBA_CUST_CUSTOMERS",
      "type": "table",            // refined from local DDL; else "table-or-view"
      "local": true,              // app ships its CREATE under supporting-objects/
      "builtin": false,
      "refCount": 83,
      "usages": [                 // only with --object / --detail
        { "kind": "region", "id": "...", "name": "...",
          "file": "pages/p00001-dashboard.apx", "line": 48,
          "property": "source.sqlQuery", "language": "sql" }
      ]
    }
  ],
  "summary": { "objectCount": 53, "builtinCount": 40,
               "byType": {"table": 47, "package": 4, "table-or-view": 2},
               "note": "Heuristic static analysis …" }
}
```

## Reading the output

| Field | Meaning |
|---|---|
| `type: table` / `view` / `package` / `function` / … | Refined by matching a `CREATE` statement in the app's shipped DDL. Trustworthy. |
| `type: table-or-view` | Found in a FROM/DML position; the app ships no DDL for it, so table-vs-view is unknown. |
| `type: program-unit` | Reached via a dotted call (`pkg.proc(...)`); no local DDL to confirm it's a package/function. |
| `local: true` | The app's install/upgrade scripts create this object. |
| `local: false` | Referenced but not created here — it must pre-exist in the target schema (external coupling). |
| `builtin: true` | Oracle/APEX-supplied (`APEX_*`, `DBMS_*`, `HTP`, dict views). Excluded from the default output (counted in `summary.builtinCount`); appears only under `--builtins`. |
| `usages[]` | Every construct referencing the object: kind, id, `file:line`, the property path, and the language. **Present only with `--object` / `--detail`** — the default summary carries `refCount` instead. |

## Limitations — it is heuristic, not authoritative

The command has **no database connection**. The `summary.note` says so, and it matters:

- **Table vs. view** is a guess unless the app ships the object's DDL.
- **Dynamic SQL** assembled from string concatenation (`'select … from ' || l_tab`) is invisible.
- **Bare program calls** (`my_proc(...)` with no package qualifier) are not attributed — too ambiguous with SQL built-in functions.
- **PL/SQL local variables / record params** occasionally surface as `program-unit` false positives (e.g. a plugin's `p_region` record).

Use it to find *where to look*, then confirm against the actual source or database before acting.

## Workflow: rename-impact check

```bash
# 1. Where is the table used, and by what?
uc-apx schema --app-dir <root> --object EBA_CUST_CUSTOMERS

# 2. Open each usage site to see the exact SQL/PL-SQL.
uc-apx component <usage.id> --app-dir <root>

# 3. After your edits, re-run to confirm the old name is gone.
uc-apx schema --app-dir <root> --object EBA_CUST_CUSTOMERS   # → empty objects[]
```

## Combining with `jq`

```bash
# External (non-local, non-builtin) objects the target schema must already have:
uc-apx schema --app-dir <root> | jq '.objects[] | select(.local == false) | .name'

# Tables touched by more than 10 constructs (the app's hot data):
uc-apx schema --app-dir <root> | jq '.objects[] | select(.refCount > 10) | {name, refCount}'
```

## Reference

- Command: [cmd/schema.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/schema.go)
- Extraction core: [dbdeps/extract.go](https://github.com/United-Codes/uc-apx/blob/main/dbdeps/extract.go), [dbdeps/ddl.go](https://github.com/United-Codes/uc-apx/blob/main/dbdeps/ddl.go)
- Construct-shape counterpart: [inspect-construct-schema](../inspect-construct-schema/SKILL.md)
