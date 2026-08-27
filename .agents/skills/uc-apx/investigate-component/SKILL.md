---
name: investigate-component
description: Find the responsible apexlang construct given a symptom or keyword in an Oracle APEX project. Use when the user reports a problem ("the salary update is wrong", "this LOV shows stale data") and you need to locate the page, region, or shared component to investigate before editing. Combines `uc-apx search`, `refs`, `deps`, and `component` instead of grepping.
---

# Investigating a component

The user gives you a symptom; you need to find the apexlang construct(s) responsible. This skill is the search → narrow → drill workflow. It's the read-only complement to the edit skills.

## When to use this skill

- The user describes a behavior or value (a column name, a SQL fragment, a button label, a JavaScript snippet) and you need to locate the construct.
- You're about to edit a shared component and want to see every place it's used first.
- You need to understand a component's upstream/downstream dependencies before changing it.

**Do not** use this skill for orientation — that's [skills/read/navigate-app/SKILL.md](../navigate-app/SKILL.md). Use this *after* you know roughly where to look.

## The 4-command toolbox

| Command | Use it when |
|---|---|
| `uc-apx search <term>` | You have a string (column name, SQL keyword, button label, JS variable) but don't know where it appears. |
| `uc-apx component <id\|name>` | You have an exact identifier and want the component's properties + a list of its children. Add `--detail` for the full recursive property tree. |
| `uc-apx refs <id>` | You have a shared component (LOV, list, authorization) and want to see who uses it. |
| `uc-apx deps <id>` | You want the dependency graph in both directions (upstream + downstream). |

## Workflow: symptom → construct

```
1. Free-text the symptom              → uc-apx search <keyword>
2. Pick the most likely hit           → uc-apx component <id> (or uc-apx page <id>)
3. If shared, list usages             → uc-apx refs <id>
4. If changing it might break things  → uc-apx deps <id>
```

## Worked example — finding misbehaving SQL

User says: "the Sales History region shows wrong totals when filtered by store."

```bash
# 1. Find any construct whose SQL or name mentions the keyword.
uc-apx search "sales history" --app-dir examples/brookstrut
# → page 2 region "Sales History" at pages/p00002-sales-history-content-row.apx:48
# → page 13 region "Sales History (Classic)" at pages/p00013-sales-history-classic.apx:...
# → lov "SALES HISTORY NAVIGATION" at shared-components/lovs.apx:63

# 2. Inspect the most likely region.
uc-apx component APEX$50764435396818709550 --app-dir examples/brookstrut
# → full property dump including source.sqlQuery — read the SQL.

# 3. If the SQL references a shared LOV that filters by store, find its usages.
uc-apx refs APEX$13966104307485518519 --app-dir examples/brookstrut
# → every page item / region that uses the LOV.

# 4. If you might change the LOV, see what depends on it.
uc-apx deps APEX$13966104307485518519 --app-dir examples/brookstrut
# → both directions: what the LOV references, what references the LOV.
```

By step 2 you have the file + line + SQL text and can decide whether the bug is in the query, the filter binding, or a downstream computation.

## `uc-apx search` details

- Case-insensitive. Matches across: component names, IDs, scalar property values, and the text inside `sql`, `plsql`, `javascript-browser`, `css`, `html` code blocks.
- Returns: kind, ID, name, file, line — one match per construct (not per occurrence inside the construct).
- Quote multi-word terms: `uc-apx search "raise salary"`.
- For very common terms, narrow first: search for a less common token in the same SQL.

## `uc-apx refs` details

- Pass an exact ID (`APEX$<digits>` or a named alias). The CLI doesn't fuzzy-match on this command.
- Returns every component that names this ID in any property (top-level or nested block). Includes the property path, e.g. `source.breadcrumb`, `lov.lov`, `authorization`.
- An LOV with 50 usages is a hot dependency — read carefully before editing.

## `uc-apx deps` details

- Returns two arrays: `dependsOn` (what this component references) and `dependedBy` (what references this component).
- Each edge has a `depth` field — depth `1` is direct, higher values are transitive. Use depth `1` to gauge blast radius; use higher depths to see how a change propagates.

## Common pitfalls

- **Don't trust the first search hit.** If the keyword is generic, scroll all results before drilling into one.
- **`@aliasName` only works in `refs` if the alias is the construct's `ID`.** If a region's name is `Sales History` but its ID is `APEX$1234...`, `uc-apx refs "Sales History"` won't find usages — pass the ID instead.
- **Component dumps can be huge — that's what the default summary avoids.** `uc-apx component <id>` shows the node's own properties plus its immediate children as stubs (kind/id/name/type + a `components` descendant count); reach for `--detail` only when you actually need the full recursive tree. Either way you can still slice with `jq '.properties'`.
- **For pages, prefer `uc-apx page` over `uc-apx component`.** Both work, but `page` returns the more structured shape with regions/items/buttons broken out.

## Reference

- Search source: [cmd/search.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/search.go)
- Refs source: [cmd/refs.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/refs.go)
- Deps source: [cmd/deps.go](https://github.com/United-Codes/uc-apx/blob/main/cmd/deps.go)
- Index cross-references: [index/index.go](https://github.com/United-Codes/uc-apx/blob/main/index/index.go)
