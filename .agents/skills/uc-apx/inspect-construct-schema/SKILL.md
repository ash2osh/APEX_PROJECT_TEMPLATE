---
name: inspect-construct-schema
description: Use `uc-apx shape <kind>` to discover what properties, blocks, child kinds, and block-paths are conventional for an apexlang construct in this app. Use before hand-editing a region, pageItem, button, process, etc. to learn what property names and structures other instances use, so your edit matches existing patterns instead of inventing keys the validator will reject.
---

# Inspecting the schema of an apexlang construct kind

`uc-apx shape <kind>` scans every instance of `<kind>` in the app and reports the union of properties, blocks, child kinds, and block-paths seen — each with a count of how many instances use it. It's the right tool when you're about to hand-edit a construct and want to know what's idiomatic *in this app*.

## When to use this skill

- You're hand-editing a component (`region`, `pageItem`, `button`, `process`, `lov`, …) and need to pick the right property name.
- You're adding a feature (e.g. "let this region paginate") and want to find an existing instance that uses the relevant block (`pagination`) so you can pattern-match.
- You want to know how rare or common a property is — common ones (count ≈ total instances) are required/default; rare ones are opt-in.

**Do not** use this skill to discover the **database schema** of tables the app reads. The `shape` command inspects apexlang-construct shape, not Oracle table columns.

## Synopsis

```bash
uc-apx shape <kind> --app-dir <root>
```

Output shape:

```yaml
kind: region
instanceCount: 142
properties:
  name: 142
  type: 142
blocks:
  appearance: 139      # 139/142 regions have an appearance block
  layout: 142
  source: 118
  pagination: 26
  ...
childKinds:
  column: 36           # 36 regions have child columns
  filter: 3
  series: 1
  ...
blockProperties:
  appearance.template: 142
  layout.sequence: 142
  layout.slot: 140
  source.tableName: 47
  source.sqlQuery: 71
  ...
```

## Reading the counts

| Pattern | Interpretation |
|---|---|
| `count == instanceCount` | Required or always-set property — your new instance probably needs it too. |
| `count` close to `instanceCount` | Conventional — most instances have it. Reasonable default to include. |
| `count == 1` | One-off / rare. Either an edge case or a copy-paste residue. Don't pattern-match this. |
| Property absent from the list | Not used anywhere in this app. Doesn't mean invalid — but if you add it, verify with `uc-apx validate --official`. |

## Workflow: pattern-match before hand-editing

```bash
# 1. What does a region typically have?
uc-apx shape region --app-dir <root>

# 2. Find an existing instance using the block you want to copy.
uc-apx search pagination --app-dir <root>

# 3. Read the full property tree of that instance for the exact syntax.
uc-apx component APEX$<id> --app-dir <root>

# 4. Apply the same shape in your edit. Then validate.
uc-apx validate --app-dir <root>
```

## Worked example — adding a chart to a page

```bash
# Step 1: confirm chart-related constructs exist in this app.
uc-apx shape region --app-dir examples/brookstrut
# → blocks include "chart", "chartLayout", "legend"; childKinds include "axis", "series", "layer"

# Step 2: find a real chart region to copy from.
uc-apx search chart --app-dir examples/brookstrut

# Step 3: dump the full structure of the chart region.
uc-apx component <id> --app-dir examples/brookstrut

# Step 4: replicate the structure in your target page, swap data sources, validate.
```

## Common kinds to inspect

| Kind | What you'll learn |
|---|---|
| `page` | App-wide page conventions: which appearance.pageTemplate values are used, common security settings. |
| `region` | All region types in use, common blocks (`source`, `pagination`, `attributes`, `appearance`). |
| `pageItem` | Item types, common appearance/validation/conditional-display patterns. |
| `button` | Common button-action patterns (submit, redirect, dynamicAction). |
| `process` | PL/SQL vs builtin processes, common timing values. |
| `lov` | Static-values vs SQL-query LOVs. |

## Combining with `jq`

Default output is minified JSON — pipe directly to `jq` without any flag:

```bash
uc-apx shape region --app-dir <root> | jq '.blockProperties[] | select(.count == 142)'
```

Returns block-properties present on every region (always-set conventions). Use `--json-pretty` for human-readable inspection without `jq`.

## Common pitfalls

- **Schema is per-app, not per-MMD.** It reflects how *this* app is built, not the full set of valid APEX properties. For full-schema validation, use `uc-apx validate --official`.
- **Don't assume a block-property is required just because count == instanceCount.** It might be that all current instances coincidentally set it. Confirm against the official validator if in doubt.
- **Don't `uc-apx shape` to discover DB-table schema.** That's not what it does. To see which database **objects** (tables, views, packages, …) the app references across all its SQL/PL-SQL, use `uc-apx schema` (see [analyze-db-dependencies](../analyze-db-dependencies/SKILL.md)).

## Reference

- Schema source: [cmd/shape.go](../../../cmd/shape.go)
- Validation: [skills/verify/validate-after-edit/SKILL.md](../../verify/validate-after-edit/SKILL.md)
