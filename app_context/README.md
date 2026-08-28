# app_context/ — per-app knowledge base

A persistent, durable knowledge base for each APEX application under `apps/`,
separate from `self_improve.md` (which is repository-wide), editable APEX
source under `apps/`, and the generated `database/` mirror. Where
`self_improve.md` records
lessons about how to work *in this repo*, `app_context/` records what is
actually true *about one application* — its purpose, its non-obvious
patterns, its known bugs and workarounds.

## Convention

One folder per application:

```
app_context/<app-id>/
  context.md          # required — see template below
  1-pages/             # optional — one file per page, only when a page is
                        # complex enough to need its own notes
  2-database/           # optional — data-model notes specific to this app
  3-tests/               # optional — test walkthroughs/scenarios specific
                          # to this app (see agents.md #8 Testing Convention)
```

Create the folder the first time you do non-trivial work on an app; it
does not need to exist before then.

## Rule

Before touching an app under `apps/<parsing-schema>/<app-id>/`, check whether
`app_context/<app-id>/context.md` already exists and
read it first — it may already document the exact pattern, bug, or
constraint you're about to rediscover. After resolving a non-trivial issue,
or establishing knowledge about the app that would save real time next
time, update it. Keep entries factual and durable — this is not a status
log or a changelog; see `self_improve.md`'s "What Not to Record" for the
same discipline applied here (no secrets, no transient status, no
speculation).

## `context.md` template

```markdown
# <application name> (app <app-id>)

## Purpose

What this application is for, and who uses it.

## Architecture Notes

Key pages and what they do. Key database objects (tables/views/packages)
this app depends on, and anything non-obvious about how it uses them.

## Known Patterns

Conventions specific to this app that a new page/change should follow —
things that aren't obvious from reading one page in isolation.

## Known Issues / Gotchas

Bugs, workarounds, or things that look wrong but are actually intentional
(and why). Update this whenever a non-trivial issue gets resolved.

## Last Updated

YYYY-MM-DD — one line on what changed and why.
```
