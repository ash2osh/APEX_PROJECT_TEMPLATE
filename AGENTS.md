# Agent entry point

This is the portable project instruction entry point for agents that discover
`AGENTS.md` by convention.

Before non-trivial work, read these files in order:

1. [`agents.md`](agents.md) — project-specific Oracle APEX, database, and delivery rules.
2. [`self_improve.md`](self_improve.md) — durable, evidence-backed lessons.
3. [`.agents/rules/agent-safety.md`](.agents/rules/agent-safety.md) — shared safety and verification gates.

When a task uses SQLcl MCP with restriction level 0, also read
[`.agents/skills/sqlcl-mcp-r0/SKILL.md`](.agents/skills/sqlcl-mcp-r0/SKILL.md).

When a task edits files under `apps/`, also read
[`.agents/workflows/uc-apx.md`](.agents/workflows/uc-apx.md) — it explains
when the optional `uc-apx` CLI is available and how to fall back when it is
not.

For `/init`, `/init <project-name>`, `$initialize-project`, or a natural-
language request to initialize, instantiate, or configure this cloned
template, read and follow
[`.agents/skills/initialize-project/SKILL.md`](.agents/skills/initialize-project/SKILL.md).

For project setup, if `.env` exists and its safely parsed
`INSTALL_UC_APX` value is `true`, read and follow
[`.agents/skills/install-uc-apx/SKILL.md`](.agents/skills/install-uc-apx/SKILL.md).
Never execute `.env` as shell code.

The referenced files are authoritative together. Do not replace project
rules with this bootstrap file, and preserve unrelated working-tree changes.
