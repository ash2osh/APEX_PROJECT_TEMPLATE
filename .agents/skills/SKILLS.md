# Skills Index

Every skill in this repo lives under one of the three group folders below,
as `<group>/<skill-name>/SKILL.md`. This file is a scannable index — name,
one-line purpose, and when to reach for it — so you don't have to open 27
folders to find the right one. `.claude/skills/<skill-name>/SKILL.md` has a
thin pointer for each, matching Claude Code's required flat discovery
layout; the full content lives here.

## `uc-apx/` — apexlang (`.apx`) editing

Conditional on the `uc-apx` CLI being installed — see
[`.agents/workflows/uc-apx.md`](../workflows/uc-apx.md) for the availability
check and fallback. Start with `getting-started`.

| Skill | Use when |
|---|---|
| [getting-started](uc-apx/getting-started/SKILL.md) | Any task touching `.apx` files — start here first. Routes to the right skill below and states the mandatory validate gate. |
| [navigate-app](uc-apx/navigate-app/SKILL.md) | Orienting in an unfamiliar apexlang project, or finding where a feature lives before reading files. |
| [investigate-component](uc-apx/investigate-component/SKILL.md) | A symptom or bug report needs to be traced to the responsible page, region, or shared component. |
| [inspect-construct-schema](uc-apx/inspect-construct-schema/SKILL.md) | Before hand-editing a construct — learn its conventional properties/shape instead of guessing keys. |
| [create-page](uc-apx/create-page/SKILL.md) | Scaffolding a new APEX page (form, report, dashboard). |
| [add-region-or-item-to-page](uc-apx/add-region-or-item-to-page/SKILL.md) | Adding a region, page item, button, process, or branch to an existing page. |
| [edit-shared-component](uc-apx/edit-shared-component/SKILL.md) | Hand-editing shared components (authentications, app-items, page-groups, LOV entries) with no dedicated scaffolder. |
| [edit-authorization](uc-apx/edit-authorization/SKILL.md) | Creating, editing, applying, or removing an authorization scheme. |
| [delete-component](uc-apx/delete-component/SKILL.md) | Removing any apexlang construct — region, item, button, page, etc. |
| [audit-authorization](uc-apx/audit-authorization/SKILL.md) | A whole-app authorization review — what exists, where it's used, what's unprotected. |
| [analyze-db-dependencies](uc-apx/analyze-db-dependencies/SKILL.md) | Impact analysis — which DB objects an app touches, what breaks if one changes. |
| [validate-after-edit](uc-apx/validate-after-edit/SKILL.md) | After any `.apx` edit, before declaring it done — mandatory verification gate. |

## `sqlcl-mcp-r0/` — SQLcl MCP at restriction level 0

One skill; see [`.agents/skills/sqlcl-mcp-r0/SKILL.md`](sqlcl-mcp-r0/SKILL.md).
Use whenever an agent operates Oracle SQLcl MCP with explicit `-R 0` — SQL,
PL/SQL, SQLcl commands, scripts, filesystem/OS commands, APEX, ORDS, Git,
Liquibase, diagnostics, or client configuration.

## `superpowers/` — general development workflow

Vendored from the [superpowers](https://github.com/obra/superpowers) skill
library (MIT License — see [`superpowers/LICENSE`](superpowers/LICENSE)).
General software-engineering process, not APEX/Oracle-specific. Start with
`using-superpowers`.

| Skill | Use when |
|---|---|
| [using-superpowers](superpowers/using-superpowers/SKILL.md) | Starting any conversation — establishes how to find and use skills before any other action. |
| [brainstorming](superpowers/brainstorming/SKILL.md) | Before any creative work — new features, components, functionality, or behavior changes. |
| [writing-plans](superpowers/writing-plans/SKILL.md) | You have a spec or requirements for a multi-step task, before touching code. |
| [test-driven-development](superpowers/test-driven-development/SKILL.md) | Implementing any feature or bugfix, before writing implementation code. |
| [systematic-debugging](superpowers/systematic-debugging/SKILL.md) | Any bug, test failure, or unexpected behavior, before proposing fixes. |
| [using-git-worktrees](superpowers/using-git-worktrees/SKILL.md) | Starting feature work that needs isolation, or before executing an implementation plan. |
| [executing-plans](superpowers/executing-plans/SKILL.md) | You have a written implementation plan to execute with review checkpoints. |
| [subagent-driven-development](superpowers/subagent-driven-development/SKILL.md) | Executing a plan's independent tasks via fresh subagents in the current session. |
| [dispatching-parallel-agents](superpowers/dispatching-parallel-agents/SKILL.md) | 2+ independent tasks with no shared state or sequential dependency. |
| [requesting-code-review](superpowers/requesting-code-review/SKILL.md) | Completing a task or major feature, or before merging, to verify it meets requirements. |
| [receiving-code-review](superpowers/receiving-code-review/SKILL.md) | Acting on code review feedback — rigor and verification, not reflexive agreement. |
| [verification-before-completion](superpowers/verification-before-completion/SKILL.md) | About to claim work is complete/fixed/passing, before committing or opening a PR. |
| [finishing-a-development-branch](superpowers/finishing-a-development-branch/SKILL.md) | Implementation is done and tests pass — deciding how to integrate the work. |
| [writing-skills](superpowers/writing-skills/SKILL.md) | Creating or editing a skill, or verifying one works before deployment. |
