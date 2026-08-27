---
name: analyze-db-dependencies
description: Use `uc-apx schema` to find which database objects (tables, views, packages, functions) an apexlang app touches and where each is used. Reach for it for impact analysis ("what breaks if I drop table X", "which pages call package Y", "what does this app read"), data-model orientation before an edit, or auditing external-schema coupling. It is a heuristic static scan of SQL/PL-SQL text — no database connection — so treat results as leads to verify, not gospel.
---

# Analyze Db Dependencies

Read and follow the canonical project skill at
[`../../../.agents/skills/uc-apx/analyze-db-dependencies/SKILL.md`](../../../.agents/skills/uc-apx/analyze-db-dependencies/SKILL.md).
Load its referenced files only when relevant to the task.
